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

  ---Get display-oriented state string
  ---@return string "running"|"stopped"|"terminated"|"unknown"
  function Session:displayState()
    return self.state:get() or "unknown"
  end

  ---Get the chain of session names from root to this session
  ---Returns something like "root > child > grandchild"
  ---@param separator? string Separator between names (default " > ")
  ---@return string
  function Session:chainName(separator)
    separator = separator or " > "
    local names = {}
    local session = self
    while session do
      table.insert(names, 1, session.name:get() or "?")
      session = session.parent:get()
    end
    return table.concat(names, separator)
  end

  ---Check if this session is in the same Config as another session
  ---@param other neodap.entities.Session
  ---@return boolean
  function Session:isInSameConfig(other)
    local my_config = self.config:get()
    local other_config = other.config:get()
    if not my_config or not other_config then
      return false
    end
    return my_config._id == other_config._id
  end

  ---Restart this session's root: terminate the root tree and relaunch that config
  ---The new session will be linked to the same Config entity
  function Session:restartRoot()
    local log = require("neodap.logger")
    local root = self:rootAncestor()
    local cfg = self.config:get()

    if not cfg then
      log:warn("Session has no Config, cannot restart")
      return
    end

    -- Find the specification for this root in Config.specifications
    local specs = cfg.specifications:get()
    if not specs then
      log:error("Config has no stored specifications")
      return
    end

    -- Find matching spec by name
    local root_name = root.name:get()
    local matching_spec = nil
    for _, spec in ipairs(specs) do
      if spec.name == root_name then
        matching_spec = spec
        break
      end
    end

    if not matching_spec then
      log:error("Could not find specification for root session: " .. (root_name or "?"))
      return
    end

    local debugger = self.debugger:get()
    if not debugger then
      log:error("Session has no debugger")
      return
    end

    -- Collect all sessions in this root's tree (to unlink from Config)
    local sessions_to_unlink = {}
    local function collect_tree(session)
      table.insert(sessions_to_unlink, session)
      for child in session.children:iter() do
        collect_tree(child)
      end
    end
    collect_tree(root)

    -- Terminate the root session (children die with it)
    local dap_context = require("neodap.plugins.dap.context")
    local dap_session = dap_context.dap_sessions[root]
    if dap_session then
      -- Mark session tree as terminating so closing handler kills terminal processes
      dap_context.mark_terminating(dap_session)
      dap_session:terminate()
    end

    -- Unlink old sessions from Config before relaunching
    for _, session in ipairs(sessions_to_unlink) do
      cfg.sessions:unlink(session)
      session:update({ isConfigRoot = false })
    end

    -- Schedule relaunch after termination
    vim.defer_fn(function()
      log:info("Restarting root session: " .. (root_name or "?"))

      local ok, err = pcall(function()
        debugger:debug({ config = matching_spec, config_entity = cfg })
      end)
      if not ok then
        log:error("Failed to restart session", { name = matching_spec.name, error = tostring(err) })
      end
    end, 100)
  end
end
