-- Session entity methods for neograph-native
local log = require("neodap.logger")
local terminate_then = require("neodap.entities.restart")

return function(Session)
  ---Check if session is terminated
  ---@return boolean
  function Session:isTerminated()
    return self.state:get() == "terminated"
  end

  ---Check if session has any non-terminated children
  ---Uses childCount/terminatedChildCount rollups for O(1) check
  ---@return boolean
  function Session:hasActiveChildren()
    local total = self.childCount:get() or 0
    local terminated = self.terminatedChildCount:get() or 0
    return terminated < total
  end

  ---Find thread by DAP threadId
  ---@param threadId number DAP thread ID
  ---@return neodap.entities.Thread?
  function Session:findThreadById(threadId)
    for thread in self.threads:filter({
      filters = {{ field = "threadId", op = "eq", value = threadId }}
    }):iter() do
      return thread
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

  ---Get the depth of this session in the parent chain (0 for root)
  ---@return number
  function Session:depth()
    local d = 0
    local s = self.parent:get()
    while s do d = d + 1; s = s.parent:get() end
    return d
  end

  ---Find the nearest terminal buffer number walking up the parent chain.
  ---Returns the first valid terminalBufnr found, or nil.
  ---@return number? bufnr
  function Session:findTerminalBufnr()
    local current = self
    while current do
      local bufnr = current.terminalBufnr and current.terminalBufnr:get()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then return bufnr end
      current = current.parent and current.parent:get()
    end
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

  ---Find an ExceptionFilterBinding by its linked ExceptionFilter's filterId
  ---Reverse lookup: find the ExceptionFilter by filterId (indexed), then find its binding for this session
  ---@param filterId string The filter ID to search for
  ---@return neodap.entities.ExceptionFilterBinding?
  function Session:findExceptionFilterBinding(filterId)
    local debugger = self.debugger:get()
    if not debugger then return nil end
    -- O(1) lookup via by_filterId index on Debugger.exceptionFilters
    for ef in debugger.exceptionFilters:filter({
      filters = {{ field = "filterId", op = "eq", value = filterId }}
    }):iter() do
      -- Search this filter's bindings for one linked to this session
      for binding in ef.bindings:iter() do
        if binding.session:get() == self then
          return binding
        end
      end
    end
  end

  ---Iterate all BreakpointBindings across all SourceBindings for this session
  ---Flattens the double-nested sourceBindings → breakpointBindings traversal
  ---@param callback fun(binding: neodap.entities.BreakpointBinding, sourceBinding: neodap.entities.SourceBinding)
  function Session:forEachBreakpointBinding(callback)
    for sb in self.sourceBindings:iter() do
      for bpb in sb.breakpointBindings:iter() do
        callback(bpb, sb)
      end
    end
  end

  ---Restart this session's root: terminate the root tree and relaunch that config
  ---The new session will be linked to the same Config entity
  function Session:restartRoot()
    local root = self:rootAncestor()
    local cfg = self.config:get()
    if not cfg then log:warn("Session has no Config, cannot restart"); return end

    local specs = cfg.specifications:get()
    if not specs then log:error("Config has no stored specifications"); return end

    -- Find matching spec by name
    local root_name = root.name:get()
    local matching_spec = nil
    for _, spec in ipairs(specs) do
      if spec.name == root_name then matching_spec = spec; break end
    end
    if not matching_spec then log:error("Could not find specification for root session: " .. (root_name or "?")); return end

    local debugger = self.debugger:get()
    if not debugger then log:error("Session has no debugger"); return end

    -- Collect all sessions in this root's tree (to unlink from Config)
    local sessions_to_unlink = {}
    local function collect_tree(session)
      table.insert(sessions_to_unlink, session)
      for child in session.children:iter() do
        collect_tree(child)
      end
    end
    collect_tree(root)

    terminate_then(root, function()
      log:info("Restarting root session: " .. (root_name or "?"))
      for _, session in ipairs(sessions_to_unlink) do
        cfg.sessions:unlink(session)
        session:update({ isConfigRoot = false })
      end
      local ok, err = pcall(function()
        debugger:debug({ config = matching_spec, config_entity = cfg })
      end)
      if not ok then
        log:error("Failed to restart session", { name = matching_spec.name, error = tostring(err) })
      end
    end)
  end
end
