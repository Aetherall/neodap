local nio = require("nio")

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
  error("TerminalSnapshot must be called from within a .spec.lua file")
end

-- Get all highlights in the current buffer
local function get_buffer_highlights()
  local highlights = {}
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Get all namespaces
  local namespaces = vim.api.nvim_get_namespaces()
  
  for name, ns_id in pairs(namespaces) do
    -- Skip empty namespace names
    if name and name ~= "" then
      -- Get highlights for this namespace
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {details = true})
      
      for _, mark in ipairs(marks) do
        local mark_id, row, col, details = mark[1], mark[2], mark[3], mark[4]
        
        if details and details.hl_group then
          local highlight = {
            name = details.hl_group,
            namespace = name,
            start_row = row + 1, -- Convert to 1-based
            start_col = col + 1, -- Convert to 1-based
            end_row = row + 1,
            end_col = col + 1
          }
          
          -- If it's a range highlight, get the end position
          if details.end_row then
            highlight.end_row = details.end_row + 1
            highlight.end_col = details.end_col and (details.end_col + 1) or highlight.end_col
          end
          
          table.insert(highlights, highlight)
        end
      end
    end
  end
  
  return highlights
end

-- Capture the current terminal screen state
local function capture_screen()
  -- Force a redraw to ensure buffer content is visible
  vim.cmd("redraw")
  vim.cmd("redraw!")
  
  local screen = {
    lines = {},
    cursor = vim.api.nvim_win_get_cursor(0),
    mode = vim.api.nvim_get_mode().mode,
    size = {vim.o.lines, vim.o.columns},
    highlights = get_buffer_highlights()
  }
  
  -- Capture each line of the terminal
  for row = 1, vim.o.lines do
    local line = ""
    for col = 1, vim.o.columns do
      local char = vim.fn.screenchar(row, col)
      if char == 0 then
        line = line .. " "
      else
        line = line .. vim.fn.nr2char(char)
      end
    end
    -- Remove trailing whitespace for cleaner snapshots
    line = line:gsub("%s+$", "")
    table.insert(screen.lines, line)
  end
  
  -- Cursor position is already captured in screen.cursor and shown in header
  -- No need to render cursor character as it can overlap with extmarks
  
  return screen
end

-- Format screen data for embedding in test file
local function format_screen_for_embedding(screen, name)
  local lines = {}
  
  -- Header with clear delimiters
  table.insert(lines, "")
  table.insert(lines, "--[[ TERMINAL SNAPSHOT: " .. name)
  table.insert(lines, "Size: " .. screen.size[1] .. "x" .. screen.size[2])
  table.insert(lines, "Cursor: [" .. screen.cursor[1] .. ", " .. screen.cursor[2] .. "] (line " .. screen.cursor[1] .. ", col " .. screen.cursor[2] .. ")")
  table.insert(lines, "Mode: " .. screen.mode)
  
  -- Add highlights information
  if screen.highlights and #screen.highlights > 0 then
    table.insert(lines, "")
    table.insert(lines, "Highlights:")
    for _, hl in ipairs(screen.highlights) do
      local range_str
      if hl.start_row == hl.end_row then
        if hl.start_col == hl.end_col then
          range_str = string.format("[%d:%d]", hl.start_row, hl.start_col)
        else
          range_str = string.format("[%d:%d-%d:%d]", hl.start_row, hl.start_col, hl.end_row, hl.end_col)
        end
      else
        range_str = string.format("[%d:%d-%d:%d]", hl.start_row, hl.start_col, hl.end_row, hl.end_col)
      end
      table.insert(lines, string.format("  %s%s", hl.name, range_str))
    end
  end
  
  table.insert(lines, "")
  
  -- Screen content with line indicators, making tabs more visible
  for i, line in ipairs(screen.lines) do
    -- Make tabs visible in the comments for better understanding
    local visible_line = line:gsub("\t", "→")
    table.insert(lines, string.format("%2d| %s", i, visible_line))
  end
  
  table.insert(lines, "]]")
  
  return lines
end

-- Parse existing snapshot from test file
local function parse_snapshot_from_file(filepath, name)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end
  
  local content = file:read("*a")
  file:close()
  
  -- Look for the snapshot block
  local pattern = "%-%-%[%[ TERMINAL SNAPSHOT: " .. name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "\n(.-)\n%]%]"
  local snapshot_content = content:match(pattern)
  
  if not snapshot_content then
    return nil
  end
  
  -- Parse the snapshot content
  local lines = vim.split(snapshot_content, "\n")
  local screen = {
    lines = {},
    cursor = {1, 1},
    mode = "n",
    size = {24, 80}
  }
  
  for _, line in ipairs(lines) do
    if line:match("^Size: ") then
      local height, width = line:match("Size: (%d+)x(%d+)")
      screen.size = {tonumber(height), tonumber(width)}
    elseif line:match("^Cursor: ") then
      local row, col = line:match("Cursor: %[(%d+), (%d+)%]")
      screen.cursor = {tonumber(row), tonumber(col)}
    elseif line:match("^Mode: ") then
      screen.mode = line:match("Mode: (%w+)")
    elseif line:match("^%s*%d+|") then
      -- Extract screen content line
      local content_line = line:match("^%s*%d+| (.*)")
      if content_line then
        table.insert(screen.lines, content_line)
      end
    end
  end
  
  return screen
end

-- Compare two screens
local function compare_screens(expected, actual)
  local differences = {}
  
  -- Compare basic properties
  if expected.mode ~= actual.mode then
    table.insert(differences, "Mode differs: expected '" .. expected.mode .. "', got '" .. actual.mode .. "'")
  end
  
  if expected.cursor[1] ~= actual.cursor[1] or expected.cursor[2] ~= actual.cursor[2] then
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
        "Line %d differs:\n  Expected: '%s'\n  Actual:   '%s'",
        i, expected_line, actual_line
      ))
    end
  end
  
  return differences
end

-- Update or append snapshot to test file
local function update_snapshot_in_file(filepath, name, screen)
  local file = io.open(filepath, "r")
  if not file then
    error("Cannot read test file: " .. filepath)
  end
  
  local content = file:read("*a")
  file:close()
  
  local formatted_snapshot = table.concat(format_screen_for_embedding(screen, name), "\n")
  
  -- Check if snapshot already exists
  local pattern = "%-%-%[%[ TERMINAL SNAPSHOT: " .. name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "\n.-\n%]%]"
  
  if content:match(pattern) then
    -- Replace existing snapshot (escape % and newlines for gsub replacement)
    local escaped_snapshot = formatted_snapshot:gsub("%%", "%%%%"):gsub("\n", "%%n")
    content = content:gsub(pattern, function() return formatted_snapshot end)
  else
    -- Append new snapshot at the end
    content = content .. "\n" .. formatted_snapshot
  end
  
  -- Write back to file
  file = io.open(filepath, "w")
  if not file then
    error("Cannot write to test file: " .. filepath)
  end
  
  file:write(content)
  file:close()
end

-- Main function to capture and compare terminal snapshot
function TerminalSnapshot.capture(name)
  local test_file = get_current_test_file()
  local current_screen = capture_screen()
  
  -- Try to find existing snapshot in the test file
  local existing_snapshot = parse_snapshot_from_file(test_file, name)
  
  if existing_snapshot then
    -- Compare with existing snapshot
    local differences = compare_screens(existing_snapshot, current_screen)
    
    if #differences > 0 then
      -- Update the snapshot with new content
      update_snapshot_in_file(test_file, name, current_screen)
      
      -- Create error message with diff
      local error_msg = "\n! Terminal snapshot '" .. name .. "' differs:\n\n" .. table.concat(differences, "\n")
      error_msg = error_msg .. "\n\nSnapshot updated in " .. test_file
      
      print(error_msg)
      error(error_msg)
    else
      print("\n✓ Terminal snapshot '" .. name .. "' matches")
    end
  else
    -- First time: create new snapshot
    update_snapshot_in_file(test_file, name, current_screen)
    print("\n📸 Created terminal snapshot '" .. name .. "' in " .. vim.fn.fnamemodify(test_file, ":t"))
  end
end

-- Region capture function
function TerminalSnapshot.capture_region(name, region)
  local test_file = get_current_test_file()
  
  local screen = {
    lines = {},
    cursor = vim.api.nvim_win_get_cursor(0),
    mode = vim.api.nvim_get_mode().mode,
    size = {region.end_row - region.start_row + 1, region.end_col - region.start_col + 1}
  }
  
  -- Capture only specified region
  for row = region.start_row, region.end_row do
    local line = ""
    for col = region.start_col, region.end_col do
      local char = vim.fn.screenchar(row, col)
      line = line .. (char == 0 and " " or vim.fn.nr2char(char))
    end
    line = line:gsub("%s+$", "")
    table.insert(screen.lines, line)
  end
  
  -- Use same logic as full capture
  local existing_snapshot = parse_snapshot_from_file(test_file, name)
  
  if existing_snapshot then
    local differences = compare_screens(existing_snapshot, screen)
    
    if #differences > 0 then
      update_snapshot_in_file(test_file, name, screen)
      print("\n! Terminal snapshot '" .. name .. "' differs. Updated in " .. test_file)
      error("\n! Terminal snapshot '" .. name .. "' differs:\n\n" .. table.concat(differences, "\n"))
    else
      print("\n✓ Terminal snapshot '" .. name .. "' matches")
    end
  else
    update_snapshot_in_file(test_file, name, screen)
    print("\n📸 Created terminal snapshot '" .. name .. "' in " .. vim.fn.fnamemodify(test_file, ":t"))
  end
end

return TerminalSnapshot