-- Plugin: Neotest Strategy
-- Provides a neotest strategy for debugging tests with neodap.
--
-- Usage:
--   neodap.use(require("neodap.plugins.neotest_strategy"), { polyfill = true })
--
--   -- Now strategy = "dap" uses neodap instead of nvim-dap
--   require("neotest").run.run({ strategy = "dap" })

local nio = require("nio")
local dap_context = require("neodap.plugins.dap.context")
local a = require("neodap.async")

---@class neodap.plugins.neotest_strategy.Config
---@field polyfill? boolean Replace neotest's "dap" strategy with neodap (default: false)

---@class neodap.plugins.neotest_strategy.Process
---@field session neodap.entities.Session?
---@field dap_session DapSession?
---@field exit_code number?
---@field output_path string
---@field output_fd userdata?
---@field finished boolean
---@field finish_event table
---@field output_queue string[]
---@field output_waiters function[]

local Process = {}
Process.__index = Process

---Create a new Process wrapping a debug session
---Returns a table of closures (not a class) because neotest calls methods with dot notation
---@param debugger neodap.entities.Debugger
---@param dap_config table DAP launch configuration
---@return table neotest.StrategyResult
function Process.new(debugger, dap_config)
  -- Internal state (closed over by returned functions)
  local session = nil
  local dap_session = nil
  local exit_code = nil
  local output_path = nio.fn.tempname()
  local finish_future = nio.control.future()

  -- Create output file immediately (neotest expects it to exist)
  -- Use sync vim.uv for initial creation (strategy may be called outside async context in tests)
  local output_fd = vim.uv.fs_open(output_path, "w", 438)
  assert(output_fd, "Failed to create output file")

  -- Output accumulator (like neotest's FanoutAccum but simpler)
  local output_subscribers = {}
  local function push_output(text)
    for _, sub in ipairs(output_subscribers) do
      nio.run(function()
        sub(text)
      end)
    end
  end

  -- Internal helpers
  local function write_output(text)
    if output_fd then
      -- Use sync vim.uv since this is called from callbacks outside async context
      vim.uv.fs_write(output_fd, text)
    end
  end

  local function finish()
    if exit_code == nil then
      exit_code = 0
    end
    pcall(finish_future.set)
  end

  local function wire_dap_events()
    dap_session:on("exited", function(body)
      exit_code = body.exitCode or 0
    end)
    dap_session:on("terminated", function()
      finish()
    end)
  end

  local function subscribe_outputs()
    session.outputs:each(function(output)
      local text = output.text:get() or ""
      local category = output.category:get()
      if category == "telemetry" then return end
      write_output(text)
      push_output(text)
    end)
  end

  local function setup_listeners()
    vim.defer_fn(function()
      dap_session = dap_context.get_dap_session(session)
      if dap_session then
        wire_dap_events()
      end
    end, 100)

    subscribe_outputs()

    session.state:use(function(state)
      if state == "terminated" then
        finish()
      end
    end)
  end

  -- Start debug session
  session = debugger:debug({ config = dap_config })

  if session then
    setup_listeners()
  else
    exit_code = 1
    pcall(finish_future.set)
  end

  -- Return neotest.StrategyResult interface (table of closures, NOT a class)
  return {
    is_complete = function()
      return exit_code ~= nil
    end,

    output = function()
      return output_path
    end,

    output_stream = function()
      local queue = nio.control.queue()
      table.insert(output_subscribers, queue.put)
      return function()
        return nio.first({ finish_future.wait, queue.get })
      end
    end,

    attach = function()
      if session then
        local session_uri = session.uri:get()
        vim.cmd.edit("dap://tree/" .. session_uri)
      end
    end,

    stop = function()
      if session and exit_code == nil then
        session:terminate()
      end
    end,

    result = function()
      finish_future:wait()
      return exit_code
    end,
  }
end

---@param debugger neodap.entities.Debugger
---@param config? neodap.plugins.neotest_strategy.Config
return function(debugger, config)
  config = config or {}

  ---The strategy function for neotest
  ---@param spec table neotest.RunSpec
  ---@return neodap.plugins.neotest_strategy.Process
  local function strategy(spec)
    local dap_config = spec.strategy
    if not dap_config or vim.tbl_isempty(dap_config) then
      return nil -- Adapter doesn't support debug strategy
    end

    require("neodap.logger"):trace("neotest strategy dap_config", dap_config)

    return Process.new(debugger, dap_config)
  end

  -- Install as neotest's "dap" strategy polyfill
  if config.polyfill then
    package.loaded["neotest.client.strategies.dap"] = strategy
  end

  return {
    strategy = strategy,
  }
end
