local name = "DebugMode"

return {
  name = name,
  description = "A vim mode dedicated to debugging with arrow key navigation for stepping and stack frame exploration",

  ---@param api Api
  plugin = function(api)
    -- Plugin-scoped state - isolated per plugin instance
    local state = {
      sessions = {},
      stoppedThread = nil,
      currentFrameIndex = nil,
      frames = {},
      isDebugModeActive = false,
      keymaps = {},
      namespace = vim.api.nvim_create_namespace("debug_mode_" .. math.random(1000000))
    }

    -- Clear all debug session state
    local function clearDebugSession()
      -- Schedule extmark clearing for later (can't call nvim_list_bufs in fast event context)
      vim.schedule(function()
        -- Clear all debug highlights from all buffers
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_clear_namespace(buf, state.namespace, 0, -1)
          end
        end
      end)

      state.stoppedThread = nil
      state.currentFrameIndex = nil
      state.frames = {}
    end

    -- Update debug session with stopped thread and stack frames
    local function updateDebugSession(thread, stack)
      state.stoppedThread = thread
      state.frames = {}
      state.currentFrameIndex = 1

      if stack then
        local frames = stack:frames()
        if frames then
          for _, frame in ipairs(frames) do
            table.insert(state.frames, frame)
          end
        end
      end
    end

    -- Navigate to a specific stack frame
    local function navigateToFrame(frameIndex)
      if not state.frames or #state.frames == 0 or not frameIndex then
        return
      end

      local frame = state.frames[frameIndex]
      if not frame or not frame.ref then
        return
      end

      local frameRef = frame.ref
      if not frameRef.source or not frameRef.source.path then
        return
      end

      -- Clear existing highlights from all buffers first
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_clear_namespace(buf, state.namespace, 0, -1)
        end
      end

      -- Open the file and navigate to the line
      vim.cmd('edit ' .. frameRef.source.path)
      if frameRef.line then
        -- Ensure cursor position is within buffer bounds
        local line_count = vim.api.nvim_buf_line_count(0)
        local safe_line = math.min(frameRef.line, line_count)
        local safe_col = math.max(0, frameRef.column or 0)
        vim.api.nvim_win_set_cursor(0, { safe_line, safe_col })
      end

      -- Highlight the current frame line
      if frameRef.line then
        -- Ensure line is within buffer bounds for extmark
        local line_count = vim.api.nvim_buf_line_count(0)
        local safe_extmark_line = math.min(frameRef.line - 1, line_count - 1)
        safe_extmark_line = math.max(0, safe_extmark_line)

        -- Use a safe end_col value
        local line_content = vim.api.nvim_buf_get_lines(0, safe_extmark_line, safe_extmark_line + 1, false)[1] or ""
        local safe_end_col = math.max(0, #line_content)

        vim.api.nvim_buf_set_extmark(0, state.namespace, safe_extmark_line, 0, {
          end_col = safe_end_col,
          hl_group = "CursorLine",
          priority = 100
        })
      end

      state.currentFrameIndex = frameIndex
    end

    -- Exit debug mode and restore normal keymaps
    local function exitDebugMode()
      if not state.isDebugModeActive then
        return
      end

      state.isDebugModeActive = false

      -- Remove debug mode keymaps
      for _, keymap in ipairs(state.keymaps) do
        vim.keymap.del('n', keymap.lhs)
      end
      state.keymaps = {}

      -- Clear highlights
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
          vim.api.nvim_buf_clear_namespace(bufnr, state.namespace, 0, -1)
        end
      end

      print("Exited debug mode")
    end

    -- Perform stepping operation while staying in debug mode
    local function performStep(stepFunction, stepName)
      if not state.stoppedThread then
        print("No stopped thread available for " .. stepName)
        return
      end

      -- Don't exit debug mode - keep it active for continuous stepping
      local threadToStep = state.stoppedThread

      -- Log current position before stepping
      if state.currentFrameIndex and state.frames[state.currentFrameIndex] then
        local currentFrame = state.frames[state.currentFrameIndex]
        print(stepName .. " from line " .. (currentFrame.ref.line or "unknown") .. "...")
        print("  - Current file: " .. (currentFrame.ref.source and currentFrame.ref.source.path or "unknown"))
        print("  - Current column: " .. (currentFrame.ref.column or "unknown"))
        print("  - About to call step function on thread: " .. tostring(threadToStep))
      else
        print(stepName .. "...")
      end

      -- Perform the step operation
      print("  - Executing " .. stepName .. " operation...")
      stepFunction(threadToStep)
      print("  - " .. stepName .. " operation completed")
    end

    -- Enter debug mode and set up keymaps
    local function enterDebugMode()
      if not state.stoppedThread then
        print("No active debug session")
        return
      end

      if state.isDebugModeActive then
        print("Already in debug mode")
        return
      end

      state.isDebugModeActive = true
      print(
      "Entered debug mode - Use arrows: →(step into/up frame), ↓(step over), ↑(step out), ←(prev frame), Esc(exit)")

      -- Navigate to current frame initially
      if state.currentFrameIndex and state.frames[state.currentFrameIndex] then
        navigateToFrame(state.currentFrameIndex)
      end

      -- Set up debug mode keymaps
      local function addKeymap(lhs, rhs, desc)
        vim.keymap.set('n', lhs, rhs, { desc = desc })
        table.insert(state.keymaps, { lhs = lhs, rhs = rhs, desc = desc })
      end

      -- Right arrow: Step into or navigate up the stack
      addKeymap('<Right>', function()
        if vim.v.count > 0 then
          -- Navigate up the stack (towards caller)
          local currentIndex = state.currentFrameIndex or 1
          local newIndex = math.max(1, currentIndex - vim.v.count)
          navigateToFrame(newIndex)
        else
          -- Step into
          performStep(function(thread) thread:stepIn() end, "Step into")
        end
      end, "Step into / Navigate up stack")

      -- Down arrow: Step over
      addKeymap('<Down>', function()
        performStep(function(thread) thread:stepOver() end, "Step over")
      end, "Step over")

      -- Up arrow: Step out
      addKeymap('<Up>', function()
        performStep(function(thread) thread:stepOut() end, "Step out")
      end, "Step out")

      -- Left arrow: Navigate down the stack (towards callee)
      addKeymap('<Left>', function()
        local count = vim.v.count > 0 and vim.v.count or 1
        local currentIndex = state.currentFrameIndex or 1
        local newIndex = math.min(#state.frames, currentIndex + count)
        navigateToFrame(newIndex)
      end, "Navigate down stack")

      -- Escape: Exit debug mode
      addKeymap('<Esc>', exitDebugMode, "Exit debug mode")
    end

    -- Set up the global key mapping to enter debug mode with <leader>dm
    vim.keymap.set('n', '<leader>dm', enterDebugMode, { desc = "Enter Debug Mode" })

    -- Track sessions and manage debug state
    api:onSession(function(session)
      -- Track this session
      state.sessions[session] = session
      print("DebugMode: Registered session " .. tostring(session))

      session:onThread(function(thread)
        print("DebugMode: Thread registered " .. tostring(thread))

        thread:onPaused(function(body)
          print("DebugMode: onStopped handler called")
          print("  - Reason: " .. tostring(body.reason))
          print("  - Thread ID: " .. tostring(body.threadId))
          print("  - Was in debug mode: " .. tostring(state.isDebugModeActive))

          -- Get current location info
          local stack = thread:stack()
          local frames = stack:frames()
          if frames and frames[1] and frames[1].ref then
            print("  - Stopped at line: " .. tostring(frames[1].ref.line))
            print("  - File: " .. tostring(frames[1].ref.source and frames[1].ref.source.path))
          end

          -- Update debug session state
          local wasInDebugMode = state.isDebugModeActive

          updateDebugSession(thread, thread:stack())

          vim.schedule(function()
            if wasInDebugMode then
              -- If we were in debug mode and stepped, stay in debug mode
              print("Stepped to new location")
              -- Always navigate to the first frame (current location) after stepping
              navigateToFrame(1)
            else
              print("Stopped at breakpoint (Press <leader>dm to enter debug mode)")
            end
          end)
        end, { name = name .. ".onStopped" })

        thread:onContinued(function(body)
          print("DebugMode: onContinued handler called")
          print("  - Thread ID: " .. tostring(body.threadId))
          print("  - Current stopped thread: " .. tostring(state.stoppedThread))
          print("  - Is debug mode active: " .. tostring(state.isDebugModeActive))
          print("  - Same thread check: " .. tostring(state.stoppedThread == thread))

          -- Don't clear debug session on continued events when in debug mode
          -- This prevents race conditions during stepping operations
          if state.stoppedThread == thread and not state.isDebugModeActive then
            print("  - Clearing debug session (not in debug mode)")
            clearDebugSession()
          else
            print("  - Keeping debug session (in debug mode or different thread)")
          end
        end, { name = name .. ".onContinued" })
      end, { name = name .. ".onThread" })

      session:onTerminated(function()
        -- Remove this session from tracking
        state.sessions[session] = nil

        -- If this session had the stopped thread, clear it
        if state.stoppedThread ~= nil then
          clearDebugSession()
        end
      end, { name = name .. ".onTerminated" })
    end, { name = name .. ".onSession" })
  end
}
