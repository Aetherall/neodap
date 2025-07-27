local nio = require("nio")
local logger = require("neodap.tools.logger")

local TerminalSnapshot = {}

-- Store the original working directory when the module is loaded
local original_cwd = vim.fn.getcwd()

-- Get current test file path (absolute path)
local function get_current_test_file()
  local info = debug.getinfo(3, "S")
  if info and info.source:match("%.spec%.lua$") then
    local file_path = info.source:gsub("^@", "")
    -- If the path is already absolute, return it as is
    if file_path:match("^/") then
      return file_path
    end
    -- Convert relative path to absolute using original working directory
    local original_dir = vim.fn.getcwd()
    vim.api.nvim_set_current_dir(original_cwd)
    local absolute_path = vim.fn.fnamemodify(file_path, ":p")
    vim.api.nvim_set_current_dir(original_dir)
    return absolute_path
  end
  -- Fallback: try to find the test file in the call stack
  for i = 1, 10 do
    info = debug.getinfo(i, "S")
    if info and info.source:match("%.spec%.lua$") then
      local file_path = info.source:gsub("^@", "")
      -- If the path is already absolute, return it as is
      if file_path:match("^/") then
        return file_path
      end
      -- Convert relative path to absolute using original working directory
      local original_dir = vim.fn.getcwd()
      vim.api.nvim_set_current_dir(original_cwd)
      local absolute_path = vim.fn.fnamemodify(file_path, ":p")
      vim.api.nvim_set_current_dir(original_dir)
      return absolute_path
    end
  end
  error("Could not determine test file location for snapshot")
end

-- Generate external snapshot file path from test file and snapshot name
local function get_snapshot_file_path(test_file, snapshot_name)
  -- Extract plugin name and test name from path
  -- e.g., /path/to/Variables4/specs/focus_mode.spec.lua -> Variables4/focus_mode
  local plugin_match = test_file:match("/plugins/([^/]+)/specs/")
  local test_match = test_file:match("/([^/]+)%.spec%.lua$")
  
  if plugin_match and test_match then
    -- Plugin test: snapshots/Variables4/focus_mode/snapshot_name.snapshot
    local snapshots_dir = original_cwd .. "/lua/testing/snapshots/" .. plugin_match .. "/" .. test_match
    return snapshots_dir .. "/" .. snapshot_name .. ".snapshot"
  else
    -- Global test: snapshots/global/test_name/snapshot_name.snapshot
    local test_name = test_file:match("/([^/]+)%.spec%.lua$") or "unknown"
    local snapshots_dir = original_cwd .. "/lua/testing/snapshots/global/" .. test_name
    return snapshots_dir .. "/" .. snapshot_name .. ".snapshot"
  end
end

-- Load external snapshot from file
local function load_external_snapshot(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end
  
  local content = file:read("*all")
  file:close()
  
  if not content or content == "" then
    return nil
  end
  
  local lines = vim.split(content, "\n")
  local screen = {
    cursor = { 1, 0 },
    mode = "n",
    lines = {},
    size = { 24, 80 }
  }
  
  local in_content = false
  for _, line in ipairs(lines) do
    if line == "---" then
      in_content = true
    elseif not in_content then
      -- Parse metadata
      if line:match("^Size: ") then
        local height, width = line:match("Size: (%d+)x(%d+)")
        screen.size = { tonumber(height), tonumber(width) }
      elseif line:match("^Cursor: ") then
        local row, col = line:match("Cursor: %[(%d+), (%d+)%]")
        screen.cursor = { tonumber(row), tonumber(col) }
      elseif line:match("^Mode: ") then
        screen.mode = line:match("Mode: (%w+)")
      end
    else
      -- Screen content line
      table.insert(screen.lines, line)
    end
  end
  
  return screen
end

-- Save external snapshot to file
local function save_external_snapshot(filepath, screen)
  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(filepath, ":h")
  vim.fn.mkdir(dir, "p")
  
  local file = io.open(filepath, "w")
  if not file then
    error("Could not create snapshot file: " .. filepath)
  end
  
  -- Write metadata
  file:write(string.format("Size: %dx%d\n", screen.size[1], screen.size[2]))
  file:write(string.format("Cursor: [%d, %d]\n", screen.cursor[1], screen.cursor[2]))
  file:write(string.format("Mode: %s\n", screen.mode))
  file:write("---\n")
  
  -- Write content
  for _, line in ipairs(screen.lines) do
    file:write(line .. "\n")
  end
  
  file:close()
end

-- Capture current screen state
local function capture_screen()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  
  -- Get window dimensions
  local height = vim.api.nvim_win_get_height(win)
  local width = vim.api.nvim_win_get_width(win)
  
  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(win)
  
  -- Get current mode
  local mode = vim.api.nvim_get_mode().mode
  
  -- Get visible lines
  local lines = {}
  local start_line = vim.fn.line("w0")
  local end_line = vim.fn.line("w$")
  
  for i = start_line, end_line do
    local line = vim.fn.getline(i)
    table.insert(lines, line)
  end
  
  -- Fill remaining lines with empty content if window is larger than content
  while #lines < height do
    table.insert(lines, "")
  end
  
  return {
    cursor = cursor,
    mode = mode,
    lines = lines,
    size = { height, width }
  }
end

-- Compare two screens
local function compare_screens(expected, actual)
  local differences = {}

  -- Compare basic properties
  if expected.mode ~= actual.mode then
    table.insert(differences, "Mode differs: expected '" .. expected.mode .. "', got '" .. actual.mode .. "'")
  end

  -- Allow slight cursor position tolerance
  local cursor_tolerance = 1
  if math.abs(expected.cursor[1] - actual.cursor[1]) > cursor_tolerance or 
     math.abs(expected.cursor[2] - actual.cursor[2]) > cursor_tolerance then
    table.insert(differences, string.format(
      "Cursor differs: expected [%d, %d], got [%d, %d]",
      expected.cursor[1], expected.cursor[2],
      actual.cursor[1], actual.cursor[2]
    ))
  end

  -- Compare line by line
  local max_lines = math.max(#expected.lines, #actual.lines)
  for i = 1, max_lines do
    local expected_line = expected.lines[i] or ""
    local actual_line = actual.lines[i] or ""

    if expected_line ~= actual_line then
      table.insert(differences, string.format(
        "Line %d differs:\n  Expected: %s\n  Actual:   %s",
        i, expected_line, actual_line
      ))
    end
  end

  return differences
end

-- Main capture function - supports both embedded (legacy) and external snapshots
function TerminalSnapshot.capture(name)
  local test_file = get_current_test_file()
  local screen = capture_screen()
  
  -- Always use external snapshots
  local snapshot_file = get_snapshot_file_path(test_file, name)
  local existing = load_external_snapshot(snapshot_file)
  
  if existing then
    local differences = compare_screens(existing, screen)
    
    if #differences > 0 then
      save_external_snapshot(snapshot_file, screen)
      print("📸 Updated external snapshot: " .. name)
      -- Optionally show differences for debugging
      -- print("Differences:\n" .. table.concat(differences, "\n"))
    else
      -- print("✓ External snapshot '" .. name .. "' matches")
    end
  else
    save_external_snapshot(snapshot_file, screen)
    print("📸 Created external snapshot: " .. name .. " -> " .. vim.fn.fnamemodify(snapshot_file, ":t"))
  end
end

-- Utility function for migrating embedded snapshots to external files
function TerminalSnapshot.migrate_embedded_to_external(test_file)
  print("🔄 Migrating embedded snapshots from " .. vim.fn.fnamemodify(test_file, ":t"))
  
  local file = io.open(test_file, "r")
  if not file then
    error("Could not read test file: " .. test_file)
  end
  
  local content = file:read("*all")
  file:close()
  
  local migrated_count = 0
  
  -- Extract all embedded snapshots
  for snapshot_block in content:gmatch("%-%-[[\n]*TERMINAL SNAPSHOT: ([^\n]+)\n(.-)\n]]") do
    local name, body = snapshot_block:match("([^\n]+)\n(.*)")
    if name and body then
      name = name:strip()
      
      -- Parse the embedded snapshot
      local lines = vim.split(body, "\n")
      local screen = {
        cursor = { 1, 0 },
        mode = "n", 
        lines = {},
        size = { 24, 80 }
      }
      
      for _, line in ipairs(lines) do
        if line:match("^Size: ") then
          local height, width = line:match("Size: (%d+)x(%d+)")
          screen.size = { tonumber(height), tonumber(width) }
        elseif line:match("^Cursor: ") then
          local row, col = line:match("Cursor: %[(%d+), (%d+)%]")
          screen.cursor = { tonumber(row), tonumber(col) }
        elseif line:match("^Mode: ") then
          screen.mode = line:match("Mode: (%w+)")
        elseif line:match("^%s*%d+|") then
          -- Extract screen content line
          local content_line = line:match("^%s*%d+| (.*)")
          if content_line then
            -- Restore [[ and ]] that were replaced with [{ and }]
            content_line = content_line:gsub("%[%{", "[[")
            content_line = content_line:gsub("%}%]", "]]")
            table.insert(screen.lines, content_line)
          end
        end
      end
      
      -- Save as external snapshot
      local snapshot_file = get_snapshot_file_path(test_file, name)
      save_external_snapshot(snapshot_file, screen)
      migrated_count = migrated_count + 1
      
      print("  ✓ Migrated: " .. name)
    end
  end
  
  if migrated_count > 0 then
    print("🎯 Migrated " .. migrated_count .. " snapshots to external files")
    print("💡 You can now remove embedded snapshots from " .. vim.fn.fnamemodify(test_file, ":t"))
  else
    print("No embedded snapshots found to migrate")
  end
end

return TerminalSnapshot