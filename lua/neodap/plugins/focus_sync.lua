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
  debugger.ctx.frame:use(function(frame)
    if not frame then return end

    frame:update({ focused = true })
    local thread = frame:thread()
    if thread then
      thread:update({ focused = true })
    end

    -- Cleanup: clear focused when focus moves away
    return function()
      if not frame:isDeleted() then
        frame:update({ focused = false })
      end
      if thread and not thread:isDeleted() then
        thread:update({ focused = false })
      end
    end
  end)

  return {}
end
