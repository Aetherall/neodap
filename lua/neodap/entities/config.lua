-- Config entity methods for neograph-native
local log = require("neodap.logger")
local terminate_then = require("neodap.entities.restart")

return function(Config)
  ---Get display name with index
  ---@return string
  function Config:displayName()
    local name = self.name:get() or "?"
    local index = self.index:get() or 1
    return string.format("%s #%d", name, index)
  end

  ---Update state based on session states
  ---Call this when session states change
  ---
  ---Uses target (leaf) rollups for state transitions because some adapters
  ---(like js-debug) have parent sessions that never terminate properly.
  ---
  ---Uses root rollups for stopAll because child processes (auto-attached by
  ---js-debug) can exit transiently without meaning the debug config itself died.
  ---stopAll should only cascade when a root session (explicit launch config) terminates.
  function Config:updateState()
    -- stopAll: check root sessions (the explicitly launched configs)
    if self.stopAll:get() then
      local root_total = self.rootCount:get() or 0
      local root_terminated = self.terminatedRootCount:get() or 0
      local has_active_root = root_terminated < root_total
      local has_terminated_root = root_terminated > 0

      if has_terminated_root and has_active_root then
        -- Avoid re-entry: terminate() will trigger more updateState() calls as sessions die.
        -- Clear stopAll after first trigger so subsequent calls fall through to normal logic.
        self:update({ stopAll = false })
        self:terminate()
        return
      end
    end

    -- State transition: use targets (leaves) because parent sessions may never terminate
    local total = self.targetCount:get() or 0
    local terminated = self.terminatedTargetCount:get() or 0
    local has_active_target = terminated < total

    local new_state = has_active_target and "active" or "terminated"
    if self.state:get() ~= new_state then
      self:update({ state = new_state })
    end
  end

  ---Terminate all sessions in this config
  ---We terminate all sessions (not just roots) because some adapters like js-debug
  ---have parent sessions that don't properly cascade termination to children
  function Config:terminate()
    for session in self.sessions:iter() do
      if session.state:get() ~= "terminated" then
        pcall(function() session:terminate() end)
      end
    end
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
    local debugger = self.debugger:get()
    if not debugger then log:error("Config has no debugger"); return end

    local specifications = self.specifications:get()
    if not specifications or #specifications == 0 then log:error("Config has no stored specifications for restart"); return end

    -- Collect all current sessions before terminating
    local old_sessions = {}
    for session in self.sessions:iter() do
      table.insert(old_sessions, session)
    end

    terminate_then(self, function()
      log:info("Restarting Config: " .. self:displayName())
      for _, session in ipairs(old_sessions) do
        self.sessions:unlink(session)
        session:update({ isConfigRoot = false })
      end
      self:update({ state = "active" })
      for _, spec in ipairs(specifications) do
        local ok, err = pcall(function()
          debugger:debug({ config = spec, config_entity = self })
        end)
        if not ok then
          log:error("Failed to restart session", { name = spec.name, error = tostring(err) })
        end
      end
    end)
  end
end
