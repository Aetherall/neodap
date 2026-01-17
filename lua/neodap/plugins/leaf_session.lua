---Leaf session plugin for neodap
---Automatically focuses "leaf" sessions (sessions with no children)
---
---This is essential for js-debug and similar adapters that spawn child sessions.
---When a child session is created, focus automatically moves to it.
---When a child session terminates, focus moves back to the parent (if it becomes a leaf).

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  ---Helper to refocus parent when child is no longer active
  ---@param session any Parent session
  ---@param child any Child session that terminated/was removed
  local function maybe_refocus_parent(session, child)
    vim.schedule(function()
      if not session:hasActiveChildren() then
        local focused = debugger.ctx.session:get()
        if focused == child or not focused then
          debugger.ctx:focus(session.uri:get())
        end
      end
    end)
  end

  -- Scoped subscriptions - cleanup handled via debugger:use()
  debugger.sessions:each(function(session)
    session.children:each(function(child)
      -- When child added and parent is focused, move focus to child
      -- Note: Must schedule because ctx.session:get() uses nvim_get_current_buf
      -- which can't be called in fast event contexts (edge callbacks)
      vim.schedule(function()
        local focused = debugger.ctx.session:get()
        if focused == session then
          debugger.ctx:focus(child.uri:get())
        end
      end)

      -- Watch child state for termination (refocus parent)
      local prev_state = child.state:get()
      child.state:use(function(new_state)
        local old_state = prev_state
        prev_state = new_state
        if new_state == "terminated" and old_state ~= "terminated" then
          maybe_refocus_parent(session, child)
        end
      end)

      -- Cleanup: when child removed from graph, refocus parent
      return function()
        maybe_refocus_parent(session, child)
      end
    end)
  end)

  return {}
end
