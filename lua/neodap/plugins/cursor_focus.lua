local log = require("neodap.logger")

---Auto-context plugin for neodap
---Automatic focus management based on cursor position and stop events
---
---Behavior:
---  - When thread stops: focus top frame
---  - When cursor moves to line with frames: focus closest frame
---  - When cursor moves to line without frames: keep current focus
---
---Session-aware:
---  - Only auto-focuses threads from the currently focused session tree
---  - Prevents focus bouncing between unrelated sessions

---@class AutoContextConfig
---@field debounce_ms? number Cursor debounce (default: 100)



---@param debugger neodap.entities.Debugger
---@param config? AutoContextConfig
---@return table api Plugin API
local function cursor_focus(debugger, config)
  config = config or {}
  local debounce_ms = config.debounce_ms or 100

  local augroup = vim.api.nvim_create_augroup("NeodapCursorFocus", { clear = true })
  local debounce_timer = nil

  -- Track last focused line to implement sticky behavior
  local last_focused_line = nil

  ---Update focus based on cursor position
  ---@param force? boolean Force update even if same line
  local function update_focus_from_cursor(force)
    local bufnr = vim.api.nvim_get_current_buf()
    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    if buf_name == "" then return end

    local source = debugger:findSourceByPath(buf_name)
    if not source then return end

    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

    -- Sticky behavior: only update if cursor moved to DIFFERENT line with frames
    if not force and last_focused_line then
      if cursor_line == last_focused_line then
        -- Same line - stay sticky (handles recursive frames)
        return
      end

      -- Different line - only update if new line has frames
      if not source:hasFrameAtLine(cursor_line) then
        -- New line has no frames - stay sticky
        return
      end
    end

    -- Find closest frame and focus
    local frame = source:closestFrame(cursor_line)
    if frame then
      debugger.ctx:focus(frame.uri:get())
      last_focused_line = frame.line:get()
    end
  end

  ---Focus the top frame of a thread's current stack
  ---@param thread any Thread entity
  local function focus_thread_frame(thread)
    local frame = debugger.ctx:focusThread(thread)
    if frame then
      last_focused_line = frame.line:get()
    end
  end

  ---Debounced update for cursor movement
  local function debounced_update()
    if debounce_timer then
      vim.fn.timer_stop(debounce_timer)
    end
    debounce_timer = vim.fn.timer_start(debounce_ms, function()
      debounce_timer = nil
      vim.schedule(function()
        update_focus_from_cursor(false)
      end)
    end)
  end

  local a = require("neodap.async")

  -- Scoped subscriptions - cleanup is automatic via debugger:use()
  debugger.sessions:each(function(session)
    -- Only focus new session if there's no currently focused session with stopped threads
    -- This prevents overwriting focus during compound launches
    local focused = debugger.ctx.session:get()
    local should_focus = not focused or focused.state:get() == "terminated"

    if should_focus then
      log:debug("cursor_focus: session created, focusing (no active focus)", { session = session.uri:get() })
      debugger.ctx:focus(session.uri:get())
    else
      log:debug("cursor_focus: session created, not focusing (has active focus)", { session = session.uri:get(), focused = focused.uri:get() })
    end

    session.threads:each(function(thread)
      -- When thread stops, load stack and focus top frame (if in focused session tree)
      thread:onStopped(function()
        local thread_session = thread.session:get()
        if not thread_session then
          log:debug("cursor_focus: thread stopped but no session", { thread = thread.uri:get() })
          return
        end

        log:debug("cursor_focus: thread stopped", { thread = thread.uri:get(), session = thread_session.uri:get() })

        -- Check if we should auto-focus this thread
        local focused = debugger.ctx.session:get()
        local focused_has_stopped = focused and focused.stoppedThreads and focused.stoppedThreads:count() > 0

        -- Focus if: no focus, focused is terminated, focused has no stopped threads, or in same context (tree or Config)
        if focused and focused.state:get() ~= "terminated" and focused_has_stopped then
          -- Only skip if focused session already has stopped threads AND this isn't in the same context
          if not debugger.ctx:isInFocusedContext(thread_session) then
            log:debug("cursor_focus: skipping focus - focused session has stopped threads and different context", { thread = thread.uri:get(), focused = focused.uri:get() })
            return
          end
        else
          log:debug("cursor_focus: will focus - no competing stopped threads", { thread = thread.uri:get() })
        end

        -- Load stack (awaitable, memoized) and focus top frame
        local stack = thread:loadCurrentStack()
        if not stack then
          log:debug("cursor_focus: no stack loaded", { thread = thread.uri:get() })
          return
        end

        a.wait(a.main, "auto_context:schedule")
        log:debug("cursor_focus: focusing thread frame", { thread = thread.uri:get() })
        focus_thread_frame(thread)
      end)

      -- Also watch stops for subsequent stops (some adapters don't send "continued" events)
      thread.stops:use(function(seq)
        if not seq or seq == 0 then return end
        if thread.state:get() ~= "stopped" then return end

        local thread_session = thread.session:get()
        if not thread_session then return end
        if not debugger.ctx:isInFocusedContext(thread_session) then return end

        -- Focus top frame on stops change
        a.run(function()
          a.wait(a.main, "auto_context:stops")
          focus_thread_frame(thread)
        end)
      end)
    end)
  end)

  -- BufEnter: initialize focus for buffer
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      -- Force update on buffer enter
      update_focus_from_cursor(true)
    end,
  })

  -- CursorMoved: debounced update (respects sticky behavior)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    callback = debounced_update,
  })

  return {
    update = function(force)
      update_focus_from_cursor(force)
    end,
  }
end

return cursor_focus
