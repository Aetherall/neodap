-- Thread entity methods for neograph-native
local a = require("neodap.async")
local scoped = require("neodap.scoped")

return function(Thread)
  function Thread:isStopped()
    return self.state:get() == "stopped"
  end

  function Thread:isRunning()
    return self.state:get() == "running"
  end

  ---Get display-oriented state string
  ---@return string "running"|"stopped"|"exited"|"unknown"
  function Thread:displayState()
    return self.state:get() or "unknown"
  end

  ---Check if thread's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Thread:isSessionTerminated()
    local session = self.session:get()
    if not session then return true end  -- Can't reach session, assume terminated
    return session:isTerminated()
  end

  function Thread:matchKey(key)
    return self.threadId:get() == tonumber(key)
  end

  ---Get the current/latest stack signal (uses currentStack rollup)
  ---Returns the signal itself, call :get() to get the entity
  ---@return table signal Signal that resolves to Stack or nil
  function Thread:getLatestStack()
    return self.currentStack
  end

  ---Awaitable: blocks until thread enters "stopped" or "exited" state
  ---Returns immediately if already in that state.
  ---@return string state The state that triggered completion ("stopped" or "exited")
  function Thread:untilStopped()
    local state = self.state:get()
    -- Already stopped or exited? Return immediately
    if state == "stopped" or state == "exited" then
      return state
    end

    -- Create event that fires when stopped/exited
    local event = a.event()
    local prev_state = state

    local unsub = self.state:use(function(new_state)
      if new_state ~= prev_state then
        if new_state == "stopped" or new_state == "exited" then
          event:set(new_state)
        end
        prev_state = new_state
      end
    end)

    -- Wait for the event
    local result = a.wait(event.wait, "untilStopped")
    unsub()
    return result
  end

  ---Load the current stack trace
  ---Fetches stack if needed, returns the current stack.
  ---@return Stack? stack The current stack or nil
  function Thread:loadCurrentStack()
    self:fetchStackTrace()
    return self.stack:get()
  end

  Thread.loadCurrentStack = a.fn(Thread.loadCurrentStack)

  ---Subscribe to thread stopped state with async-aware effect
  ---Effect runs when thread enters "stopped".
  ---Effect can return a cleanup function that runs when thread leaves "stopped".
  ---@param effect fun(): fun()?  Effect function, optionally returns cleanup
  ---@return fun() unsub Unsubscribe function
  function Thread:onStopped(effect)
    local parent_scope = scoped.current()
    local cleanup = nil
    local effect_ctx = nil
    local prev_state = self.state:get()

    local function run_effect()
      if effect_ctx then
        effect_ctx:cancel()
      end
      effect_ctx = a.run(function()
        if self.state:get() ~= "stopped" then return end
        cleanup = effect()
      end, nil, parent_scope)
    end

    local function run_cleanup()
      if effect_ctx then
        effect_ctx:cancel()
        effect_ctx = nil
      end
      if cleanup then
        pcall(cleanup)
        cleanup = nil
      end
    end

    -- If already stopped, run effect immediately
    if prev_state == "stopped" then
      run_effect()
    end

    -- Subscribe to state changes using :use()
    local unsub = self.state:use(function(state)
      if state == "stopped" and prev_state ~= "stopped" then
        run_effect()
      elseif state ~= "stopped" and prev_state == "stopped" then
        run_cleanup()
      end
      prev_state = state
    end)

    local function full_unsub()
      unsub()
      run_cleanup()
    end

    if parent_scope then
      parent_scope:onCleanup(full_unsub)
    end

    return full_unsub
  end
end
