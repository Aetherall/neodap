-- Smart popup: content-agnostic floating window manager
--
-- Manages multiple popups that automatically:
--   - Show/hide based on caller-provided conditions
--   - Position themselves opposite the cursor
--   - Stack vertically when multiple are visible
--   - Avoid each other and the cursor zone
--   - Hide with hysteresis (delay before hiding to avoid flicker)
--
-- Usage:
--   local popup = require("neodap.ui.smart_popup")
--
--   popup.add_context_provider(function(ctx)
--     ctx.my_condition = some_check()
--   end)
--
--   local handle = popup.register({
--     name = "my_popup",
--     content = "dap://tree/@frame",
--     width = 0.3,
--     height = 0.5,
--     title = " My Popup ",
--     show = function(ctx) return ctx.my_condition end,
--   })
--
--   handle.toggle_pin()  -- pin/unpin (overrides show condition)
--   handle.focus()       -- focus the popup window

local M = {}

M._popups = {}
M._group = nil
M._update_timer = nil
M._context_providers = {}
M._state_unsubs = {} -- unsubscribe callbacks for reactive state watchers

-- Configurable timing
M.SHOW_DELAY = 100       -- ms before showing (debounce from CursorMoved)
M.HIDE_DELAY = 500       -- ms before hiding (hysteresis)
M.REPOSITION_DELAY = 50  -- ms before repositioning on resize

-------------------------------------------------------------------------------
-- Timer helpers (cancellable)
-------------------------------------------------------------------------------

local function cancel_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  return nil
end

local function start_timer(delay, fn)
  local timer = vim.uv.new_timer()
  timer:start(delay, 0, vim.schedule_wrap(function()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    fn()
  end))
  return timer
end

-------------------------------------------------------------------------------
-- Registration
-------------------------------------------------------------------------------

--- Register a popup managed by this module.
--- The popup will auto-show/hide based on the `show` condition.
---@param opts { name?: string, content: string|fun():string, width?: number, height?: number, title?: string, show: fun(ctx: table): boolean, priority?: number, border?: string }
---@return { pin: fun(), unpin: fun(), toggle_pin: fun(), focus: fun(), is_visible: fun(): boolean, is_pinned: fun(): boolean }
function M.register(opts)
  local popup = {
    name = opts.name or ("popup_" .. (#M._popups + 1)),
    content = opts.content,
    width = opts.width or 0.3,
    height = opts.height or 0.5,
    title = opts.title or "",
    show = opts.show,
    priority = opts.priority or 10,
    border = opts.border or "rounded",
    -- Runtime state
    winid = nil,
    bufnr = nil,
    visible = false,
    pinned = false,
    _hide_timer = nil,
  }

  table.insert(M._popups, popup)
  table.sort(M._popups, function(a, b) return a.priority < b.priority end)

  -- Auto-setup manager if not done
  M.setup()

  return {
    pin = function() popup.pinned = true; M._do_update() end,
    unpin = function() popup.pinned = false; M._do_update() end,
    toggle_pin = function()
      popup.pinned = not popup.pinned
      M._do_update()
    end,
    focus = function()
      if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
        vim.api.nvim_set_current_win(popup.winid)
      end
    end,
    is_visible = function() return popup.visible end,
    is_pinned = function() return popup.pinned end,
  }
end

--- Add a context provider. Called on each update to enrich the context
--- table that gets passed to each popup's `show` condition.
---@param fn fun(ctx: table)
function M.add_context_provider(fn)
  table.insert(M._context_providers, fn)
end

--- Watch a reactive signal and trigger popup update when it changes.
--- This ensures popups react to debug state changes (e.g. session termination)
--- even if the user hasn't moved the cursor.
---@param signal table A signal with :use(callback) method (e.g. debugger.focusedUrl)
function M.watch_signal(signal)
  if signal and signal.use then
    local unsub = signal:use(function()
      -- Schedule with minimal delay to batch rapid changes (e.g. stepping)
      M._schedule_update(50)
    end)
    if unsub then
      table.insert(M._state_unsubs, unsub)
    end
  end
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

function M.setup()
  if M._group then return end
  M._group = vim.api.nvim_create_augroup("SmartPopup", { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = M._group,
    callback = function() M._schedule_update(M.SHOW_DELAY) end,
  })

  vim.api.nvim_create_autocmd("WinResized", {
    group = M._group,
    callback = function() M._schedule_update(M.REPOSITION_DELAY) end,
  })

  -- Clean up popup state when its window is closed externally (e.g. :q, <C-w>c)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = M._group,
    callback = function(ev)
      local closed_win = tonumber(ev.match)
      for _, popup in ipairs(M._popups) do
        if popup.winid == closed_win then
          popup.winid = nil
          popup.visible = false
          popup._hide_timer = cancel_timer(popup._hide_timer)
        end
      end
    end,
  })
end

-------------------------------------------------------------------------------
-- Update cycle
-------------------------------------------------------------------------------

function M._schedule_update(delay)
  M._update_timer = cancel_timer(M._update_timer)
  M._update_timer = start_timer(delay, function()
    M._update_timer = nil
    M._do_update()
  end)
end

function M._is_popup_window(winid)
  for _, popup in ipairs(M._popups) do
    if popup.winid == winid then return true end
  end
  return false
end

function M._compute_context()
  local ctx = {}

  local ok = pcall(function()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local cursor = vim.api.nvim_win_get_cursor(win)

    ctx.cursor_row = cursor[1]
    ctx.cursor_col = cursor[2]
    ctx.bufnr = buf
    ctx.winid = win
    ctx.bufname = vim.api.nvim_buf_get_name(buf)
    ctx.editor_width = vim.o.columns
    ctx.editor_height = vim.o.lines - vim.o.cmdheight - 1

    -- Cursor screen position (relative to editor top-left)
    local win_pos = vim.api.nvim_win_get_position(win)
    local win_top = vim.fn.line("w0", win)
    ctx.screen_row = win_pos[1] + (cursor[1] - win_top)
    ctx.screen_col = win_pos[2] + cursor[2]
    ctx.cursor_on_left = ctx.screen_col < (ctx.editor_width / 2)
  end)

  if not ok then return nil end

  -- Run registered context providers (debug layer injects frame proximity etc.)
  for _, provider in ipairs(M._context_providers) do
    pcall(provider, ctx)
  end

  return ctx
end

function M._do_update()
  -- Skip if current window is a managed popup (user is interacting with it)
  local ok, current_win = pcall(vim.api.nvim_get_current_win)
  if not ok then return end
  if M._is_popup_window(current_win) then return end

  local ctx = M._compute_context()
  if not ctx then return end

  -- Skip if cursor is in a dap:// buffer (e.g. console, tree opened via detour)
  if ctx.bufname and ctx.bufname:match("^dap://") then return end

  for _, popup in ipairs(M._popups) do
    local should_show = popup.pinned or (popup.show and popup.show(ctx))

    if should_show then
      -- Cancel pending hide
      popup._hide_timer = cancel_timer(popup._hide_timer)
      if not popup.visible then
        M._open_popup(popup, ctx)
      end
    else
      if popup.visible and not popup._hide_timer then
        -- Hysteresis: delay before hiding
        popup._hide_timer = start_timer(M.HIDE_DELAY, function()
          popup._hide_timer = nil
          -- Re-check condition before actually hiding
          -- (e.g., thread may have stopped again between steps)
          local recheck = M._compute_context()
          if recheck then
            local still_want = popup.pinned or (popup.show and popup.show(recheck))
            if still_want then return end
          end
          M._close_popup(popup)
        end)
      end
    end
  end

  -- Reposition all visible popups
  M._reposition(ctx)
end

-------------------------------------------------------------------------------
-- Window lifecycle
-------------------------------------------------------------------------------

function M._open_popup(popup, ctx)
  if popup.visible then return end

  local width = math.floor(ctx.editor_width * popup.width)
  local height = math.floor(ctx.editor_height * popup.height)
  width = math.max(width, 20)
  height = math.max(height, 5)

  -- Reuse buffer if still valid (preserves tree expansion state)
  local needs_content = true
  if popup.bufnr and vim.api.nvim_buf_is_valid(popup.bufnr) then
    needs_content = false
  else
    popup.bufnr = vim.api.nvim_create_buf(false, true)
  end

  local col = ctx.cursor_on_left and (ctx.editor_width - width - 2) or 0

  popup.winid = vim.api.nvim_open_win(popup.bufnr, false, {
    relative = "editor",
    row = 0,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = popup.border,
    title = popup.title ~= "" and popup.title or nil,
    title_pos = popup.title ~= "" and "center" or nil,
    focusable = true,
    zindex = 45, -- below detour (50) and other high-priority floats
  })

  if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
    vim.wo[popup.winid].cursorline = true
    vim.wo[popup.winid].wrap = false
    vim.wo[popup.winid].number = false
    vim.wo[popup.winid].relativenumber = false
    vim.wo[popup.winid].signcolumn = "no"
    vim.wo[popup.winid].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  end

  -- Load content URI into the popup window
  if needs_content and popup.content then
    local prev_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(popup.winid)
    local uri = type(popup.content) == "function" and popup.content() or popup.content
    if uri then
      vim.cmd("edit " .. vim.fn.fnameescape(uri))
      -- :edit via BufReadCmd may create a new buffer; track it
      popup.bufnr = vim.api.nvim_win_get_buf(popup.winid)
    end
    vim.api.nvim_set_current_win(prev_win)
  end

  popup.visible = true
end

function M._close_popup(popup)
  if not popup.visible then return end
  popup._hide_timer = cancel_timer(popup._hide_timer)

  if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
    pcall(vim.api.nvim_win_close, popup.winid, true)
  end
  popup.winid = nil
  popup.visible = false

  -- Keep buffer alive — tree_buffer subscriptions persist and re-render
  -- when the buffer is shown again in a new window, preserving expansion state.
  -- Buffers are only deleted on full cleanup().
end

-------------------------------------------------------------------------------
-- Repositioning: stack visible popups on the opposite side of the cursor
-------------------------------------------------------------------------------

function M._reposition(ctx)
  local visible = {}
  for _, popup in ipairs(M._popups) do
    if popup.visible and popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      table.insert(visible, popup)
    end
  end

  if #visible == 0 then return end

  local editor_w = ctx.editor_width
  local editor_h = ctx.editor_height

  -- Total height weight for proportional sizing
  local total_weight = 0
  for _, popup in ipairs(visible) do
    total_weight = total_weight + popup.height
  end

  -- Available height: full editor minus gaps between popups (for borders)
  local gaps = math.max(0, #visible - 1) * 2 -- 2 rows per gap (bottom border + top border)
  local available_h = editor_h - gaps

  -- Stack vertically on the opposite side of cursor
  local current_row = 0

  for i, popup in ipairs(visible) do
    local w = math.floor(editor_w * popup.width)
    local h = math.floor(available_h * (popup.height / total_weight))
    w = math.max(w, 20)
    h = math.max(h, 5)

    -- Place on opposite side of cursor
    local col = ctx.cursor_on_left and (editor_w - w - 2) or 0

    pcall(vim.api.nvim_win_set_config, popup.winid, {
      relative = "editor",
      row = current_row,
      col = col,
      width = w,
      height = h,
    })

    current_row = current_row + h + 2 -- +2 for top+bottom borders
  end
end

-------------------------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------------------------

function M.cleanup()
  M._update_timer = cancel_timer(M._update_timer)
  -- Unsubscribe from reactive signals
  for _, unsub in ipairs(M._state_unsubs) do
    pcall(unsub)
  end
  M._state_unsubs = {}
  for _, popup in ipairs(M._popups) do
    popup._hide_timer = cancel_timer(popup._hide_timer)
    M._close_popup(popup)
    -- On full cleanup, delete buffers too
    if popup.bufnr and vim.api.nvim_buf_is_valid(popup.bufnr) then
      pcall(vim.api.nvim_buf_delete, popup.bufnr, { force = true })
    end
    popup.bufnr = nil
  end
  M._popups = {}
  M._context_providers = {}
  if M._group then
    pcall(vim.api.nvim_del_augroup_by_id, M._group)
    M._group = nil
  end
end

return M
