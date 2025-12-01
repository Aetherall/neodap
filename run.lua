-- run.lua - Startup script for nvim MCP
-- Sets up the debugger with common adapters and plugins
--
-- Usage: nvim -u run.lua
-- Or source it: :source run.lua
--
-- Hot reload: :NeodapReload

-- =============================================================================
-- ONE-TIME SETUP (not reloaded)
-- =============================================================================

-- Add project to runtime path
vim.opt.rtp:prepend(".")

-- Enable true colors for frame highlight backgrounds
vim.opt.termguicolors = true

-- Initialize code-workspace (only once)
if not _G._workspace_initialized then
  local workspace_ok, workspace = pcall(require, "code-workspace")
  if workspace_ok then
    workspace.setup()
    -- If no workspace was auto-detected, manually set root to cwd
    if not workspace.get_root_dir() then
      workspace._state.root_dir = vim.fn.getcwd()
    end
    --print("code-workspace: loaded (root: " .. workspace.get_root_dir() .. ")")
  else
    --print("code-workspace: not loaded - " .. tostring(workspace))
  end
  _G._workspace_initialized = true
end

-- =============================================================================
-- DEBUGGER SETUP FUNCTION
-- =============================================================================

local function setup_debugger()
  -- Use the singleton debugger from neodap module
  -- This ensures all code using require("neodap") gets the same instance
  local debugger = require("neodap")

  -- Make debugger globally accessible for easy REPL use
  _G.debugger = debugger
  _G.neostate = require("neostate")

  -- ===========================================================================
  -- ADAPTER REGISTRATION
  -- ===========================================================================

  -- Python (debugpy)
  debugger:register_adapter("python", {
    type = "stdio",
    command = "python3",
    args = { "-m", "debugpy.adapter" },
    exceptionFilters = {
      { filter = "raised",   label = "Raised Exceptions",   default = false },
      { filter = "uncaught", label = "Uncaught Exceptions", default = true },
    },
  })

  -- JavaScript/TypeScript (vscode-js-debug)
  debugger:register_adapter("pwa-node", {
    type = "server",
    command = "js-debug",
    args = { "0" }, -- Let js-debug pick a random port
    connect_condition = function(chunk)
      local h, p = chunk:match("Debug server listening at (.*):(%d+)")
      return tonumber(p), h
    end,
    exceptionFilters = {
      { filter = "all",      label = "All Exceptions",      default = true },
      { filter = "uncaught", label = "Uncaught Exceptions", default = false },
    },
  })

  -- Node.js (alias for pwa-node)
  debugger:register_adapter("node", {
    type = "server",
    command = "js-debug",
    args = { "0" },
    connect_condition = function(chunk)
      local h, p = chunk:match("Debug server listening at (.*):(%d+)")
      return tonumber(p), h
    end,
  })

  -- print("Registered adapters: python, pwa-node, node")

  -- ===========================================================================
  -- PLUGIN SETUP
  -- ===========================================================================

  -- code_workspace: :DapLaunch command for launch.json configs
  require("neodap.plugins.code_workspace")(debugger)
  -- print("Plugin: code_workspace (:DapLaunch)")

  -- breakpoint_signs: Show breakpoint signs in the sign column
  require("neodap.plugins.breakpoint_signs")(debugger)
  -- print("Plugin: breakpoint_signs")

  -- frame_highlights: Highlight current frame location
  require("neodap.plugins.frame_highlights")(debugger)
  -- print("Plugin: frame_highlights")

  -- auto_context: Automatically track context as you navigate
  require("neodap.plugins.auto_context")(debugger)
  -- print("Plugin: auto_context")

  -- dap_jump: :DapJump command to navigate to frames
  require("neodap.plugins.dap_jump")(debugger)
  -- print("Plugin: dap_jump (:DapJump)")

  -- source_buffer: Already setup by require("neodap") singleton
  -- print("Plugin: source_buffer")

  -- variable_edit: Edit variables in buffers (uses .setup() pattern)
  require("neodap.plugins.variable_edit").setup(debugger)
  -- print("Plugin: variable_edit")

  -- variable_completion: DAP completions for variable edit buffers
  require("neodap.plugins.variable_completion")(debugger)
  -- print("Plugin: variable_completion")

  -- dap_variable: :DapVariable command for editing variables with picker
  require("neodap.plugins.dap_variable")(debugger)
  -- print("Plugin: dap_variable (:DapVariable)")

  -- dap_breakpoint: :DapBreakpoint command
  require("neodap.plugins.dap_breakpoint")(debugger)
  -- print("Plugin: dap_breakpoint (:DapBreakpoint)")

  -- auto_stack: Automatically fetch stack when thread stops
  require("neodap.plugins.auto_stack")(debugger)
  -- print("Plugin: auto_stack")

  -- dap_context: :DapContext command for setting context via URI picker
  require("neodap.plugins.dap_context")(debugger)
  -- print("Plugin: dap_context (:DapContext)")

  -- dap_step: :DapStep command for stepping through debug sessions
  require("neodap.plugins.dap_step")(debugger)
  -- print("Plugin: dap_step (:DapStep)")

  -- dap_continue: :DapContinue command for resuming execution
  require("neodap.plugins.dap_continue")(debugger)
  -- print("Plugin: dap_continue (:DapContinue)")

  -- jump_stop: Auto-jump to source when thread stops
  require("neodap.plugins.jump_stop")(debugger)
  -- print("Plugin: jump_stop (:DapJumpStop)")

  -- exception_highlight: Red highlight + virtual text on exceptions
  require("neodap.plugins.exception_highlight")(debugger)
  -- print("Plugin: exception_highlight")

  -- eval_buffer: dap-eval: URI handler for REPL-style input
  require("neodap.plugins.eval_buffer")(debugger)
  -- print("Plugin: eval_buffer (dap-eval:)")

  -- replline: Floating REPL input at cursor
  require("neodap.plugins.replline")(debugger)
  -- print("Plugin: replline (:DapReplLine)")

  -- tree_buffer: dap-tree: URI handler for tree exploration
  require("neodap.plugins.tree_buffer")(debugger)
  -- print("Plugin: tree_buffer (dap-tree:)")

  -- neotest: Strategy for debugging tests via neotest
  local neotest_plugin = require("neodap.plugins.neotest")(debugger)
  _G.neodap_neotest = neotest_plugin
  -- print("Plugin: neotest (strategy)")

  return debugger
end
-- =============================================================================
-- COMMANDS
-- =============================================================================

-- Dev scenario: JS stepping test
vim.api.nvim_create_user_command("NeodapScenarioJS1", function()
  vim.cmd("e tests/fixtures/stepping_test.js")
  vim.cmd("12")
  vim.cmd("DapBreakpoint")
  vim.cmd("DapLaunch Node: Debug stepping_test.js")
end, { desc = "Dev scenario: JS stepping test with breakpoint at line 12" })

-- Dev scenario: Test neotest strategy
vim.api.nvim_create_user_command("NeodapScenarioNeotest", function()
  -- First, set a breakpoint at line 12 (where we want to stop)
  local file = vim.fn.getcwd() .. "/tests/fixtures/stepping_test.js"
  debugger:add_breakpoint({ path = file }, 12)
  print("Breakpoint set at line 12")

  -- Simulate what neotest would do: create a RunSpec and call the strategy
  local strategy = _G.neodap_neotest.get_strategy()

  -- Create a mock RunSpec like neotest adapters provide
  local spec = {
    strategy = {
      type = "pwa-node",
      request = "launch",
      name = "Neotest: Debug JS",
      program = file,
      cwd = vim.fn.getcwd(),
    },
    env = {},
    cwd = vim.fn.getcwd(),
  }

  local context = {
    adapter = { name = "test-adapter" },
    position = { id = "test::example" },
  }

  -- Call the strategy (simulating neotest)
  local process = strategy(spec, context)

  if process then
    print("Strategy returned process interface")
    print("  output file: " .. process.output())

    -- Store globally for inspection
    _G._neotest_process = process
    print("Process stored in _G._neotest_process")
    print("Use :NeodapNeotestAttach to see the session")
  else
    print("Strategy returned nil (failed to start)")
  end
end, { desc = "Test neotest strategy with JS fixture and breakpoint" })

-- Attach to neotest process
-- vim.api.nvim_create_user_command("NeodapNeotestAttach", function()
--   if _G._neotest_process then
--    _G._neotest_process.attach()
--  else
--    print("No neotest process running")
--  end
--end, { desc = "Attach to neotest debug process" })

-- Stop neotest process
--vim.api.nvim_create_user_command("NeodapNeotestStop", function()
--  if _G._neotest_process then
--    _G._neotest_process.stop()
--    print("Stopped neotest process")
--  else
--    print("No neotest process running")
--  end
--end, { desc = "Stop neotest debug process" })

-- =============================================================================
-- INITIAL SETUP
-- =============================================================================

setup_debugger()

-- =============================================================================
-- NEOTEST SETUP
-- =============================================================================

local neotest_ok, neotest = pcall(require, "neotest")
if neotest_ok then
  neotest.setup({
    adapters = {
      require("neotest-jest")({
        jestCommand = "npx jest",
        cwd = function() return vim.fn.getcwd() end,
      }),
    },
    -- Register our neodap strategy
    strategies = {
      neodap = _G.neodap_neotest.get_strategy(),
    },
  })
  print("Neotest: configured with neodap strategy")
else
  print("Neotest: not available")
end

print("=== Debugger Ready ===")

print("  :NeodapScenarioJS1           - Start the mcp ready debug configuration")
print("  :edit dap-tree:       - Open tree explorer for debug entities")
print("  :edit dap-eval:@frame - Open REPL input buffer for evaluation")

