-- Config entity methods for neograph-native
return function(Config)
  ---Check if config is active (has non-terminated sessions)
  ---@return boolean
  function Config:isActive()
    return self.state:get() == "active"
  end

  ---Check if config is terminated (all sessions terminated)
  ---@return boolean
  function Config:isTerminated()
    return self.state:get() == "terminated"
  end

  ---Get display name with index
  ---@return string
  function Config:displayName()
    local name = self.name:get() or "?"
    local index = self.index:get() or 1
    return string.format("%s #%d", name, index)
  end

  ---Get short display name (just index)
  ---@return string
  function Config:shortName()
    local index = self.index:get() or 1
    return string.format("#%d", index)
  end

  ---Update state based on target (leaf) session states
  ---Call this when session states change
  ---We only consider targets because some adapters (like js-debug) have
  ---parent sessions that never terminate properly
  function Config:updateState()
    local has_active_target = false
    local has_terminated_target = false
    for target in self.targets:iter() do
      if target.state:get() ~= "terminated" then
        has_active_target = true
      else
        has_terminated_target = true
      end
    end

    -- stopAll: if any target terminated and others are still active, terminate them all
    if self.stopAll:get() and has_terminated_target and has_active_target then
      -- Avoid re-entry: terminate() will trigger more updateState() calls as sessions die.
      -- Clear stopAll after first trigger so subsequent calls fall through to normal logic.
      self:update({ stopAll = false })
      self:terminate()
      return
    end

    local new_state = has_active_target and "active" or "terminated"
    if self.state:get() ~= new_state then
      self:update({ state = new_state })
    end
  end

  ---Terminate all sessions in this config
  ---We terminate all sessions (not just roots) because some adapters like js-debug
  ---have parent sessions that don't properly cascade termination to children
  function Config:terminate()
    local dap_context = require("neodap.plugins.dap.context")
    for session in self.sessions:iter() do
      if session.state:get() ~= "terminated" then
        local dap_session = dap_context.dap_sessions[session]
        if dap_session then
          -- Mark session tree as terminating so closing handler kills terminal processes
          dap_context.mark_terminating(dap_session)
          dap_session:terminate()
        end
      end
    end
  end

  ---Check if this config has any stopped targets
  ---@return boolean
  function Config:hasStoppedTarget()
    return self.stoppedTargetCount:get() > 0
  end

  ---Get target index within this config (1-based)
  ---@param session table The session to find
  ---@return number? index The 1-based index, or nil if not found
  function Config:targetIndex(session)
    local i = 0
    for target in self.targets:iter() do
      i = i + 1
      if target._id == session._id then
        return i
      end
    end
    return nil
  end

  ---Get the current view mode for tree display
  ---@return string "targets" or "roots"
  function Config:getViewMode()
    return self.viewMode:get() or "targets"
  end

  ---Toggle view mode between targets and roots
  ---@return string new_mode The new view mode
  function Config:toggleViewMode()
    local current = self:getViewMode()
    local new_mode = current == "targets" and "roots" or "targets"
    self:update({ viewMode = new_mode })
    return new_mode
  end

  ---Restart this config: terminate all sessions and relaunch with stored specifications
  ---The new sessions will be linked to the same Config entity
  function Config:restart()
    local log = require("neodap.logger")
    local debugger = self.debugger:get()
    if not debugger then
      log:error("Config has no debugger")
      return
    end

    local specifications = self.specifications:get()
    if not specifications or #specifications == 0 then
      log:error("Config has no stored specifications for restart")
      return
    end

    -- Collect all current sessions before terminating
    -- (so we can unlink them from the Config)
    local old_sessions = {}
    for session in self.sessions:iter() do
      table.insert(old_sessions, session)
    end

    -- Terminate all current root sessions
    self:terminate()

    -- Unlink all old sessions from this Config
    -- This ensures new sessions will be the only ones linked
    for _, session in ipairs(old_sessions) do
      self.sessions:unlink(session)
      -- Also clear isConfigRoot on old sessions
      session:update({ isConfigRoot = false })
    end

    -- Reset state to active (we're restarting)
    self:update({ state = "active" })

    -- Schedule relaunch after termination completes
    -- Use vim.defer_fn to allow termination to propagate
    vim.defer_fn(function()
      log:info("Restarting Config: " .. self:displayName())

      for _, spec in ipairs(specifications) do
        local ok, err = pcall(function()
          debugger:debug({ config = spec, config_entity = self })
        end)
        if not ok then
          log:error("Failed to restart session", { name = spec.name, error = tostring(err) })
        end
      end
    end, 100)  -- Small delay to allow termination to propagate
  end
end
