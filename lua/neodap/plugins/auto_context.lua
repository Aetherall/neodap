-- Plugin: Automatically manage debug context as users navigate files
-- Context "just follows you" - switching files restores appropriate context
--
-- Uses BUFFER-LOCAL context to enable:
-- - Each buffer remembers its own focused frame
-- - Multiple frames at same line (recursion) stay sticky
-- - Moving to different line with frames updates context
--
-- Hybrid strategy:
-- - CursorMoved to different line WITH frames → update to closest
-- - CursorMoved to same line or line without frames → stay sticky
-- - Explicit selection (DapJump) → always updates

local neostate = require("neostate")

---@class AutoContextConfig
---@field debounce_ms? number  Cursor debounce (default: 100)

---@param debugger Debugger
---@param config? AutoContextConfig
---@return function cleanup
return function(debugger, config)
  config = config or {}
  local debounce_ms = config.debounce_ms or 100

  local augroup = vim.api.nvim_create_augroup("DapAutoContext", { clear = true })
  local debounce_timer = nil
  local buffer_watches = {}  -- bufnr -> Disposable (for source watching)
  local pinned_lines = {}    -- bufnr -> number (line where context was pinned)

  ---Find closest frame to cursor line
  local function find_closest_frame(source, cursor_line)
    local best, best_dist = nil, math.huge
    for frame in source:active_frames():iter() do
      local dist = math.abs(frame.line - cursor_line)
      if dist < best_dist then
        best_dist, best = dist, frame
      end
    end
    return best
  end

  ---Find any frame at exact line
  local function has_frame_at_line(source, line)
    for frame in source:active_frames():iter() do
      if frame.line == line then
        return true
      end
    end
    return false
  end

  ---Update context for buffer (hybrid strategy)
  ---@param bufnr number
  ---@param force? boolean  Force update even if same line
  ---@param frame_hint? table  Optional frame to use instead of finding by cursor
  local function update_context(bufnr, force, frame_hint)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    if buf_name == "" then return end

    local key = buf_name:match("dap:source:(.+)$") or buf_name
    local source = debugger.sources:get_one("by_correlation_key", key)
    local ctx = debugger:context(bufnr)

    if not source then
      -- No source for this buffer - unpin if not already
      if ctx:is_pinned() then
        ctx:unpin()
        pinned_lines[bufnr] = nil
      end
      return
    end

    -- If we have a frame hint (from onActiveFrame), use it directly
    if frame_hint then
      ctx:pin(frame_hint.uri)
      pinned_lines[bufnr] = frame_hint.line
      return
    end

    -- For cursor-based updates, only run if we're in this buffer
    if bufnr ~= vim.api.nvim_get_current_buf() then return end

    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

    -- Hybrid strategy: only update if cursor moved to DIFFERENT line with frames
    local last_pinned_line = pinned_lines[bufnr]

    if not force and last_pinned_line then
      -- Already pinned - check if we should update
      if cursor_line == last_pinned_line then
        -- Same line - stay sticky (handles recursive frames)
        return
      end

      -- Different line - only update if new line has frames
      if not has_frame_at_line(source, cursor_line) then
        -- New line has no frames - stay sticky
        return
      end
    end

    -- Find closest frame and pin
    local frame = find_closest_frame(source, cursor_line)
    if frame then
      ctx:pin(frame.uri)
      pinned_lines[bufnr] = frame.line
    else
      ctx:unpin()
      pinned_lines[bufnr] = nil
    end
  end

  ---Setup source watching for buffer
  local function setup_buffer(bufnr)
    if buffer_watches[bufnr] then return end

    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    if buf_name == "" then return end

    local key = buf_name:match("dap:source:(.+)$") or buf_name

    local watch = neostate.Disposable({}, nil, "AutoContext:" .. bufnr)
    watch:set_parent(debugger)
    buffer_watches[bufnr] = watch

    watch:run(function()
      debugger.sources:where("by_correlation_key", key):each(function(source)
        -- Use onTopFrame to get only the top frame at this source location
        -- This ensures we follow the current execution point, not older stack frames
        return source:onTopFrame(function(frame)
          vim.schedule(function()
            -- Update context with the new frame directly (works even when viewing other buffers)
            update_context(bufnr, true, frame)
          end)
        end)
      end)
    end)

    watch:on_dispose(function()
      buffer_watches[bufnr] = nil
      pinned_lines[bufnr] = nil
    end)
  end

  ---Debounced update for cursor movement
  local function debounced_update()
    if debounce_timer then vim.fn.timer_stop(debounce_timer) end
    debounce_timer = vim.fn.timer_start(debounce_ms, function()
      debounce_timer = nil
      vim.schedule(function()
        update_context(vim.api.nvim_get_current_buf(), false)
      end)
    end)
  end

  -- BufEnter: setup watching + immediate update
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(ev)
      setup_buffer(ev.buf)
      -- Force update on buffer enter to initialize context
      update_context(ev.buf, true)
    end,
  })

  -- CursorMoved: debounced update (hybrid - respects sticky)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    callback = debounced_update,
  })

  -- Buffer cleanup
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    callback = function(ev)
      if buffer_watches[ev.buf] then
        buffer_watches[ev.buf]:dispose()
      end
    end,
  })

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    if debounce_timer then vim.fn.timer_stop(debounce_timer) end
    pcall(vim.api.nvim_del_augroup_by_name, "DapAutoContext")
  end)

  -- Return manual cleanup function
  return function()
    for _, watch in pairs(buffer_watches) do watch:dispose() end
    if debounce_timer then vim.fn.timer_stop(debounce_timer) end
    pcall(vim.api.nvim_del_augroup_by_name, "DapAutoContext")
  end
end
