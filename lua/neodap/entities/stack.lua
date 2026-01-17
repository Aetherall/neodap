-- Stack entity methods for neograph-native
return function(Stack)
  ---Check if key matches this stack
  ---@param key string
  ---@return boolean
  function Stack:matchKey(key)
    return self.index:get() == tonumber(key)
  end

  ---Check if this is the current stack for its thread
  ---@return boolean
  function Stack:isCurrent()
    return self.stackOf:get() ~= nil
  end

  ---Find a frame by its index within this stack
  ---@param index number Frame index (0-based, as per DAP spec)
  ---@return neodap.entities.Frame?
  function Stack:frameAtIndex(index)
    for frame in self.frames:iter() do
      if frame.index:get() == index then
        return frame
      end
    end
  end

  ---Check if stack's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Stack:isSessionTerminated()
    local thread = self.thread:get()
    if not thread then return true end  -- Can't reach session, assume terminated
    return thread:isSessionTerminated()
  end
end
