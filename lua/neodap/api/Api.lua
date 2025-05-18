local Class = require("neodap.tools.class")
local Session = require("neodap.api.Session")



---@class ApiProps
---@field sessions { [integer]: Session }
---@field listeners { [string]: fun(session: Session) }
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

  manager:onSession(function(session)
    instance.sessions[session.id] = Session.wrap(session)
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

return Api
