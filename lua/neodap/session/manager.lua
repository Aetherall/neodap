local Class = require("neodap.tools.class")
local Sequence = require("neodap.tools.sequence")

---@class ManagerProps
---@field sessions { [integer]: Session }
---@field root_sessions { [integer]: Session }
---@field listeners { [string]: fun(session: Session) }
---@field sequence Sequence
---@field breakpoints api.BreakpointManager

---@class Manager: ManagerProps
---@field new Constructor<ManagerProps>
local Manager = Class()


---@return Manager
function Manager.create()
  local instance = Manager:new({
    sequence = Sequence:zero(),
    sessions = {},
    root_sessions = {},
    listeners = {},
    breakpoints = nil, -- Will be initialized by Api
  })

  return instance
end

function Manager:generateSessionId()
  return self.sequence:next()
end

function Manager:addSession(session)
  self.sessions[session.id] = session
  if not session.parent then
    self.root_sessions[session.id] = session
  end

  for _, listener in pairs(self.listeners) do
    listener(session)
  end
end

---@param session Session
function Manager:removeSession(session)
  self.sessions[session.id] = nil
  if not session.parent then
    self.root_sessions[session.id] = nil
  end


  -- Hoist a session's children to the parent if it exists
  for _, child in pairs(session.children) do
    if session.parent then
      session.parent.children[child.id] = child
      child.parent = session.parent
    else
      self.root_sessions[child.id] = child
    end
  end
end

---@param listener fun(session: Session)
---@param opts? { name?: string }
function Manager:onSession(listener, opts)
  opts = opts or {}
  local id = opts.name or math.random(1, 1000000) .. "_session_listener"

  self.listeners[id] = listener

  return function()
    self.listeners[id] = nil
  end
end

return Manager
