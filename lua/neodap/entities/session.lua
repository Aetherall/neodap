-- Session entity methods for neograph-native
return function(Session)
  ---Check if session is running
  ---@return boolean
  function Session:isRunning()
    return self.state:get() == "running"
  end

  ---Check if session is stopped
  ---@return boolean
  function Session:isStopped()
    return self.state:get() == "stopped"
  end

  ---Check if session is terminated
  ---@return boolean
  function Session:isTerminated()
    return self.state:get() == "terminated"
  end

  ---Check if key matches this session
  ---@param key string
  ---@return boolean
  function Session:matchKey(key)
    return self.sessionId:get() == key
  end

  ---Check if session has any non-terminated children
  ---@return boolean
  function Session:hasActiveChildren()
    for child in self.children:iter() do
      if child.state:get() ~= "terminated" then
        return true
      end
    end
    return false
  end

  ---Find thread by DAP threadId
  ---@param threadId number DAP thread ID
  ---@return neodap.entities.Thread?
  function Session:findThreadById(threadId)
    for thread in self.threads:iter() do
      if thread.threadId:get() == threadId then
        return thread
      end
    end
  end

  ---Check if this session is an ancestor of another session
  ---@param other neodap.entities.Session
  ---@return boolean
  function Session:isAncestorOf(other)
    -- parent is a reference rollup, use :get()
    local parent = other.parent:get()
    while parent do
      if parent._id == self._id then return true end
      parent = parent.parent:get()
    end
    return false
  end

  ---Check if this session is a descendant of another session
  ---@param other neodap.entities.Session
  ---@return boolean
  function Session:isDescendantOf(other)
    return other:isAncestorOf(self)
  end

  ---Check if this session is in the same tree as another session
  ---@param other neodap.entities.Session
  ---@return boolean
  function Session:isInSameTreeAs(other)
    if self._id == other._id then return true end
    return self:isAncestorOf(other) or self:isDescendantOf(other)
  end

  ---Get the root ancestor of this session (topmost parent)
  ---@return neodap.entities.Session
  function Session:rootAncestor()
    local parent = self.parent:get()
    if parent then
      return parent:rootAncestor()
    end
    return self
  end
end
