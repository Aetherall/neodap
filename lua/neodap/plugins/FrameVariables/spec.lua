local Test = require("spec.helpers.testing")(describe, it)
local BufferSnapshot = require("spec.helpers.buffer_snapshot")
local FrameVariables = require("neodap.plugins.FrameVariables")
local BreakpointManager = require("neodap.plugins.BreakpointManager")
local PrepareHelper = require("spec.helpers.prepare")
local prepare = PrepareHelper.prepare

Test.Describe("FrameVariables plugin", function()

  Test.It("FV_scopes_snapshot - capture variables tree structure", function()
    local api, start = prepare()
    
    local _breakpoints = api:getPluginInstance(BreakpointManager)
    local frame_variables = api:getPluginInstance(FrameVariables)
    
    local variables_ready = Test.spy("variables_ready")
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        local filesource = source:asFile()
        if filesource and filesource:filename() == "loop.js" then
          filesource:addBreakpoint({ line = 3 })
        end
      end)
      
      session:onThread(function(thread)
        thread:onStopped(function()
          variables_ready.trigger()
        end)
      end)
    end)
    
    start("loop.js")
    variables_ready.wait()
    
    -- Wait for frame to be available
    local wait_count = 0
    while wait_count < 50 and not (frame_variables.get_current_frame and frame_variables.get_current_frame()) do
      vim.wait(100)
      wait_count = wait_count + 1
    end
    
    -- Execute the floating window command to create the actual plugin buffer
    vim.cmd("NeodapVariablesFloat")
    
    -- Wait a moment for the floating window and buffer to be created
    vim.wait(500)
    
    -- Get the buffer created by the plugin using the API
    local plugin_buf = frame_variables.get_variables_buffer()
    assert(plugin_buf, "FrameVariables plugin should create and expose a variables buffer")
    
    -- Capture and assert snapshot of the actual plugin buffer
    local actual_snapshot = BufferSnapshot.capture_buffer_snapshot(plugin_buf)
    BufferSnapshot.assert_snapshot(actual_snapshot, [[
▼ Local
    this = undefined
▼ Closure
    i = 0
▶ Global
    ]])
  end)

  Test.It("FV_expanded_global_snapshot - capture Global scope expansion", function()
    local api, start = prepare()
    
    local _breakpoints = api:getPluginInstance(BreakpointManager)
    local frame_variables = api:getPluginInstance(FrameVariables)
    
    local variables_ready = Test.spy("variables_ready")
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        local filesource = source:asFile()
        if filesource and filesource:filename() == "loop.js" then
          filesource:addBreakpoint({ line = 3 })
        end
      end)
      
      session:onThread(function(thread)
        thread:onStopped(function()
          variables_ready.trigger()
        end)
      end)
    end)
    
    start("loop.js")
    variables_ready.wait()
    
    -- Wait for frame to be available
    local wait_count = 0
    while wait_count < 50 and not (frame_variables.get_current_frame and frame_variables.get_current_frame()) do
      vim.wait(100)
      wait_count = wait_count + 1
    end
    
    -- Execute the floating window command to create the actual plugin buffer
    vim.cmd("NeodapVariablesFloat")
    
    -- Wait a moment for the floating window and buffer to be created
    vim.wait(500)
    
    -- Get the buffer and window created by the plugin
    local plugin_buf = frame_variables.get_variables_buffer()
    assert(plugin_buf, "FrameVariables plugin should create and expose a variables buffer")
    
    -- Find the floating window containing our buffer
    local plugin_win = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == plugin_buf then
        plugin_win = win
        break
      end
    end
    assert(plugin_win, "Should find the floating window containing the variables buffer")
    
    -- Find the Global scope line (should be line 3: "▶ Global")
    local lines = vim.api.nvim_buf_get_lines(plugin_buf, 0, -1, false)
    local global_line = nil
    for i, line in ipairs(lines) do
      if line:match("▶ Global") then
        global_line = i
        break
      end
    end
    assert(global_line, "Should find the Global scope line")
    
    -- Set cursor to the Global scope line and press Enter to expand it
    vim.api.nvim_win_set_cursor(plugin_win, {global_line, 0})
    
    print("=== BEFORE EXPANSION ===")
    print("Global line number:", global_line)
    print("Current cursor position:", vim.inspect(vim.api.nvim_win_get_cursor(plugin_win)))
    print("Line content:", lines[global_line])
    
    -- Debug: Check what scopes are available and their contents
    local current_frame = frame_variables.get_current_frame()
    local scopes = current_frame:scopes()
    print("=== SCOPE ANALYSIS ===")
    for i, scope in ipairs(scopes) do
      print(string.format("Scope %d: %s (ref: %s, expensive: %s)", i, scope.ref.name, scope.ref.variablesReference, tostring(scope.ref.expensive)))
      if scope.ref.name == "Global" then
        local global_vars = scope:variables()
        if global_vars then
          print("Global variables found:", #global_vars)
          
          -- Find and examine Array and Buffer specifically
          for j, var in ipairs(global_vars) do
            if var.ref.name == "Array" or var.ref.name == "Buffer" then
              print(string.format("\n=== DETAILED DAP INFO FOR %s ===", var.ref.name))
              print("  name:", var.ref.name)
              print("  type:", var.ref.type or "nil")
              print("  value:", var.ref.value or "nil")
              print("  variablesReference:", var.ref.variablesReference or "nil")
              print("  evaluateName:", var.ref.evaluateName or "nil")
              print("  presentationHint:", vim.inspect(var.ref.presentationHint or {}))
              print("  memoryReference:", var.ref.memoryReference or "nil")
              print("  indexedVariables:", var.ref.indexedVariables or "nil")
              print("  namedVariables:", var.ref.namedVariables or "nil")
              print("  Full ref object:", vim.inspect(var.ref))
              print("========================================\n")
            elseif j <= 3 then -- Show first 3 others briefly
              print(string.format("  %s = %s (%s)", var.ref.name, var.ref.value or "nil", var.ref.type or "unknown"))
            end
          end
          if #global_vars > 6 then
            print("  ... and", #global_vars - 6, "more")
          end
        else
          print("Global variables: nil")
        end
      end
    end
    print("========================")
    
    -- Make sure we're in the correct window and in normal mode
    vim.api.nvim_set_current_win(plugin_win)
    
    -- Try multiple approaches to trigger the keymap
    local expansion_worked = false
    
    -- Approach 1: Use direct keymap access 
    vim.api.nvim_set_current_win(plugin_win)
    vim.api.nvim_set_current_buf(plugin_buf)
    vim.api.nvim_win_set_cursor(plugin_win, {global_line, 0})
    
    -- Get the keymap and execute it directly
    local keymaps = vim.api.nvim_buf_get_keymap(plugin_buf, "n")
    for _, keymap in ipairs(keymaps) do
      if keymap.lhs == "<CR>" and keymap.callback then
        print("Found Enter keymap, executing directly...")
        keymap.callback()
        expansion_worked = true
        break
      end
    end
    
    -- Wait for the first attempt
    vim.wait(500)
    
    -- If first approach didn't work, try approach 2: Use a different keystroke method
    if not expansion_worked then
      print("First keystroke attempt failed, trying approach 2...")
      
      -- Try using vim.cmd with normal! command
      vim.api.nvim_set_current_win(plugin_win)
      vim.api.nvim_win_set_cursor(plugin_win, {global_line, 0})
      vim.cmd("normal! \\<CR>")
      vim.wait(500)
      
      -- Check if approach 2 worked
      local updated_lines2 = vim.api.nvim_buf_get_lines(plugin_buf, 0, -1, false)
      for _, line in ipairs(updated_lines2) do
        if line:match("▼ Global") then
          expansion_worked = true
          break
        end
      end
    end
    
    -- If still not working, try approach 3: Direct mode change
    if not expansion_worked then
      print("Approach 2 failed, trying approach 3...")
      
      -- Enter insert mode and then return to normal mode to trigger events
      vim.api.nvim_set_current_win(plugin_win)
      vim.api.nvim_win_set_cursor(plugin_win, {global_line, 0})
      vim.api.nvim_input("<CR>")
      vim.wait(500)
    end
    
    -- Capture and assert snapshot of the expanded Global scope
    local actual_snapshot = BufferSnapshot.capture_buffer_snapshot(plugin_buf)
    
    print("=== ACTUAL SNAPSHOT CONTENT ===")
    print(actual_snapshot)
    print("===============================")
    
    -- Helper function to find a line by variable name and verify exact content
    local function assert_exact_line(variable_name, expected_line)
      local snapshot_lines = vim.split(actual_snapshot, "\n")
      local found = false
      
      for _, line in ipairs(snapshot_lines) do
        if line:find(variable_name, 1, true) then -- plain text search
          assert(line == expected_line, string.format("Variable '%s' line mismatch. Expected: '%s', Actual: '%s'", variable_name, expected_line, line))
          found = true
          break
        end
      end
      
      assert(found, string.format("Variable '%s' not found in snapshot", variable_name))
    end
    
    -- Test exact content for scope headers
    assert_exact_line("▼ Local", "▼ Local")
    assert_exact_line("▼ Closure", "▼ Closure") 
    assert_exact_line("▼ Global", "▼ Global")
    
    -- Test exact content for local/closure variables
    assert_exact_line("this = undefined", "    this = undefined")
    assert_exact_line("i = 0", "    i = 0")
    
    -- Test exact content for specific global variables
    assert_exact_line("AbortController", "  ▶ AbortController()")
    assert_exact_line("Buffer", "  ▶ Buffer()")
    assert_exact_line("Array", "  ▶ Array = ƒ Array()")
    assert_exact_line("Promise", "  ▶ Promise = ƒ Promise()")
    assert_exact_line("console", "  ▶ console = console {log: ƒ, warn: ƒ, dir: ƒ, time: ƒ, tim...")
    assert_exact_line("process", "  ▶ process()")
    assert_exact_line("fetch", "  ▶ fetch = ƒ fetch(input, init = undefined) { // eslint-disa...")
    
    print("✓ Global scope expansion test passed - all variable lines match exactly")
  end)

  Test.It("FV_floating_command - test NeodapVariablesFloat command", function()
    local api, start = prepare()
    
    local _breakpoints = api:getPluginInstance(BreakpointManager)
    local frame_variables = api:getPluginInstance(FrameVariables)
    
    local command_executed = Test.spy("command_executed")
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        local filesource = source:asFile()
        if filesource and filesource:filename() == "loop.js" then
          filesource:addBreakpoint({ line = 3 })
        end
      end)
      
      session:onThread(function(thread)
        thread:onStopped(function()
          command_executed.trigger()
        end)
      end)
    end)
    
    start("loop.js")
    command_executed.wait()
    
    -- Wait for frame to be available in main test body
    local wait_count = 0
    while wait_count < 50 and not (frame_variables.get_current_frame and frame_variables.get_current_frame()) do
      vim.wait(100)
      wait_count = wait_count + 1
    end
    
    -- Execute the floating window command from main test body
    local success = pcall(vim.cmd, "NeodapVariablesFloat")
    
    -- Just verify the command executed - floating window may depend on neo-tree availability
    assert(success, "NeodapVariablesFloat command should execute without error")
    
    print("✓ NeodapVariablesFloat command executed successfully")
  end)
end)