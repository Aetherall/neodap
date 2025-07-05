local M = {}

-- Configuration for different marker types
local MARKER_CONFIG = {
  virtual_text = {
    symbol = "●◆○✗",  -- Common symbols used
    annotation = "vt"
  },
  sign = {
    annotation = "sign"
  },
  highlight = {
    annotation = "hl"
  }
}

-- Helper to get all extmarks for a buffer
local function get_all_extmarks(bufnr)
  local all_extmarks = {}
  
  -- Method 1: Check common namespace names
  local common_namespaces = {
    "neodap_breakpoint_virtual_text",
    "HighlightCurrentFrame", 
    "dap_breakpoints",
    "neodap"
  }
  
  for _, ns_name in ipairs(common_namespaces) do
    local ns_id = vim.api.nvim_create_namespace(ns_name)
    local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {details = true})
    
    for _, extmark in ipairs(extmarks) do
      table.insert(all_extmarks, {
        namespace = ns_name,
        id = extmark[1],
        line = extmark[2],
        col = extmark[3],
        details = extmark[4] or {}
      })
    end
  end
  
  -- Method 2: Check for dynamically created namespaces by trying common patterns
  -- Look for namespaces that start with expected prefixes
  local dynamic_patterns = {
    "neodap_bpvt_table:", -- API-based namespaces
  }
  
  -- Since we can't easily enumerate all namespaces, we'll try to get them from
  -- any loaded plugins that might expose their namespace info
  -- This is a more targeted approach than brute force
  
  -- Try a small range of namespace IDs that are commonly used
  -- But wrap in pcall to handle invalid ones gracefully
  for ns_id = 1, 50 do
    local success, extmarks = pcall(vim.api.nvim_buf_get_extmarks, bufnr, ns_id, 0, -1, {details = true})
    if success and #extmarks > 0 then
      -- Check if we already processed this namespace by comparing extmarks
      local already_found = false
      for _, existing in ipairs(all_extmarks) do
        if existing.id == extmarks[1][1] and existing.line == extmarks[1][2] and existing.col == extmarks[1][3] then
          already_found = true
          break
        end
      end
      
      if not already_found then
        -- Found new namespace with extmarks
        local Logger = require("neodap.tools.logger")
        local log = Logger.get()
        log:debug("SNAPSHOT: Found extmarks in namespace ID", ns_id, "- count:", #extmarks)
        
        -- Log detailed contents of this namespace
        local namespace_contents = {}
        for _, extmark in ipairs(extmarks) do
          local content = {
            id = extmark[1],
            line = extmark[2],
            col = extmark[3],
            virt_text = extmark[4] and extmark[4].virt_text and extmark[4].virt_text[1] and extmark[4].virt_text[1][1] or "none",
            hl_group = extmark[4] and extmark[4].virt_text and extmark[4].virt_text[1] and extmark[4].virt_text[1][2] or "none",
            details = extmark[4] or {}
          }
          table.insert(namespace_contents, content)
          table.insert(all_extmarks, {
            namespace = "dynamic_ns_" .. tostring(ns_id),
            namespace_id = ns_id,
            id = extmark[1], 
            line = extmark[2],
            col = extmark[3],
            details = extmark[4] or {}
          })
        end
        log:info("NAMESPACE_CONTENTS: Namespace", ns_id, "contains:", vim.inspect(namespace_contents))
      end
    end
  end
  
  return all_extmarks
end

-- Helper to get all signs for a buffer
local function get_all_signs(bufnr)
  local all_signs = {}
  local signs_data = vim.fn.sign_getplaced(bufnr)
  
  if #signs_data > 0 and signs_data[1].signs then
    for _, sign in ipairs(signs_data[1].signs) do
      table.insert(all_signs, {
        line = sign.lnum,
        name = sign.name,
        group = sign.group,
        id = sign.id,
        priority = sign.priority
      })
    end
  end
  
  return all_signs
end

-- Helper to build line annotation
local function build_line_annotation(line_markers)
  if #line_markers == 0 then
    return ""
  end
  
  local annotations = {}
  
  for _, marker in ipairs(line_markers) do
    if marker.type == "virtual_text" then
      table.insert(annotations, string.format("vt:%s", marker.text))
    elseif marker.type == "sign" then
      table.insert(annotations, string.format("sign:%s", marker.text or marker.name))
    elseif marker.type == "highlight" then
      table.insert(annotations, string.format("hl:%s[%d:%d]", marker.hl_group, marker.col, marker.end_col or marker.col))
    end
  end
  
  if #annotations > 0 then
    return "  // ◄ " .. table.concat(annotations, " ")
  end
  
  return ""
end

-- Main function to capture buffer snapshot
function M.capture_buffer_snapshot(bufnr)
  local Logger = require("neodap.tools.logger")
  local log = Logger.get()
  log:info("SNAPSHOT_CAPTURE: Starting buffer snapshot capture for buffer", bufnr, "at timestamp", os.clock())
  
  -- Validate buffer
  if not bufnr or bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    log:warn("SNAPSHOT_CAPTURE: Invalid buffer", bufnr)
    return "INVALID_BUFFER"
  end
  
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  -- If buffer is empty but should have content, try to load the file content
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    -- Try to get buffer name and load content
    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    if buf_name and buf_name ~= "" then
      -- Force buffer to load content
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit!")
      end)
      lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end
  end
  
  local extmarks = get_all_extmarks(bufnr)
  local signs = get_all_signs(bufnr)
  
  log:info("SNAPSHOT_CAPTURE: Found", #extmarks, "extmarks and", #signs, "signs")
  if #extmarks > 0 then
    log:debug("SNAPSHOT_CAPTURE: Extmarks:", vim.inspect(extmarks))
    
    -- Group extmarks by namespace for clearer analysis
    local by_namespace = {}
    for _, extmark in ipairs(extmarks) do
      local ns = extmark.namespace or "unknown"
      local ns_id = extmark.namespace_id or "unknown"
      local key = ns .. "_id_" .. ns_id
      if not by_namespace[key] then
        by_namespace[key] = { namespace = ns, namespace_id = ns_id, extmarks = {} }
      end
      table.insert(by_namespace[key].extmarks, {
        id = extmark.id,
        line = extmark.line,
        col = extmark.col,
        virt_text = extmark.details and extmark.details.virt_text and extmark.details.virt_text[1] and extmark.details.virt_text[1][1] or "none"
      })
    end
    
    log:info("SNAPSHOT_BY_NAMESPACE: Extmarks grouped by namespace:", vim.inspect(by_namespace))
  end
  
  -- Organize markers by line
  local markers_by_line = {}
  
  -- Process virtual text extmarks
  for _, extmark in ipairs(extmarks) do
    local line_num = extmark.line + 1  -- Convert to 1-indexed
    
    if not markers_by_line[line_num] then
      markers_by_line[line_num] = {}
    end
    
    if extmark.details.virt_text then
      -- Virtual text marker
      local vt_text = extmark.details.virt_text[1][1]
      table.insert(markers_by_line[line_num], {
        col = extmark.col,
        type = "virtual_text",
        text = vt_text,
        hl_group = extmark.details.virt_text[1][2]
      })
    elseif extmark.details.hl_group then
      -- Highlight marker
      table.insert(markers_by_line[line_num], {
        col = extmark.col,
        end_col = extmark.details.end_col,
        type = "highlight",
        hl_group = extmark.details.hl_group
      })
    end
  end
  
  -- Process signs
  for _, sign in ipairs(signs) do
    local line_num = sign.line
    
    if not markers_by_line[line_num] then
      markers_by_line[line_num] = {}
    end
    
    -- Get sign definition to find the text
    local sign_def = vim.fn.sign_getdefined(sign.name)
    local sign_text = (sign_def and #sign_def > 0) and sign_def[1].text or sign.name
    
    table.insert(markers_by_line[line_num], {
      type = "sign",
      name = sign.name,
      text = sign_text,
      group = sign.group
    })
  end
  
  -- Build the snapshot with inline annotations
  local snapshot_lines = {}
  
  for i, line in ipairs(lines) do
    local line_markers = markers_by_line[i] or {}
    
    -- Add virtual text inline at correct positions
    local annotated_line = line
    
    -- Sort virtual text by column position (reverse order for string insertion)
    local vt_markers = {}
    for _, marker in ipairs(line_markers) do
      if marker.type == "virtual_text" then
        table.insert(vt_markers, marker)
      end
    end
    table.sort(vt_markers, function(a, b) return a.col > b.col end)
    
    -- Insert virtual text at positions
    for _, vt in ipairs(vt_markers) do
      local insert_pos = math.min(vt.col, #annotated_line)
      annotated_line = annotated_line:sub(1, insert_pos) .. vt.text .. annotated_line:sub(insert_pos + 1)
    end
    
    -- Add line annotation for signs and highlights
    local other_markers = {}
    for _, marker in ipairs(line_markers) do
      if marker.type ~= "virtual_text" then
        table.insert(other_markers, marker)
      end
    end
    
    local annotation = build_line_annotation(other_markers)
    
    table.insert(snapshot_lines, annotated_line .. annotation)
  end
  
  local final_snapshot = table.concat(snapshot_lines, "\n")
  log:info("SNAPSHOT_CAPTURE: Completed snapshot capture, length:", #final_snapshot, "at timestamp", os.clock())
  
  return final_snapshot
end

-- Function to compare snapshots (for testing)
function M.compare_snapshots(actual, expected)
  -- Handle nil inputs
  if not actual or not expected then
    return false, "One or both snapshots are nil"
  end
  
  -- Function to strip common indentation from multiline strings
  local function strip_common_indent(text)
    local lines = vim.split(text, "\n")
    
    -- Remove leading/trailing empty lines
    while #lines > 0 and lines[1]:match("^%s*$") do
      table.remove(lines, 1)
    end
    while #lines > 0 and lines[#lines]:match("^%s*$") do
      table.remove(lines, #lines)
    end
    
    if #lines == 0 then
      return ""
    end
    
    -- Find minimum indentation (excluding empty lines)
    local min_indent = math.huge
    for _, line in ipairs(lines) do
      if not line:match("^%s*$") then -- Skip empty lines
        local indent = line:match("^(%s*)")
        min_indent = math.min(min_indent, #indent)
      end
    end
    
    -- Strip common indentation
    if min_indent > 0 and min_indent < math.huge then
      for i, line in ipairs(lines) do
        if not line:match("^%s*$") then -- Skip empty lines
          lines[i] = line:sub(min_indent + 1)
        else
          lines[i] = ""
        end
      end
    end
    
    return table.concat(lines, "\n")
  end
  
  -- Normalize whitespace and strip common indentation
  local function normalize(text)
    local stripped = strip_common_indent(text)
    return stripped:gsub("%s+$", ""):gsub("\n+$", "")
  end
  
  local norm_actual = normalize(actual)
  local norm_expected = normalize(expected)
  
  if norm_actual == norm_expected then
    return true, nil
  end
  
  -- Generate diff for better error messages
  local actual_lines = vim.split(norm_actual, "\n")
  local expected_lines = vim.split(norm_expected, "\n")
  
  local diff = {}
  local max_lines = math.max(#actual_lines, #expected_lines)
  
  for i = 1, max_lines do
    local actual_line = actual_lines[i] or "<missing>"
    local expected_line = expected_lines[i] or "<missing>"
    
    if actual_line ~= expected_line then
      table.insert(diff, string.format("Line %d:", i))
      table.insert(diff, string.format("  Expected: %s", expected_line))
      table.insert(diff, string.format("  Actual:   %s", actual_line))
      table.insert(diff, "")
    end
  end
  
  return false, table.concat(diff, "\n")
end

-- Helper function to expect snapshot match (for test integration)
function M.expect_buffer_snapshot(bufnr, expected_snapshot)
  local actual_snapshot = M.capture_buffer_snapshot(bufnr)
  local matches, diff = M.compare_snapshots(actual_snapshot, expected_snapshot)
  
  if not matches then
    error("Buffer snapshot mismatch:\n\n" .. diff .. "\n\nFull actual snapshot:\n" .. actual_snapshot)
  end
  
  return true
end

-- Helper to clear all visual markers from a buffer
function M.clear_buffer_markers(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  
  -- Clear signs
  vim.fn.sign_unplace("*", { buffer = bufnr })
  
  -- Clear extmarks from common namespaces
  local common_namespaces = {
    "neodap_breakpoint_virtual_text",
    "HighlightCurrentFrame", 
    "dap_breakpoints",
    "neodap"
  }
  
  for _, ns_name in ipairs(common_namespaces) do
    local ns_id = vim.api.nvim_create_namespace(ns_name)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  end
end

-- Helper to reset all breakpoints and ensure clean state
function M.reset_breakpoints(api)
  local nio = require("nio")
  local Logger = require("neodap.tools.logger")
  local log = Logger.get()
  
  log:info("RESET: Starting breakpoint reset process")
  
  -- The comprehensive cleanup is now handled by prepare.lua
  -- This function just does a final verification
  
  -- Count current breakpoints after prepare.lua cleanup
  local breakpoint_count = 0
  local breakpoint_ids = {}
  for breakpoint in api:breakpoints().breakpoints:each() do
    breakpoint_count = breakpoint_count + 1
    table.insert(breakpoint_ids, breakpoint.id)
  end
  
  if breakpoint_count > 0 then
    log:warn("RESET: Found", breakpoint_count, "remaining breakpoints after prepare cleanup:", vim.inspect(breakpoint_ids))
    
    -- Emergency cleanup - this shouldn't be needed if prepare.lua is working
    for breakpoint in api:breakpoints().breakpoints:each() do
      log:debug("RESET: Emergency removal of breakpoint:", breakpoint.id)
      api:breakpoints():toggleBreakpoint(breakpoint.location)
    end
  else
    log:debug("RESET: Confirmed clean state - no breakpoints found")
  end
  
  log:info("RESET: Breakpoint reset process completed")
  
  -- Wait a bit for any final cleanup to complete
  nio.sleep(200)
end

-- Helper to wait for breakpoint and capture snapshot with minimal boilerplate
function M.wait_for_breakpoint_snapshot(api, filename, expected_snapshot, plugins)
  plugins = plugins or {}
  
  local nio = require("nio")
  local event = nio.control.event()
  local captured_snapshot = nil
  
  -- Reset state before starting
  M.reset_breakpoints(api)
  
  api:onBreakpoint(function(breakpoint)
    require("nio").run(function()
      require("nio").sleep(300)  -- Give time for visual elements
      
      local path = breakpoint.location.path
      local future = require("nio").control.future()
      -- vim.schedule(function()
        local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(path))
        future.set(bufnr ~= -1 and bufnr or nil)
      -- end)
      local bufnr = future.wait()
      
      if bufnr then
        -- vim.schedule(function()
          -- Force load the buffer content
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("silent! edit!")
          end)
          
          -- Wait a bit for visual markers to be placed
          vim.defer_fn(function()
            captured_snapshot = M.capture_buffer_snapshot(bufnr)
            
            if expected_snapshot then
              M.expect_buffer_snapshot(bufnr, expected_snapshot)
            end
            
            event.set()
          end, 100)
        -- end)
      end
    end)
  end)
  
  -- Load plugins before session starts (only if not already loaded)
  for _, plugin in ipairs(plugins) do
    -- Track loaded plugins per API to prevent duplicates
    if not api._loaded_plugins then
      api._loaded_plugins = {}
    end
    
    if not api._loaded_plugins[plugin.name] then
      local Logger = require("neodap.tools.logger")
      local log = Logger.get()
      log:info("PLUGIN: Loading", plugin.name, "for first time on this API")
      plugin.plugin(api)
      api._loaded_plugins[plugin.name] = true
    else
      local Logger = require("neodap.tools.logger")
      local log = Logger.get()
      log:debug("PLUGIN: Skipping", plugin.name, "- already loaded on this API")
    end
  end
  
  api:onSession(function(session)
    session:onSourceLoaded(function(source)
      local filesource = source:asFile()
      if filesource and filesource:filename() == filename then
        filesource:addBreakpoint({ line = 3 })
      end
    end)
  end)
  
  vim.wait(15000, event.is_set)
  return captured_snapshot
end

-- Helper to setup multiple breakpoints and capture snapshot
function M.wait_for_multiple_breakpoints_snapshot(api, filename, breakpoint_lines, expected_snapshot, plugins)
  plugins = plugins or {}
  
  local nio = require("nio")
  local event = nio.control.event()
  local breakpoint_count = 0
  local captured_snapshot = nil
  
  -- Reset state before starting
  M.reset_breakpoints(api)
  
  api:onBreakpoint(function(breakpoint)
    breakpoint_count = breakpoint_count + 1
    
    if breakpoint_count >= #breakpoint_lines then
      require("nio").run(function()
        require("nio").sleep(500)
        
        local path = breakpoint.location.path
        local future = require("nio").control.future()
        -- vim.schedule(function()
          local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(path))
          future.set(bufnr ~= -1 and bufnr or nil)
        -- end)
        local bufnr = future.wait()
        
        if bufnr then
          -- vim.schedule(function()
            -- Force load the buffer content
            vim.api.nvim_buf_call(bufnr, function()
              vim.cmd("silent! edit!")
            end)
            
            -- Wait a bit for visual markers to be placed
            vim.defer_fn(function()
              captured_snapshot = M.capture_buffer_snapshot(bufnr)
              
              if expected_snapshot then
                M.expect_buffer_snapshot(bufnr, expected_snapshot)
              end
              
              event.set()
            end, 100)
          -- end)
        end
      end)
    end
  end)
  
  -- Load plugins before session starts (only if not already loaded)
  for _, plugin in ipairs(plugins) do
    -- Track loaded plugins per API to prevent duplicates
    if not api._loaded_plugins then
      api._loaded_plugins = {}
    end
    
    if not api._loaded_plugins[plugin.name] then
      local Logger = require("neodap.tools.logger")
      local log = Logger.get()
      log:info("PLUGIN: Loading", plugin.name, "for first time on this API")
      plugin.plugin(api)
      api._loaded_plugins[plugin.name] = true
    else
      local Logger = require("neodap.tools.logger")
      local log = Logger.get()
      log:debug("PLUGIN: Skipping", plugin.name, "- already loaded on this API")
    end
  end
  
  api:onSession(function(session)
    session:onSourceLoaded(function(source)
      local filesource = source:asFile()
      if filesource and filesource:filename() == filename then
        -- Add all breakpoints
        for _, line in ipairs(breakpoint_lines) do
          filesource:addBreakpoint({ line = line })
        end
      end
    end)
  end)
  
  vim.wait(15000, event.is_set)
  return captured_snapshot
end

-- Debug function to print current buffer snapshot
function M.debug_buffer_snapshot(bufnr)
  print("=== BUFFER DEBUG INFO ===")
  print("Buffer ID:", bufnr)
  print("Buffer valid:", vim.api.nvim_buf_is_valid(bufnr))
  print("Buffer name:", vim.api.nvim_buf_get_name(bufnr))
  
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  print("Line count:", #lines)
  print("First few lines:")
  for i = 1, math.min(5, #lines) do
    print("  " .. i .. ": " .. (lines[i] or "<nil>"))
  end
  
  local extmarks = get_all_extmarks(bufnr)
  print("Extmarks found:", #extmarks)
  for i, mark in ipairs(extmarks) do
    print("  Extmark " .. i .. ":", vim.inspect(mark))
  end
  
  local signs = get_all_signs(bufnr)
  print("Signs found:", #signs)
  for i, sign in ipairs(signs) do
    print("  Sign " .. i .. ":", vim.inspect(sign))
  end
  
  print("========================")
  
  local snapshot = M.capture_buffer_snapshot(bufnr)
  print("=== BUFFER SNAPSHOT ===")
  print(snapshot)
  print("=======================")
  return snapshot
end

-- Simple helper to wait for a buffer to be loaded and capture its snapshot
function M.wait_and_capture_snapshot(filename, wait_ms)
  wait_ms = wait_ms or 300
  local nio = require("nio")
  
  -- Try multiple methods to find the buffer
  local bufnr = -1
  
  -- Method 1: Check all buffers for matching filename
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:find(filename) or name:find(filename:gsub("%.js$", "")) then
      bufnr = buf
      break
    end
  end
  
  -- Method 2: Try by full path
  if bufnr == -1 then
    local full_path = vim.fn.fnamemodify(filename, ":p")
    bufnr = vim.fn.bufnr(full_path)
  end
  
  -- Method 3: Try by URI
  if bufnr == -1 then
    local uri = vim.uri_from_fname(vim.fn.fnamemodify(filename, ":p"))
    bufnr = vim.uri_to_bufnr(uri)
  end
  
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    error("Buffer not found for file: " .. filename)
  end
  
  -- Force load the buffer with vim.schedule
  local loaded = false
  local future = nio.control.future()
  
  vim.schedule(function()
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent! edit!")
    end)
    
    -- Check if we need to force load
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if line_count <= 1 then
      local buf_name = vim.api.nvim_buf_get_name(bufnr)
      if buf_name and buf_name ~= "" then
        vim.cmd("edit " .. vim.fn.fnameescape(buf_name))
      end
    end
    
    loaded = true
    future.set(true)
  end)
  
  -- Wait for buffer to be loaded
  future.wait()
  
  -- Debug: Check buffer state
  local Logger = require("neodap.tools.logger")
  local log = Logger.get()
  log:debug("wait_and_capture_snapshot: Found buffer", bufnr, "for file", filename)
  log:debug("Buffer valid:", vim.api.nvim_buf_is_valid(bufnr))
  log:debug("Buffer loaded:", vim.api.nvim_buf_is_loaded(bufnr))
  log:debug("Buffer name:", vim.api.nvim_buf_get_name(bufnr))
  log:debug("Line count:", vim.api.nvim_buf_line_count(bufnr))
  
  -- Wait for visual elements to be placed
  nio.sleep(wait_ms)
  
  -- Capture and return snapshot
  return M.capture_buffer_snapshot(bufnr)
end

-- Helper to assert snapshot matches expected
function M.assert_snapshot(actual, expected)
  local matches, diff = M.compare_snapshots(actual, expected)
  if not matches then
    error("Buffer snapshot mismatch:\n\n" .. diff .. "\n\nFull actual snapshot:\n" .. actual)
  end
end

-- Helper to wait for condition and capture snapshot
function M.wait_for_condition_and_capture(filename, condition_fn, timeout_ms, wait_ms)
  timeout_ms = timeout_ms or 15000
  wait_ms = wait_ms or 300
  
  -- Wait for condition
  local success = vim.wait(timeout_ms, condition_fn)
  if not success then
    error("Timeout waiting for condition")
  end
  
  -- Capture snapshot after condition is met
  return M.wait_and_capture_snapshot(filename, wait_ms)
end

-- Convenience method that captures a snapshot and asserts it matches expected
function M.expectSnapshotMatching(filename, expected)
  local actual = M.wait_and_capture_snapshot(filename, 300)
  M.assert_snapshot(actual, expected)
end

return M