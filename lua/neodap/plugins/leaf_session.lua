---Leaf session plugin for neodap
---Manages the "leaf" flag on sessions and auto-focuses leaf sessions.
---
---A "leaf" session is one with no active (non-terminated) children.
---This is essential for js-debug and similar adapters that spawn child sessions.
---When a child session is created, focus automatically moves to it.
---When a child session terminates, focus moves back to the parent (if it becomes a leaf).
---
---The leaf flag drives schema rollups (targets, activeTargets, stoppedTargets, etc.)
---so it must be kept in sync as children come and go.

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  ---Update leaf flag and optionally refocus when a child is no longer active
  ---@param session any Parent session
  ---@param child any Child session that terminated/was removed
  local function on_child_inactive(session, child)
    if not session:hasActiveChildren() then
      -- Refocus: move focus from terminated child to parent
      vim.schedule(function()
        local focused = debugger.ctx.session:get()
        if focused == child or not focused then
          debugger.ctx:focus(session.uri:get())
        end

        -- Re-leaf: promote parent to leaf if it has no active children and is
        -- not terminated itself. We check state here (in vim.schedule) rather
        -- than synchronously because the parent's termination event may arrive
        -- in the same tick as the child's — deferring lets both state changes
        -- settle before we decide.
        if not session:hasActiveChildren() and session.state:get() ~= "terminated" then
          session:update({ leaf = true })
        end
      end)
    end
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

      -- Watch child state for termination (re-leaf parent, refocus)
      local prev_state = child.state:get()
      child.state:use(function(new_state)
        local old_state = prev_state
        prev_state = new_state
        if new_state == "terminated" and old_state ~= "terminated" then
          on_child_inactive(session, child)
        end
      end)

      -- Cleanup: when child removed from graph, re-leaf parent
      return function()
        on_child_inactive(session, child)
      end
    end)
  end)

  return {}
end
