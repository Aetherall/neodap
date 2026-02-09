-- Plugin: DapRunToCursor command for running to cursor position
-- Implements "run to cursor" by setting a temporary breakpoint and continuing

local a = require("neodap.async")
local Location = require("neodap.location")
local log = require("neodap.logger")

---@param debugger neodap.entities.Debugger
return function(debugger)
  local api = {}

  ---@param opts? { ignoreBreakpoints?: boolean }
  function api.run_to_cursor(opts)
    opts = opts or {}
    local loc = Location.from_cursor()

    if loc.path == "" then
      log:warn("Buffer has no file path")
      return false
    end

    local thread = debugger.ctx.thread:get()
    if not thread then
      log:warn("No focused thread")
      return false
    end

    local source = debugger:getOrCreateSource(loc)
    local temp_bp = source:addBreakpoint({ line = loc.line })
    if not temp_bp then
      log:error("Failed to create breakpoint")
      return false
    end

    local disabled_breakpoints = {}
    if opts.ignoreBreakpoints then
      for bp in debugger.breakpoints:iter() do
        if bp ~= temp_bp and bp:isEnabled() then
          table.insert(disabled_breakpoints, bp)
          bp:disable()
        end
      end
    end

    local function restore_breakpoints()
      if #disabled_breakpoints == 0 then return end
      local sources_to_sync = {}
      for _, bp in ipairs(disabled_breakpoints) do
        if not bp:isDeleted() then
          bp:enable()
          local bp_source = bp.source:get()
          if bp_source then sources_to_sync[bp_source:id()] = bp_source end
        end
      end
      for _, src in pairs(sources_to_sync) do src:syncBreakpoints() end
      disabled_breakpoints = {}
    end

    a.run(function()
      -- Sync breakpoints and continue
      local sources_to_sync = {}
      if opts.ignoreBreakpoints then
        for _, bp in ipairs(disabled_breakpoints) do
          local bp_source = bp.source:get()
          if bp_source then sources_to_sync[bp_source:id()] = bp_source end
        end
      end
      sources_to_sync[source:id()] = source

      for _, src in pairs(sources_to_sync) do src:syncBreakpoints() end
      thread:continue()

      -- Wait for thread to stop or exit
      thread:untilStopped()

      -- Clean up temp breakpoint and restore disabled breakpoints
      if not temp_bp:isDeleted() then
        temp_bp:remove()
        source:syncBreakpoints()
      end
      restore_breakpoints()
    end)

    return true
  end

  vim.api.nvim_create_user_command("DapRunToCursor", function(cmd_opts)
    api.run_to_cursor({ ignoreBreakpoints = cmd_opts.bang })
  end, { bang = true, desc = "Run to cursor line (! to ignore other breakpoints)" })

  function api.cleanup() pcall(vim.api.nvim_del_user_command, "DapRunToCursor") end

  return api
end
