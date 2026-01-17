-- Breakpoint management with Location-based targeting
local a = require("neodap.async")
local Location = require("neodap.location")
local adjust = require("neodap.plugins.breakpoint_cmd.adjust")
local commands = require("neodap.plugins.breakpoint_cmd.commands")

-- Ensure Source methods are available (addBreakpoint, syncBreakpoints)
require("neodap.plugins.dap.source")
require("neodap.plugins.dap.breakpoint")

---Default disambiguate: exact column match, then line-only, then first by column
---@param candidates neodap.entities.Breakpoint[]
---@param loc neodap.Location
---@param action string
---@param callback fun(err: nil, bp: neodap.entities.Breakpoint|nil|false)
local function default_disambiguate(candidates, loc, action, callback)
  for _, bp in ipairs(candidates) do
    if bp.column:get() == loc.column then return callback(nil, bp) end
  end
  for _, bp in ipairs(candidates) do
    if bp.column:get() == nil then return callback(nil, bp) end
  end
  callback(nil, candidates[1])
end

---@class neodap.plugins.breakpoint_cmd.Config
---@field disambiguate? fun(candidates: neodap.entities.Breakpoint[], loc: neodap.Location, action: string, callback: fun(bp: neodap.entities.Breakpoint|nil|false))

---@param debugger neodap.entities.Debugger
---@param config? neodap.plugins.breakpoint_cmd.Config
return function(debugger, config)
  config = config or {}
  local disambiguate = config.disambiguate or default_disambiguate
  local path_locks, api = {}, { Location = Location }
  -- Adjust location - called from async context, runs inline
  local function await_adjust(loc)
    return adjust.adjust(debugger, loc)
  end

  ---Collect breakpoints on same line as loc, sorted by column
  ---@param loc neodap.Location
  ---@return neodap.entities.Breakpoint[]
  local function candidates_at(loc)
    local result = {}
    for bp in debugger:breakpointsAt(loc) do
      if bp.line:get() == loc.line then
        table.insert(result, bp)
      end
    end
    table.sort(result, function(a, b)
      return (a.column:get() or 0) < (b.column:get() or 0)
    end)
    return result
  end

  function api.add(loc, opts)
    opts = opts or {}
    local source = debugger:getOrCreateSource(loc)
    if not source then return end
    local bp = source:addBreakpoint({
      line = loc.line, column = loc.column, condition = opts.condition,
      hitCondition = opts.hitCondition, logMessage = opts.logMessage,
    })
    source:syncBreakpoints()
    return bp
  end

  function api.remove(bp)
    local source = bp.source:get()
    bp:remove()
    if source then source:syncBreakpoints() end
  end

  function api.toggle(loc)
    -- Fast synchronous path when no location adjustment needed
    if loc:is_point() or not debugger:supportsBreakpointLocations() then
      local candidates = candidates_at(loc)
      if #candidates == 0 then return api.add(loc) end
      local bp
      disambiguate(candidates, loc, "toggle", function(_, result) bp = result end)
      if bp == false then return end
      if bp then api.remove(bp); return end
      return api.add(loc)
    end
    -- Async path with location adjustment
    local lock = path_locks[loc.path] or a.mutex(); path_locks[loc.path] = lock; a.wait(lock.lock)
    local adj = await_adjust(loc)
    local candidates = candidates_at(adj)
    if #candidates == 0 then
      local new_bp = api.add(adj); lock:unlock(); return new_bp
    end
    local bp = a.wait(function(cb) disambiguate(candidates, adj, "toggle", cb) end)
    if bp == false then lock:unlock(); return end
    if bp then api.remove(bp); lock:unlock(); return end
    local new_bp = api.add(adj); lock:unlock(); return new_bp
  end
  api.toggle = a.fn(api.toggle)

  commands.setup(api, debugger, await_adjust, candidates_at, disambiguate)
  function api.cleanup() pcall(vim.api.nvim_del_user_command, "DapBreakpoint") end
  return api
end
