-- Plugin: Sync focused state to Frame and Thread entities
--
-- Maintains the `focused` boolean property on Frame and Thread entities
-- so renderers can check it directly without needing access to the debugger ctx.
--
-- When focus changes:
--   1. Clears `focused = false` on the previously focused frame/thread
--   2. Sets `focused = true` on the newly focused frame/thread

---@param debugger neodap.entities.Debugger
return function(debugger)
  local prev_frame = nil
  local prev_thread = nil

  debugger.ctx.frame:use(function(frame)
    -- Clear previous
    if prev_frame then
      prev_frame:update({ focused = false })
    end
    if prev_thread then
      prev_thread:update({ focused = false })
    end

    -- Set new
    if frame then
      frame:update({ focused = true })
      local stack = frame.stack:get()
      local thread = stack and stack.thread:get()
      if thread then
        thread:update({ focused = true })
      end
      prev_frame = frame
      prev_thread = thread
    else
      prev_frame = nil
      prev_thread = nil
    end
  end)

  return {}
end
