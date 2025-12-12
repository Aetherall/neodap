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
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local neoword = require("neoword")

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
---@param config_entity table Config entity to link the session to
---@return table neotest.StrategyResult
function Process.new(debugger, dap_config, config_entity)
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
  session = debugger:debug({ config = dap_config, config_entity = config_entity })

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

---Get or create the shared Config entity for neotest sessions.
---Creates a single persistent Config on first call; reuses it on subsequent calls.
---Resets state to "active" if the Config had terminated (all prior sessions done).
---@param debugger neodap.entities.Debugger
---@param config_entity_ref table Mutable table holding the shared Config reference
---@return table config_entity
local function get_or_create_config(debugger, config_entity_ref)
  local config_entity = config_entity_ref[1]

  -- Reuse existing Config if it's still valid in the graph
  if config_entity and not config_entity:isDeleted() then
    -- Reset to active if it had terminated (all prior sessions finished)
    if config_entity.state:get() == "terminated" then
      config_entity:update({ state = "active" })
    end
    return config_entity
  end

  -- Create a new shared Config entity
  local config_id = neoword.generate()
  config_entity = entities.Config.new(debugger._graph, {
    uri = uri.config(config_id),
    configId = config_id,
    name = "Neotest",
    index = 1,
    state = "active",
    superseded = false,
    isCompound = true,
  })
  debugger.configs:link(config_entity)
  config_entity_ref[1] = config_entity

  return config_entity
end

---@param debugger neodap.entities.Debugger
---@param config? neodap.plugins.neotest_strategy.Config
return function(debugger, config)
  config = config or {}

  -- Shared Config entity reference (mutable table so closures share state)
  local config_entity_ref = {}

  ---The strategy function for neotest
  ---@param spec table neotest.RunSpec
  ---@return neodap.plugins.neotest_strategy.Process
  local function strategy(spec)
    local dap_config = spec.strategy
    if not dap_config or vim.tbl_isempty(dap_config) then
      return nil -- Adapter doesn't support debug strategy
    end

    require("neodap.logger"):trace("neotest strategy dap_config", dap_config)

    local cfg = get_or_create_config(debugger, config_entity_ref)
    return Process.new(debugger, dap_config, cfg)
  end

  -- Install as neotest's "dap" strategy polyfill
  if config.polyfill then
    package.loaded["neotest.client.strategies.dap"] = strategy
  end

  return {
    strategy = strategy,
  }
end
