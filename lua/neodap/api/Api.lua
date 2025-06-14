local Class = require("neodap.tools.class")
local Session = require("neodap.api.Session.Session")
local BreakpointManager = require("neodap.api.Breakpoint.BreakpointManager")

---@class ApiProps
---@field sessions { [integer]: api.Session }
---@field listeners { [string]: fun(session: api.Session) }
---@field manager Manager

---@class Api: ApiProps
---@field new Constructor<ApiProps>
local Api = Class()

---@return Api
function Api.register(manager)
  local instance = Api:new({
    sessions = {},
    manager = manager,
    listeners = {},
  })

  -- Initialize the breakpoint manager
  manager.breakpoints = BreakpointManager.create(instance)

  manager:onSession(function(session)
    instance.sessions[session.id] = Session.wrap(session, manager)
    for _, listener in pairs(instance.listeners) do
      listener(instance.sessions[session.id])
    end
  end, { name = "api" })

  return instance
end

---@param listener fun(session: api.Session)
function Api:onSession(listener, opts)
  opts = opts or {}
  local id = opts.name or math.random(1, 1000000) .. "_session_listener"

  self.listeners[id] = listener
  return function()
    self.listeners[id] = nil
  end
end

function Api:breakpoints()
  return self.manager.breakpoints
end

---@param listener fun(breakpoint: api.SourceBreakpoint)
---@param opts? HookOptions
function Api:onBreakpoint(listener, opts)
  return self.manager.breakpoints:onBreakpointAdded(listener, opts)
end

--- Iterable over all sessions
--- @return fun(): api.Session
function Api:eachSession()
  local sessions = self.sessions
  local keys = vim.tbl_keys(sessions)
  local index = 0

  return function()
    index = index + 1
    if index <= #keys then
      return sessions[keys[index]]
    end
  end
end

return Api
