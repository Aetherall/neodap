-- Stack entity methods for neograph-native
return function(Stack)
  ---Find a frame by its index within this stack
  ---@param index number Frame index (0-based, as per DAP spec)
  ---@return neodap.entities.Frame?
  function Stack:frameAtIndex(index)
    for frame in self.frames:filter({ filters = {{ field = "index", op = "eq", value = index }} }):iter() do
      return frame
    end
  end

  ---Get the session this stack belongs to (Stack → Thread → Session)
  ---@return neodap.entities.Session?
  function Stack:session()
    local thread = self.thread:get()
    return thread and thread.session:get()
  end

  ---Check if stack's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Stack:isSessionTerminated()
    local session = self:session()
    if not session then return true end
    return session:isTerminated()
  end
end
