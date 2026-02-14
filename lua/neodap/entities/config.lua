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

  ---Update state based on target (leaf) session states
  ---Call this when session states change
  ---Uses target (leaf) rollups because some adapters (like js-debug) have
  ---parent sessions that never terminate properly.
  ---
  ---Note: stopAll is NOT checked here. It is handled in Session:terminate()
  ---and Session:disconnect() so it only triggers on manual stop, not on
  ---natural process termination.
  function Config:updateState()
    local total = self.targetCount:get() or 0
    local terminated = self.terminatedTargetCount:get() or 0
    local has_active_target = terminated < total

    local new_state = has_active_target and "active" or "terminated"
    if self.state:get() ~= new_state then
      self:update({ state = new_state })
    end
  end

  ---Check and trigger stopAll cascade (called from Session:terminate/disconnect)
  ---Only cascades on manual stop of a root session, not on natural termination.
  function Config:checkStopAll()
    if not self.stopAll:get() then return end
    -- Clear stopAll before cascading to prevent re-entry
    self:update({ stopAll = false })
    self:terminate()
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
