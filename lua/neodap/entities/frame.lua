-- Frame entity methods for neograph-native
local Location = require("neodap.location")

return function(Frame)
  ---Get location as Location object
  ---@return neodap.Location?
  function Frame:location()
    local source = self.source:get()
    if not source then return nil end
    local uri = source:bufferUri()
    if not uri then return nil end
    return Location.new(uri, self.line:get(), self.column:get())
  end

  ---Check if key matches this frame
  ---@param key string
  ---@return boolean
  function Frame:matchKey(key)
    return self.frameId:get() == tonumber(key)
  end

  ---Check if this is the current frame for its stack
  ---@return boolean
  function Frame:isCurrent()
    local stack = self.stack:get()
    return stack and stack.stackOf:get() ~= nil
  end

  ---Get the thread this frame belongs to
  ---@return neodap.entities.Thread?
  function Frame:getThread()
    local stack = self.stack:get()
    return stack and stack.thread:get()
  end

  -- Alias for compatibility with entities/frame.lua
  Frame.thread = Frame.getThread

  ---Check if frame is in the current (active) stack of its thread
  ---A frame is active if its stack is the thread's stack
  ---@return boolean
  function Frame:isActive()
    local stack = self.stack:get()
    if not stack then return false end
    return stack.stackOf:get() ~= nil
  end

  ---Check if frame is at the top of its stack (index 0)
  ---@return boolean
  function Frame:isTop()
    return self.index:get() == 0
  end

  ---Check if frame's thread is stopped
  ---@return boolean
  function Frame:isStopped()
    local thread = self:thread()
    return thread and thread:isStopped() or false
  end

  ---Check if frame's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Frame:isSessionTerminated()
    local thread = self:thread()
    if not thread then return true end  -- Can't reach session, assume terminated
    return thread:isSessionTerminated()
  end
end
