-- Update operations for breakpoints (set_condition, enable, disable, etc.)

local a = require("neodap.async")

local function setup(api, debugger, await_adjust, candidates_at, disambiguate)
  ---Find breakpoint via disambiguate (sync path)
  ---@param loc neodap.Location
  ---@param action string
  ---@return neodap.entities.Breakpoint|nil|false
  local function find_bp_sync(loc, action)
    local candidates = candidates_at(loc)
    if #candidates == 0 then return nil end
    local bp
    disambiguate(candidates, loc, action, function(_, result) bp = result end)
    return bp
  end

  ---Find breakpoint via disambiguate (async path with adjustment)
  ---@param loc neodap.Location
  ---@param action string
  ---@return neodap.entities.Breakpoint|nil|false
  local function find_bp_async(loc, action)
    local adj = await_adjust(loc)
    local candidates = candidates_at(adj)
    if #candidates == 0 then return nil end
    return a.wait(function(cb) disambiguate(candidates, adj, action, cb) end)
  end

  function api.set_condition(loc, condition)
    local bp
    if loc:is_point() or not debugger:supportsBreakpointLocations() then
      bp = find_bp_sync(loc, "set_condition")
    else
      bp = find_bp_async(loc, "set_condition")
    end
    if bp == false then return end
    if not bp then api.add(loc, { condition = condition }); return end
    bp:update({ condition = condition })
    bp:sync()
  end
  api.set_condition = a.fn(api.set_condition)

  function api.set_log_message(loc, message)
    local bp
    if loc:is_point() or not debugger:supportsBreakpointLocations() then
      bp = find_bp_sync(loc, "set_log_message")
    else
      bp = find_bp_async(loc, "set_log_message")
    end
    if bp == false then return end
    if not bp then api.add(loc, { logMessage = message }); return end
    bp:update({ logMessage = message })
    bp:sync()
  end
  api.set_log_message = a.fn(api.set_log_message)

  function api.enable(loc)
    local bp
    if loc:is_point() or not debugger:supportsBreakpointLocations() then
      bp = find_bp_sync(loc, "enable")
    else
      bp = find_bp_async(loc, "enable")
    end
    if not bp then return end
    bp:enable()
    bp:sync()
  end
  api.enable = a.fn(api.enable)

  function api.disable(loc)
    local bp
    if loc:is_point() or not debugger:supportsBreakpointLocations() then
      bp = find_bp_sync(loc, "disable")
    else
      bp = find_bp_async(loc, "disable")
    end
    if not bp then return end
    bp:disable()
    bp:sync()
  end
  api.disable = a.fn(api.disable)
end

return { setup = setup }
