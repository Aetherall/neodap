--- Test harness for neodap tests
--- Provides high-level API for test interactions, hiding child.lua internals
---@class tests.helpers.test_harness
local M = {}

local fixtures = require("helpers.dap.fixtures")

-------------------------------------------------------------------------------
-- Timeout Constants
-------------------------------------------------------------------------------

---Standard timeout values for consistency across tests
---@class TimeoutConstants
M.TIMEOUT = {
  SHORT = 2000,   -- Quick operations (cleanup, simple waits)
  MEDIUM = 5000,  -- Standard operations (fetch, step, sync)
  LONG = 10000,   -- Slow operations (launch, continue to breakpoint)
  EXTENDED = 15000, -- Very slow operations (multiple sessions)
}

---@alias AdapterName "python"|"javascript"

---Adapter configurations for multi-adapter tests
---@type table<AdapterName, { name: AdapterName }>
M.adapters = {
  python = { name = "python" },
  javascript = { name = "javascript" },
}

---@class TestHarness
---@field child table MiniTest child neovim
---@field _test_file string? Current test file path
---@field adapter table? Current adapter config
local Harness = {}
Harness.__index = Harness

---Create a new test harness wrapping a child neovim
---@param child table MiniTest child neovim
---@param adapter? table Adapter config (defaults to python)
---@return TestHarness
function M.new(child, adapter)
  local self = setmetatable({}, Harness)
  self.child = child
  self._test_file = nil
  self.adapter = adapter or M.adapters.python
  return self
end

---Use a static fixture directory
---Maps pattern name to tests/fixtures/{pattern}/{adapter}/
---Reloads code_workspace plugin with the fixture path
---@param pattern string Fixture pattern name (e.g., "simple-vars")
---@return string path Absolute path to fixture directory
function Harness:fixture(pattern)
  local adapter_name = self.adapter.name
  local cwd = vim.fn.getcwd()
  local fixture_path = cwd .. "/tests/fixtures/" .. pattern .. "/" .. adapter_name

  -- Verify fixture exists
  if vim.fn.isdirectory(fixture_path) == 0 then
    error(string.format("Fixture not found: %s (looking in %s)", pattern, fixture_path))
  end

  -- Store fixture path for edit_main()
  self._fixture_path = fixture_path

  -- Reload code_workspace plugin with new path (runs in child process)
  self.child.lua(string.format([[
    -- Cleanup old code_workspace if exists
    if _G.code_workspace_api and _G.code_workspace_api.cleanup then
      _G.code_workspace_api.cleanup()
    end

    -- resolve_adapter returns adapter configs
    local function resolve_adapter(config)
      local adapter_type = config.type
      if adapter_type == "python" then
        return _G.fixtures.debugpy_adapter()
      elseif adapter_type == "pwa-node" then
        return _G.fixtures.jsdbg_adapter()
      end
      return nil
    end

    -- Reload code_workspace with fixture path
    _G.code_workspace_api = require("neodap").use(require("neodap.plugins.code_workspace"), {
      resolve_adapter = resolve_adapter,
      path = %q,
    })
  ]], fixture_path))

  return fixture_path
end

---Open the main file of the current fixture
---Must be called after h:fixture()
---@return string path Path to the main file
function Harness:edit_main()
  if not self._fixture_path then
    error("edit_main() requires h:fixture() to be called first")
  end

  local ext = self.adapter.name == "python" and ".py" or ".js"
  local main_path = self._fixture_path .. "/main" .. ext
  self:edit(main_path)
  return main_path
end

---Open a specific file in the current fixture by name (without extension)
---Must be called after h:fixture()
---@param name string File name without extension (e.g., "program_a")
---@return string path Path to the file
function Harness:edit_file(name)
  if not self._fixture_path then
    error("edit_file() requires h:fixture() to be called first")
  end

  local ext = self.adapter.name == "python" and ".py" or ".js"
  local file_path = self._fixture_path .. "/" .. name .. ext
  self:edit(file_path)
  return file_path
end

---Ensure npm dependencies are installed for current fixture
---Must be called after h:fixture() if the fixture has a package.json
---Runs npm install synchronously in parent process if node_modules doesn't exist
function Harness:ensure_npm_deps()
  if not self._fixture_path then
    error("ensure_npm_deps() requires h:fixture() to be called first")
  end

  local package_json = self._fixture_path .. "/package.json"
  local node_modules = self._fixture_path .. "/node_modules"

  -- Skip if no package.json
  if vim.fn.filereadable(package_json) == 0 then
    return
  end

  -- Skip if node_modules exists
  if vim.fn.isdirectory(node_modules) == 1 then
    return
  end

  -- Run npm install synchronously
  local result = vim.fn.system("cd " .. vim.fn.shellescape(self._fixture_path) .. " && npm install 2>&1")
  if vim.v.shell_error ~= 0 then
    error("npm install failed: " .. result)
  end
end

---Initialize neodap in the child
function Harness:setup_neodap()
  local adapter_name = self.adapter.name
  local tmpdir = fixtures.get_tmpdir()
  self.child.lua(string.format([[
    package.path = vim.fn.getcwd() .. "/tests/?.lua;" .. package.path
    package.path = vim.fn.getcwd() .. "/tests/?/init.lua;" .. package.path

    _G.fixtures = require("helpers.dap.fixtures")

    local neodap = require("neodap")
    neodap.setup({
      adapters = {
        python = _G.fixtures.debugpy_adapter(),
        ["pwa-node"] = _G.fixtures.jsdbg_adapter(),
      },
    })
    neodap.use(require("neodap.plugins.dap"))
    neodap.use(require("neodap.plugins.step_cmd"))
    neodap.use(require("neodap.plugins.control_cmd"))
    neodap.use(require("neodap.plugins.focus_cmd"))
    _G.neodap = neodap
    _G.debugger = neodap.debugger
    _G.H = require("helpers.dap")

    -- Note: launch.json is created in parent process via create_file()
    -- Don't call ensure_launch_json() here - it would use child's PID

    -- Store adapter name for tests that need adapter-specific behavior
    _G.adapter_name = %q

    -- Load code_workspace plugin for :DapLaunch support
    -- Use parent's tmpdir so it finds the launch.json created by parent process
    _G.code_workspace_api = neodap.use(require("neodap.plugins.code_workspace"), {
      path = %q,
    })

    -- Set up adapter-specific globals for tests that use direct launch
    if _G.adapter_name == "python" then
      _G.adapter = _G.fixtures.debugpy_adapter()
      _G.launch_config = function(program, opts)
        opts = opts or {}
        return {
          type = "python",
          request = "launch",
          name = "Test",
          program = program,
          console = "internalConsole",
          stopOnEntry = opts.stopOnEntry or false,
        }
      end
    elseif _G.adapter_name == "javascript" then
      _G.adapter = _G.fixtures.jsdbg_adapter()
      _G.jsdbg = require("helpers.dap.jsdbg")
      _G.launch_config = function(program, opts)
        opts = opts or {}
        return {
          type = "pwa-node",
          request = "launch",
          name = "Test",
          program = program,
          stopOnEntry = opts.stopOnEntry or false,
          sourceMaps = true,
          skipFiles = {},
        }
      end
    end
  ]], adapter_name, tmpdir))
end

---Open a file in the child
---@param path string File path to edit
function Harness:edit(path)
  self.child.cmd("edit " .. path)
end

---Execute a Vim command in the child
---@param command string Vim command (without leading colon)
function Harness:cmd(command)
  self.child.cmd(command)
end

---Yield to the event loop to let scheduled callbacks run
---@param ms? number Milliseconds to wait (default 50)
function Harness:yield(ms)
  ms = ms or 50
  self.child.lua(string.format([[
    vim.wait(%d, function() return false end, 10)
  ]], ms))
end

---Execute a Vim command and expect it to fail
---@param command string Vim command that should fail
---@param error_pattern? string Optional pattern to match in error message
---@return { failed: boolean, error_msg: string }
function Harness:expect_cmd_fails(command, error_pattern)
  local result = self.child.lua_get(string.format([[(function()
    local ok, err = pcall(vim.cmd, %q)
    return { failed = not ok, error_msg = err or "" }
  end)()]], command))

  MiniTest.expect.equality(result.failed, true, "Expected command to fail: " .. command)

  if error_pattern then
    local matches = result.error_msg:match(error_pattern) ~= nil
    MiniTest.expect.equality(matches, true,
      "Expected error to match '" .. error_pattern .. "', got: " .. result.error_msg)
  end

  return result
end

-------------------------------------------------------------------------------
-- JS-Debug Dual Session Helpers (for leaf_session tests)
-------------------------------------------------------------------------------

---Start jsdbg with both root and child sessions accessible
---Sessions accessible via /sessions[0] (root) and /sessions[1] (child)
---Uses jsdbg-simple fixture
---@param opts? { stopOnEntry?: boolean }
function Harness:start_jsdbg_dual(opts)
  opts = opts or {}
  opts.focus_root = opts.focus_root == nil and true or opts.focus_root
  local fixture_path = self:fixture("jsdbg-simple")
  local program = fixture_path .. "/main.js"

  -- Launch directly using _G.debugger (set by harness pre_case hook)
  self.child.lua(string.format([[
    local fixtures = require("helpers.dap.fixtures")
    local H = require("helpers.dap")

    local root_session = _G.debugger:debug({
      adapter = fixtures.jsdbg_adapter(),
      config = fixtures.node_launch({
        program = %q,
        stopOnEntry = %s,
      }),
    })

    -- Focus root session immediately (before child might be created)
    -- This ensures leaf_session can auto-focus child when it spawns
    if %s then
      _G.debugger.ctx:focus(root_session.uri:get())
    end

    -- Wait for root session to be running
    H.wait_for(10000, function()
      return root_session.state:get() == "running"
    end)

    -- Wait for child session to be created
    H.wait_for(10000, function()
      return H.edge_first(root_session.children) ~= nil
    end)

    -- Wait for child to be stopped or terminated
    local child = H.edge_first(root_session.children)
    if child then
      H.wait_for(10000, function()
        local state = child.state:get()
        return state == "stopped" or state == "terminated"
      end)
    end
  ]], program, opts.stopOnEntry and "true" or "false", opts.focus_root and "true" or "false"))
end

---Get session URI by role (for JS-debug dual sessions)
---@param role "root"|"child" Session role
---@return string? uri
function Harness:session_uri(role)
  local index = role == "root" and 0 or 1
  return self:query_uri(string.format("/sessions[%d]", index))
end

---Clean up jsdbg dual session context
function Harness:cleanup_jsdbg_dual()
  -- Terminate child session first
  if not self:query_is_nil("/sessions[1]") then
    self:query_call("/sessions[1]", "terminate")
    self:wait_url("/sessions(state=terminated)[0]", M.TIMEOUT.SHORT)
  end
  -- Terminate root session
  if not self:query_is_nil("/sessions[0]") then
    self:query_call("/sessions[0]", "terminate")
    self:wait_url("/sessions(state=terminated)[1]", M.TIMEOUT.SHORT)
  end
end

---Start a Python sleeper session (for cross-adapter focus tests)
---Uses py-sleeper fixture which has a time.sleep() to keep session alive
function Harness:start_py_sleeper()
  local cwd = vim.fn.getcwd()
  local fixture_path = cwd .. "/tests/fixtures/py-sleeper/python"
  local program = fixture_path .. "/main.py"

  -- Load code_workspace plugin with py-sleeper fixture (include resolve_adapter)
  self.child.lua(string.format([[
    local function resolve_adapter(config)
      if config.type == "python" then
        return _G.fixtures.debugpy_adapter()
      elseif config.type == "pwa-node" then
        return _G.fixtures.jsdbg_adapter()
      end
      return nil
    end
    require("neodap").use(require("neodap.plugins.code_workspace"), {
      path = %q,
      resolve_adapter = resolve_adapter,
    })
  ]], fixture_path))

  self.child.g.debug_file = program
  self:cmd("DapLaunch Debug stop")
end

---Check if both root and child sessions exist
---@return boolean, boolean has_root, has_child
function Harness:has_jsdbg_sessions()
  local has_root = not self:query_is_nil("/sessions[0]")
  local has_child = not self:query_is_nil("/sessions[1]")
  return has_root, has_child
end

---Focus the root session (sessions[0])
function Harness:focus_root_session()
  -- Wait for root session frame to be available
  self:wait_url("/sessions[0]/threads[0]/stack/frames[0]")
  local frame_uri = self:query_uri("/sessions[0]/threads[0]/stack/frames[0]")
  if frame_uri and frame_uri ~= vim.NIL then
    self:cmd("DapFocus " .. frame_uri)
  end
end

---Continue the child session (sessions[1])
function Harness:continue_child_session()
  local state = self:query_field("/sessions[1]", "state")
  if state == "stopped" then
    self:query_call("/sessions[1]", "fetchThreads")
    self:wait_url("/sessions[1]/threads[0]")
    self:query_call("/sessions[1]/threads[0]", "continue")
  end
end

---Wait for child session (sessions[1]) to terminate
---@param timeout? number Timeout in ms (default 5000)
function Harness:wait_child_terminated(timeout)
  -- Wait specifically for sessions[1] (child) to terminate
  self:wait_field("/sessions[1]", "state", "terminated", timeout or M.TIMEOUT.MEDIUM)
end

---Terminate root session (sessions[0])
function Harness:terminate_root_session()
  if not self:query_is_nil("/sessions[0]") then
    self:query_call("/sessions[0]", "terminate")
    -- If child already terminated, root is second; otherwise first
    -- Just wait for at least one more termination
    self:wait_url("/sessions(state=terminated)[0]", M.TIMEOUT.SHORT)
  end
end

---Check if child session format includes root session name (for leaf display)
---@return boolean
function Harness:child_format_includes_root_name()
  self.child.lua([[
    _G._format_ok = false
    local child = _G.debugger:query("/sessions[1]")
    local root = _G.debugger:query("/sessions[0]")
    if child and root then
      local fmt = child:format()
      local root_name = root.name:get()
      _G._format_ok = fmt:find(root_name, 1, true) ~= nil
    end
  ]])
  return self:get("_G._format_ok") or false
end

---Get a value from the child
---@param expr string Lua expression to evaluate
---@return any
function Harness:get(expr)
  return self.child.lua_get(expr)
end

---Cleanup test resources
function Harness:cleanup()
  -- Disconnect all non-terminated sessions from parent process
  local count = self:query_count("/sessions")
  local terminated_count = 0
  for i = 0, count - 1 do
    local session_url = string.format("/sessions[%d]", i)
    local state = self:query_field(session_url, "state")
    if state == "terminated" then
      terminated_count = terminated_count + 1
    else
      self:query_call(session_url, "disconnect")
      -- Wait for one more session to be terminated
      self:wait_url(string.format("/sessions(state=terminated)[%d]", terminated_count), M.TIMEOUT.MEDIUM)
      terminated_count = terminated_count + 1
    end
  end
  if self._test_file then
    vim.fn.delete(self._test_file)
    self._test_file = nil
  end
end

---Evaluate an expression in current frame
---@param expr string Expression to evaluate
---@return string result
function Harness:evaluate(expr)
  self.child.lua(string.format([[
    _G._eval_done = false
    _G._eval_result = nil
    local frame = _G.debugger:query("@frame")
    if frame then
      require("neodap.async").run(function()
        _G._eval_result = frame:evaluate(%q)
        _G._eval_done = true
      end)
      vim.wait(5000, function() return _G._eval_done end, 10)
    end
  ]], expr))
  return self.child.lua_get("_G._eval_result")
end

-------------------------------------------------------------------------------
-- Plugin Initialization Helpers
-------------------------------------------------------------------------------

---Initialize a plugin and store its API in _G
---Uses debugger:use() for proper scoped subscriptions
---@param module string Module path (e.g., "neodap.plugins.breakpoint_cmd")
---@param opts? table Optional configuration to pass to plugin
---@param global_name? string Name to store API under (default: derived from module)
---@return boolean success
function Harness:init_plugin(module, opts, global_name)
  local name = global_name or module:match("[^.]+$") .. "_api"
  if opts then
    -- Use child.lua for multi-line opts
    local opts_str = vim.inspect(opts)
    self.child.lua(string.format([[
      _G[%q] = _G.debugger:use(require(%q), %s)
    ]], name, module, opts_str))
  else
    self:cmd(string.format('lua _G[%q] = _G.debugger:use(require(%q))', name, module))
  end
  return self:get("_G." .. name .. " ~= nil")
end

---Use a plugin via neodap.use() pattern
---@param module string Module path
---@param config_or_name? table|string Config table, or global name string (deprecated)
---@return boolean success
function Harness:use_plugin(module, config_or_name)
  local name = module:match("[^.]+$") .. "_api"

  -- Handle old-style global name (string) vs new-style config (table)
  if type(config_or_name) == "string" then
    -- Old style: second param is global name
    name = config_or_name
    self.child.lua(string.format([[
      local p = require(%q)
      _G[%q] = require("neodap").use(p)
    ]], module, name))
  elseif type(config_or_name) == "table" then
    -- New style: second param is config
    local config_str = vim.inspect(config_or_name)
    self.child.lua(string.format([[
      local p = require(%q)
      _G[%q] = require("neodap").use(p, %s)
    ]], module, name, config_str))
  else
    -- No second param
    self.child.lua(string.format([[
      local p = require(%q)
      _G[%q] = require("neodap").use(p)
    ]], module, name))
  end
  return self:get("_G." .. name .. " ~= nil")
end

-------------------------------------------------------------------------------
-- Focus Helpers
-------------------------------------------------------------------------------

---Focus an entity in the debugger using DapFocus command
---@param url string URL to focus (e.g., "@frame", "/sessions/threads[0]")
---@param wait_ms? number Wait time after focus (default 100)
function Harness:focus(url, wait_ms)
  wait_ms = wait_ms or 100
  self:cmd("DapFocus " .. url)
  if wait_ms > 0 then
    self:wait(wait_ms)
  end
end

---Clear focus (unfocus)
---@param wait_ms? number Wait time after unfocus (default 100)
function Harness:unfocus(wait_ms)
  wait_ms = wait_ms or 100
  self:query_focus("")
  self:wait(wait_ms)
end

-------------------------------------------------------------------------------
-- Visual Test Helpers
-------------------------------------------------------------------------------

---Setup for visual tests (disable statusline etc.)
function Harness:setup_visual()
  self.child.o.laststatus = 0
end

---Open a dap://tree entity buffer
---@param tree_path string Tree path (e.g., "@debugger", "@session", "@frame")
---@param wait_ms? number Wait time after opening (default 100)
function Harness:open_tree(tree_path, wait_ms)
  self.child.cmd("edit dap://tree/" .. tree_path)
  if wait_ms ~= 0 then
    self:wait(wait_ms or 100)
  end
end

---Open a dap://url buffer for URL debugging
---@param url string URL to watch (e.g., "/sessions", "@frame/scopes")
---@param wait_ms? number Wait time after opening (default 100)
function Harness:open_url_buffer(url, wait_ms)
  self.child.cmd("edit dap://url/" .. url)
  if wait_ms ~= 0 then
    self:wait(wait_ms or 100)
  end
end

-------------------------------------------------------------------------------
-- Child Process Helpers (eliminate direct child.lua in tests)
-------------------------------------------------------------------------------

---Wait in child process (processes events during wait)
---@param ms number Milliseconds to wait
function Harness:wait(ms)
  self.child.lua(string.format([[ vim.wait(%d) ]], ms))
end

---Get current buffer number
---@return number
function Harness:current_buf()
  return self.child.api.nvim_get_current_buf()
end

---Set cursor position
---@param line number Line number (1-indexed)
---@param col? number Column (0-indexed, default 0)
function Harness:set_cursor(line, col)
  self.child.api.nvim_win_set_cursor(0, { line, col or 0 })
end

---Get buffer line count
---@param bufnr? number Buffer number (default current)
---@return number
function Harness:line_count(bufnr)
  return self.child.api.nvim_buf_line_count(bufnr or 0)
end

---Wait for context to have a frame (for cursor_focus plugin tests)
---@param timeout? number Timeout in ms (default 5000)
---@return boolean success True if frame found before timeout
function Harness:wait_context_frame(timeout)
  timeout = timeout or 5000
  self.child.lua(string.format([[
    _G._wait_ctx_frame_ok = vim.wait(%d, function()
      return _G.debugger.ctx.frame:get() ~= nil
    end, 10)
  ]], timeout))
  return self:get("_G._wait_ctx_frame_ok") or false
end

---Check if context has a frame (for cursor_focus plugin tests)
---@return boolean
function Harness:context_has_frame()
  self.child.lua([[
    _G._ctx_has_frame = _G.debugger.ctx.frame:get() ~= nil
  ]])
  return self:get("_G._ctx_has_frame") or false
end

---Get frame line from context (for cursor_focus plugin tests)
---@return number|nil
function Harness:context_frame_line()
  self.child.lua([[
    local frame = _G.debugger.ctx.frame:get()
    _G._ctx_frame_line = frame and frame.line:get()
  ]])
  return self:get("_G._ctx_frame_line")
end

---Check if buffer is valid
---@param bufnr number Buffer number
---@return boolean
function Harness:buf_valid(bufnr)
  return self.child.api.nvim_buf_is_valid(bufnr)
end

---Execute new buffer command
function Harness:enew()
  self:cmd("enew")
end

---Delete buffer
---@param bufnr number Buffer number
---@param force? boolean Force delete (default false)
function Harness:bwipeout(bufnr, force)
  if force then
    self:cmd(bufnr .. "bwipeout!")
  else
    self:cmd(bufnr .. "bwipeout")
  end
end

---Set buffer lines
---@param bufnr number Buffer number (0 for current)
---@param lines string[] Lines to set
function Harness:set_lines(bufnr, lines)
  self.child.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

---Call a plugin API method stored in a global
---@param global_name string Global name (e.g., "auto_context_api")
---@param method string Method name (e.g., "update")
---@param ... any Arguments to pass
function Harness:call_plugin(global_name, method, ...)
  local args = { ... }
  local args_str = ""
  for i, arg in ipairs(args) do
    if type(arg) == "string" then
      args_str = args_str .. string.format("%q", arg)
    elseif type(arg) == "boolean" then
      args_str = args_str .. tostring(arg)
    else
      args_str = args_str .. tostring(arg)
    end
    if i < #args then
      args_str = args_str .. ", "
    end
  end
  self.child.lua(string.format([[ _G.%s.%s(%s) ]], global_name, method, args_str))
end

---Sanitize screenshot text and attrs to make tests deterministic
---Replaces non-deterministic values (thread IDs, temp paths, etc.) with placeholders
---Normalizes line widths to avoid flaky column count comparisons from vsplit variations
---Converts attr IDs to highlight group names for stable comparison
---@param screenshot table MiniTest screenshot object
---@param hl_map table? Mapping from attr ID to highlight group name
---@return table screenshot Modified screenshot
local function sanitize_screenshot(screenshot, hl_map)
  if not screenshot or not screenshot.text then
    return screenshot
  end

  -- Normalize attrs: convert numeric IDs to highlight group names
  -- This makes comparisons stable across environments where IDs differ
  if hl_map and screenshot.attr then
    for i, line in ipairs(screenshot.attr) do
      if type(line) == "table" then
        for j, attr_id in ipairs(line) do
          if type(attr_id) == "number" and hl_map[attr_id] then
            line[j] = hl_map[attr_id]
          end
        end
      end
    end
  end

  -- Standard terminal width for screenshot normalization
  local TARGET_WIDTH = 80

  -- First pass: collect all session IDs across all lines to build a consistent mapping
  local session_map = {}
  local session_count = 0
  local session_placeholders = { "aabbb", "ccddd", "eefff", "gghhhh" } -- distinct 5-char tokens

  for _, line in ipairs(screenshot.text) do
    if type(line) == "table" then
      local str = table.concat(line)
      -- Find all 5-char lowercase session IDs (neoword format)
      for id in str:gmatch(":([a-z][a-z][a-z][a-z][a-z])") do
        if not session_map[id] then
          session_count = session_count + 1
          session_map[id] = session_placeholders[session_count] or "xxxxx"
        end
      end
    end
  end

  -- Second pass: apply all normalizations
  for i, line in ipairs(screenshot.text) do
    -- MiniTest screenshot lines are tables of characters, convert to string
    if type(line) == "table" then
      local str = table.concat(line)
      -- Replace temp directory numbers with fixed width: neodap_test_XXXXX → neodap_test_NNNNNN
      str = str:gsub("neodap_test_%d+", "neodap_test_NNNNNN")
      -- Replace entire thread description with fixed-length placeholder
      -- Thread ID: name [PID] (state) → Thread XXXXXXXXXXXXXXXXXXXXXXXX (state)
      str = str:gsub("(Thread ).-( %(%w+%))", "%1XXXXXXXXXXXXXXXXXXXXXXXX%2")
      -- Also handle truncated thread lines (no closing paren visible)
      str = str:gsub("(Thread )%d+:.+$", "%1XXXXXXXXXXXXXXXXXXXXXXXX")
      -- Replace session/debugee names with file+PID pattern (with or without state suffix)
      -- Handles both temp files (0.js) and fixture files (main.js)
      str = str:gsub("(%w+%.js) %[%d+%]( %(%w+%))", "%1 [NNNNNN]%2")
      str = str:gsub("(%w+%.py) %[%d+%]( %(%w+%))", "%1 [NNNNNN]%2")
      str = str:gsub("(%w+%.js) %[%d+%]", "%1 [NNNNNN]")
      str = str:gsub("(%w+%.py) %[%d+%]", "%1 [NNNNNN]")
      -- Replace standalone temp file names (for breakpoints etc): 0.js → NN.js, 0.py → NN.py
      str = str:gsub("(%D)(%d+)(%.js)", "%1NN%3")
      str = str:gsub("(%D)(%d+)(%.py)", "%1NN%3")
      -- Replace IDs in scope URIs: scope:SESSION:STOPSEQ:FRAMEID:Name → scope:SESSION:NNNN:NNNN:Name
      str = str:gsub("(scope:%w+:)%d+:%d+(:.+)", "%1NNNN:NNNN%2")
      -- Replace frame IDs in thread URIs: thread:SESSION:ID → thread:SESSION:NNNN
      str = str:gsub("(thread:%w+:)%d+", "%1NNNN")
      -- Replace IDs in frame URIs: frame:SESSION:STOPSEQ:FRAMEID → frame:SESSION:NNNN:NNNN
      str = str:gsub("(frame:%w+:)%d+:%d+", "%1NNNN:NNNN")
      -- Apply session ID normalization using the pre-built map
      for orig_id, norm_id in pairs(session_map) do
        str = str:gsub("(session:)" .. orig_id, "%1" .. norm_id)
        str = str:gsub("(thread:)" .. orig_id, "%1" .. norm_id)
        str = str:gsub("(frame:)" .. orig_id, "%1" .. norm_id)
        str = str:gsub("(scope:)" .. orig_id, "%1" .. norm_id)
        str = str:gsub("(stack:)" .. orig_id, "%1" .. norm_id)
        str = str:gsub("(output:)" .. orig_id, "%1" .. norm_id)
        str = str:gsub("(stdio:)" .. orig_id, "%1" .. norm_id)
      end
      -- Mask cursor position in status line (last 2 lines, rightmost portion)
      -- Neovim's ruler shows: "line,col-virtcol" then "All/Top/Bot/percentage"
      -- Examples: "8,11-7         All", "4,23-19       All", "1:1"
      if i >= #screenshot.text - 1 then
        -- Mask complex cursor position pattern: digits,digits-digits (Neovim ruler format)
        str = str:gsub("%d+,%d+%-%d+", "NN,NN-NN")
        -- Mask simple cursor position pattern: digits:digits or digits,digits
        str = str:gsub("%d+[,:;]%d+", "NN:NN")
        -- Mask percentage pattern (like "50%")
        str = str:gsub("%d+%%", "NN%%")
        -- Mask All/Top/Bot indicators
        str = str:gsub(" All", " XXX")
        str = str:gsub(" Top", " XXX")
        str = str:gsub(" Bot", " XXX")
      end
      -- Trim trailing spaces to avoid terminal width flakiness
      str = str:gsub("%s+$", "")

      -- Normalize line width to TARGET_WIDTH to avoid vsplit column count flakiness
      -- Pad shorter lines with spaces, truncate longer lines
      local chars = vim.fn.split(str, [[\zs]])
      local len = #chars
      if len < TARGET_WIDTH then
        -- Pad with spaces
        for j = len + 1, TARGET_WIDTH do
          chars[j] = " "
        end
      elseif len > TARGET_WIDTH then
        -- Truncate (keep first TARGET_WIDTH chars)
        for j = TARGET_WIDTH + 1, len do
          chars[j] = nil
        end
      end
      screenshot.text[i] = chars
    end
  end
  return screenshot
end

---Take screenshot with redraw
---@return table screenshot
function Harness:take_screenshot()
  self.child.cmd("redraw")
  local screenshot = self.child.get_screenshot()
  return sanitize_screenshot(screenshot, nil)
end

---Get all lines from current buffer
---@return string[] lines
function Harness:buffer_lines()
  return self.child.api.nvim_buf_get_lines(0, 0, -1, false)
end

---Get buffer content as single string
---@return string content
function Harness:buffer_content()
  return table.concat(self:buffer_lines(), "\n")
end

---Check if buffer contains text (searches all lines)
---@param text string Text to search for
---@return boolean found
function Harness:buffer_contains(text)
  local content = self:buffer_content()
  return content:find(text, 1, true) ~= nil
end

---Assert buffer contains text
---@param text string Text to search for
---@param message? string Optional message
function Harness:assert_buffer_contains(text, message)
  local found = self:buffer_contains(text)
  if not found then
    local content = self:buffer_content()
    error(string.format(
      "%s\nExpected buffer to contain: %q\nBuffer content:\n%s",
      message or "Buffer content assertion failed",
      text,
      content
    ))
  end
end

---Assert buffer contains all specified texts
---@param texts string[] List of texts to search for
---@param message? string Optional message
function Harness:assert_buffer_contains_all(texts, message)
  local content = self:buffer_content()
  local missing = {}
  for _, text in ipairs(texts) do
    if not content:find(text, 1, true) then
      table.insert(missing, text)
    end
  end
  if #missing > 0 then
    error(string.format(
      "%s\nMissing texts: %s\nBuffer content:\n%s",
      message or "Buffer content assertion failed",
      vim.inspect(missing),
      content
    ))
  end
end

-------------------------------------------------------------------------------
-- Output Helpers
-------------------------------------------------------------------------------

---Wait for session to terminate
---Uses adapter-specific index: 0 for Python (only session), 1 for JavaScript (child session)
---@param timeout? number Timeout in ms (default 5000)
function Harness:wait_terminated(timeout)
  local index = self.adapter.name == "javascript" and 1 or 0
  self:wait_field(string.format("/sessions[%d]", index), "state", "terminated", timeout or M.TIMEOUT.MEDIUM)
  self:wait(500) -- Give time for final events
end

-------------------------------------------------------------------------------
-- URL Query Helpers
-------------------------------------------------------------------------------

---Execute a URL query and return result count
---@param url string URL to query
---@return number Count of results (0 for nil/empty)
function Harness:query_count(url)
  self.child.lua(string.format([[
    local result = _G.debugger:query(%q)
    if result == nil then
      _G._query_count = 0
    elseif type(result) == "table" and result.type == nil then
      -- Array result
      _G._query_count = #result
    else
      -- Single entity
      _G._query_count = 1
    end
  ]], url))
  local result = self:get("_G._query_count")
  -- Handle vim.NIL (which is truthy) explicitly
  if result == nil or result == vim.NIL then
    return 0
  end
  return result
end

---Execute a URL query and return if result is nil
---@param url string URL to query
---@return boolean True if result is nil
function Harness:query_is_nil(url)
  self.child.lua(string.format([[
    local result = _G.debugger:query(%q)
    _G._query_is_nil = (result == nil)
  ]], url))
  return self:get("_G._query_is_nil") or false
end

---Wait for a URL to resolve to non-nil/non-empty result
---Use this instead of manual fetch sequences - the URL expresses what you need
---@param url string URL to wait for (e.g., "@session/threads/stack/frames[0]")
---@param timeout? number Timeout in ms (default 5000)
---@return boolean success True if URL resolved before timeout
function Harness:wait_url(url, timeout)
  timeout = timeout or 5000
  self.child.lua(string.format([[
    _G._wait_url_ok = vim.wait(%d, function()
      local result = _G.debugger:query(%q)
      if result == nil then return false end
      -- Array result: check non-empty
      if type(result) == "table" and result.type == nil then
        return #result > 0
      end
      -- Single entity: exists
      return true
    end, 10)
  ]], timeout, url))
  return self:get("_G._wait_url_ok") or false
end

---Wait for a URL's field to equal a specific value
---Use this when you need to wait for a *specific* entity's field, not just any matching entity
---@param url string URL to query (e.g., "/sessions[0]")
---@param field string Field name to check
---@param expected any Expected value
---@param timeout? number Timeout in ms (default 5000)
---@return boolean success True if field matched before timeout
function Harness:wait_field(url, field, expected, timeout)
  timeout = timeout or 5000
  -- Format expected value appropriately for Lua (booleans, numbers, strings)
  local expected_str
  if type(expected) == "boolean" then
    expected_str = expected and "true" or "false"
  elseif type(expected) == "number" then
    expected_str = tostring(expected)
  else
    expected_str = string.format("%q", expected)
  end
  self.child.lua(string.format([[
    _G._wait_field_ok = vim.wait(%d, function()
      local result = _G.debugger:query(%q)
      if result == nil then return false end
      local field_val = result.%s
      if field_val == nil then return false end
      local ok, val = pcall(function() return field_val:get() end)
      if not ok then val = field_val end
      return val == %s
    end, 10)
  ]], timeout, url, field, expected_str))
  return self:get("_G._wait_field_ok") or false
end

---Execute a URL query and return the type of the result
---@param url string URL to query
---@return string|nil Entity type or nil
function Harness:query_type(url)
  self.child.lua(string.format([[
    local result = _G.debugger:query(%q)
    if result == nil then
      _G._query_type = nil
    elseif type(result) == "table" and result.type == nil then
      -- Array result - get type of first element
      if result[1] and type(result[1].type) == "function" then
        _G._query_type = result[1]:type()
      else
        _G._query_type = "table"
      end
    elseif type(result.type) == "function" then
      _G._query_type = result:type()
    else
      _G._query_type = type(result)
    end
  ]], url))
  return self:get("_G._query_type")
end

---Execute a URL query and return if all results are of the given type
---@param url string URL to query
---@param entity_type string Expected entity type
---@return boolean True if all results match the type
function Harness:query_all_type(url, entity_type)
  self.child.lua(string.format([[
    local result = _G.debugger:query(%q)
    _G._query_all_type = true
    if result == nil then
      _G._query_all_type = false
    elseif type(result) == "table" and result.type == nil then
      for _, item in ipairs(result) do
        if not item or type(item.type) ~= "function" or item:type() ~= %q then
          _G._query_all_type = false
          break
        end
      end
    elseif type(result.type) == "function" then
      _G._query_all_type = (result:type() == %q)
    else
      _G._query_all_type = false
    end
  ]], url, entity_type, entity_type))
  return self:get("_G._query_all_type") or false
end

---Check if a query result matches the first element of another query
---@param url1 string First URL to query
---@param url2 string Second URL that should return array
---@return boolean True if result of url1 equals first element of url2 result
function Harness:query_matches_first(url1, url2)
  self.child.lua(string.format([[
    local result1 = _G.debugger:query(%q)
    local result2 = _G.debugger:query(%q)
    _G._query_matches = (result2 and type(result2) == "table" and result1 == result2[1])
  ]], url1, url2))
  return self:get("_G._query_matches") or false
end

---Query using session's key and verify match
---@param base_url string Base URL like "/sessions"
---@return boolean True if key lookup matches the session
function Harness:query_session_by_key_matches(base_url)
  local index = self.adapter.name == "javascript" and 1 or 0
  local session_url = string.format("/sessions[%d]", index)
  local session_id = self:query_field(session_url, "sessionId")
  if not session_id then return false end
  local session_uri = self:query_uri(session_url)
  local key_url = base_url .. ":" .. session_id
  local key_uri = self:query_uri(key_url)
  return session_uri == key_uri
end

---Check if query result is a table (collection)
---@param url string URL to query
---@return boolean True if result is a table
function Harness:query_is_table(url)
  self.child.lua(string.format([[
    local result = _G.debugger:query(%q)
    _G._query_is_table = (type(result) == "table" and result.type == nil)
  ]], url))
  return self:get("_G._query_is_table") or false
end

---Check if query result is a single entity (not nil, not array)
---@param url string URL to query
---@return boolean True if result is a single entity
function Harness:query_is_entity(url)
  self.child.lua(string.format([[
    local result = _G.debugger:query(%q)
    _G._query_is_entity = (result ~= nil and type(result.type) == "function")
  ]], url))
  return self:get("_G._query_is_entity") or false
end

---Check if query result is nil or empty table
---@param url string URL to query
---@return boolean True if result is nil or empty table
function Harness:query_is_nil_or_empty(url)
  self.child.lua(string.format([[
    local result = _G.debugger:query(%q)
    _G._query_nil_or_empty = (result == nil or (type(result) == "table" and #result == 0))
  ]], url))
  return self:get("_G._query_nil_or_empty") or false
end

---Get a field value from URL query result
---@param url string URL to query (e.g., "@session", "@frame")
---@param field string Field name to get
---@return any value The field value (nil if not found)
function Harness:query_field(url, field)
  -- Inject field name directly to handle metatables
  self.child.lua(string.format([[
    local result = _G.debugger:query(%q)
    _G._query_field_value = nil
    if result then
      local field_val = result.%s
      if field_val ~= nil then
        -- Try to call :get() for signals (use pcall for safety)
        local ok, val = pcall(function() return field_val:get() end)
        if ok then
          _G._query_field_value = val
        else
          _G._query_field_value = field_val
        end
      end
    end
  ]], url, field))
  return self:get("_G._query_field_value")
end

---Get the URI of an entity at URL
---@param url string URL to query (e.g., "@session", "@frame")
---@return string|nil uri The entity's URI
function Harness:query_uri(url)
  return self:query_field(url, "uri")
end

---Get the URI of an entity referenced by a field (reference rollup)
---@param url string URL to base entity (e.g., binding URI)
---@param field string Field name that is a reference rollup
---@return string|nil uri The referenced entity's URI
function Harness:query_field_uri(url, field)
  -- Get entity, access reference rollup, get its URI
  self.child.lua(string.format([[
    local result = _G.debugger:query(%q)
    _G._query_field_uri = nil
    if result then
      local field_val = result.%s
      if field_val ~= nil then
        local ok, entity = pcall(function() return field_val:get() end)
        if ok and entity and entity.uri then
          local uri_ok, uri = pcall(function() return entity.uri:get() end)
          if uri_ok then
            _G._query_field_uri = uri
          end
        end
      end
    end
  ]], url, field))
  return self:get("_G._query_field_uri")
end

---Check if URL query result matches another URL query result
---@param url1 string First URL
---@param url2 string Second URL
---@return boolean True if both resolve to the same entity (by URI)
function Harness:query_same(url1, url2)
  self.child.lua(string.format([[
    local r1 = _G.debugger:query(%q)
    local r2 = _G.debugger:query(%q)
    -- Compare by URI since query may return different wrapper objects
    _G._query_same = (r1 ~= nil and r2 ~= nil and r1.uri and r2.uri and r1.uri:get() == r2.uri:get())
  ]], url1, url2))
  return self:get("_G._query_same") or false
end

---Call a method on an entity resolved from URL
---@param url string URL to query (e.g., "@frame", "@frame/scopes[0]")
---@param method string Method name to call (e.g., "fetchScopes", "fetchVariables")
function Harness:query_call(url, method)
  self.child.lua(string.format([[
    local e = _G.debugger:query(%q)
    if e and e.%s then e:%s() end
  ]], url, method, method))
end

---Call a method on an entity and return the result's URI
---@param url string URL to query (e.g., "@session")
---@param method string Method name to call that returns an entity (e.g., "rootAncestor")
---@return string|nil uri The returned entity's URI
function Harness:query_method_uri(url, method)
  self.child.lua(string.format([[
    local e = _G.debugger:query(%q)
    _G._query_method_uri = nil
    if e and e.%s then
      local result = e:%s()
      if result and result.uri then
        _G._query_method_uri = result.uri:get()
      end
    end
  ]], url, method, method))
  return self:get("_G._query_method_uri")
end

---Focus a URL/URI (or empty string to clear focus)
---@param url string URL/URI to focus, or "" to unfocus
function Harness:query_focus(url)
  self.child.lua(string.format([[ _G.debugger.ctx:focus(%q) ]], url))
end

---Install identity module (for URI resolution tests)
function Harness:install_identity()
  self.child.lua([[ require("neodap.identity").install(_G.debugger) ]])
end

---Check if a URI resolves back to the same entity via query
---@param url string URL to get entity from (e.g., "@session")
---@return boolean True if entity.uri:get() resolves back to entity
function Harness:query_uri_roundtrips(url)
  self.child.lua(string.format([[
    local entity = _G.debugger:query(%q)
    _G._uri_roundtrips = false
    if entity and entity.uri then
      local uri = entity.uri:get()
      if uri then
        local resolved = _G.debugger:query(uri)
        _G._uri_roundtrips = (resolved == entity)
      end
    end
  ]], url))
  return self:get("_G._uri_roundtrips") or false
end

---Check @frame/source query (one-to-one edge returning 0 or 1 Source)
---Assumes @frame is already focused
---@return boolean is_valid True if source query is valid (0 or 1 items, Source type)
function Harness:query_frame_source_valid()
  local count = self:query_count("@frame/source")
  if count == 0 then
    return true -- No source is valid
  elseif count == 1 then
    local entity_type = self:query_type("@frame/source[0]")
    return entity_type == "Source"
  end
  return false
end

-------------------------------------------------------------------------------
-- Entity Link Helpers
-------------------------------------------------------------------------------

---Get scope information for all scopes in current frame
---@return table[] Array of { name, variablesReference, expensive }
function Harness:get_scopes_info()
  local count = self:query_count("@frame/scopes")
  local result = {}
  for i = 0, count - 1 do
    local scope_url = string.format("@frame/scopes[%d]", i)
    table.insert(result, {
      name = self:query_field(scope_url, "name"),
      variablesReference = self:query_field(scope_url, "variablesReference"),
      expensive = self:query_field(scope_url, "expensive"),
    })
  end
  return result
end

---Dispose the debugger (cleanup all sessions, watchers, etc.)
function Harness:dispose()
  self:query_call("/", "dispose")
end

-------------------------------------------------------------------------------
-- Multi-adapter test generation
-------------------------------------------------------------------------------

---List of adapter names to run integration tests with
---@type AdapterName[]
M.enabled_adapters = { "javascript", "python" }

---Creates test sets that run with multiple adapters
---Each adapter gets its own test set with the same test cases
---
---Usage:
---```lua
---return harness.integration("session", function(T, ctx)
---  T["state transitions"] = function()
---    local h = ctx.create()
---    h:fixture("simple-vars")
---    h:cmd("DapLaunch Debug stop")
---    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
---    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
---  end
---end)
---```
---@param name string Test group name
---@param define_tests fun(T: table, h: TestHarness) Function that defines tests
---@return table Test set for MiniTest
function M.integration(name, define_tests)
  local T = MiniTest.new_set()

  for _, adapter_name in ipairs(M.enabled_adapters) do
    local adapter = M.adapters[adapter_name]
    local child = MiniTest.new_child_neovim()

    T[adapter_name] = MiniTest.new_set({
      hooks = {
        pre_case = function()
          child.restart({ "-u", "tests/init.lua", "--headless" })
        end,
        post_case = function()
          child.stop()
        end,
      },
    })

    T[adapter_name][name] = MiniTest.new_set()

    -- Create harness factory for this adapter
    local function create_harness()
      local h = M.new(child, adapter)
      h:setup_neodap()
      return h
    end

    -- Define tests with context that includes harness factory
    define_tests(T[adapter_name][name], {
      create = create_harness,
      adapter = adapter,
      adapter_name = adapter_name,
    })
  end

  return T
end

---Simplified integration helper - creates harness in each test
---Usage:
---```lua
---local T = MiniTest.new_set()
---local adapter = harness.for_adapter("python")
---
---T["my tests"] = MiniTest.new_set({
---  hooks = adapter.hooks,
---})
---
---T["my tests"]["does something"] = function()
---  local h = adapter.harness()
---  h:fixture("simple-vars")
---  h:cmd("DapLaunch Debug")
---end
---```
---@param adapter_name AdapterName
---@return table { hooks: table, harness: fun(): TestHarness, adapter: table }
function M.for_adapter(adapter_name)
  local adapter = M.adapters[adapter_name]
  local child = MiniTest.new_child_neovim()
  local current_harness = nil

  return {
    hooks = {
      pre_case = function()
        child.restart({ "-u", "tests/init.lua", "--headless" })
        current_harness = M.new(child, adapter)
        current_harness:setup_neodap()
      end,
      post_case = function()
        if current_harness then
          current_harness:cleanup()
        end
        child.stop()
      end,
    },
    harness = function()
      return current_harness
    end,
    adapter = adapter,
  }
end

-------------------------------------------------------------------------------
-- Neotest Helpers
-------------------------------------------------------------------------------

---Setup neotest with neodap strategy
---@param adapter_type string Adapter type name (e.g., "python") - unused, adapters configured in neodap.setup()
function Harness:setup_neotest(adapter_type)
  self.child.lua([[
    -- Load neotest_strategy plugin (adapters already configured in neodap.setup())
    local strategy_api = require("neodap").use(require("neodap.plugins.neotest_strategy"))
    _G.neotest_strategy_api = strategy_api

    -- Setup neotest with our strategy
    require("neotest").setup({
      adapters = {
        require("neotest-python")({
          dap = { justMyCode = false },
        }),
      },
      strategies = {
        neodap = strategy_api.strategy,
      },
    })
  ]])
end

return M
