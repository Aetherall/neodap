-- view_buffer: shared lifecycle for graph-view-backed buffers
--
-- Handles the mechanical parts that tree_buffer and console_buffer duplicate:
--   - View subscription (enter/leave/change → debounced render)
--   - Viewport tracking (CursorMoved → scroll, WinResized → resize)
--   - Window options (wrap, number, signcolumn, cursorline)
--   - Debounced render timer with cleanup
--
-- Usage:
--   local vb = view_buffer.create({
--     bufnr = bufnr,
--     view = graph:view(query, { limit = limit }),
--     group = augroup,
--     ns_id = vim.api.nvim_create_namespace("dap-tree-" .. bufnr),
--     render = function(state) ... end,
--     on_enter = function(entity) ... end,   -- optional: called on view enter
--     on_cursor_moved = function(state) ... end, -- optional: extra CursorMoved logic
--     on_viewport_change = function(state) ... end, -- optional: pre-render viewport hook
--   })
--
--   vb.state    -- { view, ns_id, offset, viewport_limit, ... }
--   vb.render() -- force immediate render
--   vb.cleanup()

local M = {}

--- Set standard window options for a view buffer.
---@param win number Window id
function M.set_win_options(win)
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = true
end

--- Render items into buffer lines with highlight extmarks.
--- Handles the placeholder-lines → render → set-lines → apply-extmarks pipeline.
---@param bufnr number Buffer number
---@param ns_id number Namespace id for extmarks
---@param items table[] Processed items (from view:items())
---@param offset number Current scroll offset
---@param total number Total visible item count from view
---@param limit number Viewport limit
---@param render_item fun(item: table, line_idx: number): string, table[], number?, table[]? Returns (text, highlights, cursor_col?, right_virt?)
---@return table[] items The same items (for caller to store)
function M.render_lines(bufnr, ns_id, items, offset, total, limit, render_item)
  local lines_count = math.max(1, total >= limit and total or (offset + #items))

  vim.bo[bufnr].modifiable = true
  local placeholders = {}
  for _ = 1, lines_count do
    placeholders[#placeholders + 1] = ""
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, placeholders)

  local all_highlights = {}
  local all_right_virt = {}
  for i, item in ipairs(items) do
    local line_idx = offset + i - 1
    local text, hls, _, right_virt = render_item(item, line_idx)
    vim.api.nvim_buf_set_lines(bufnr, line_idx, line_idx + 1, false, { text })
    for _, hl in ipairs(hls) do
      all_highlights[#all_highlights + 1] = hl
    end
    if right_virt then
      all_right_virt[#all_right_virt + 1] = { line = line_idx, chunks = right_virt }
    end
  end
  vim.bo[bufnr].modifiable = false

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, offset, offset + #items)
  for _, hl in ipairs(all_highlights) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, hl.line, hl.col_start, {
      end_col = hl.col_end ~= -1 and hl.col_end or nil,
      hl_group = hl.group,
      hl_eol = hl.col_end == -1,
    })
  end

  -- Apply right-aligned virtual text extmarks
  for _, rv in ipairs(all_right_virt) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, rv.line, 0, {
      virt_text = rv.chunks,
      virt_text_pos = "right_align",
    })
  end

  return items
end

--- Get the item under the cursor from a flat items list.
---@param bufnr number Buffer number
---@param items table[] Items array (1-indexed, matching rendered lines at offset)
---@param offset number Current scroll offset
---@return table|nil item
function M.get_cursor_item(bufnr, items, offset)
  if not items then return nil end
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then return nil end
  local cursor = vim.api.nvim_win_get_cursor(win)[1] - 1
  local idx = cursor - offset + 1
  return (idx >= 1 and idx <= #items) and items[idx] or nil
end

--- Create a managed view buffer with lifecycle, viewport tracking, and debounced rendering.
---@param opts table Options
---@return table handle { state, render, cleanup }
function M.create(opts)
  local bufnr = opts.bufnr
  local view = opts.view
  local group = opts.group
  local render_fn = opts.render
  local on_enter = opts.on_enter
  local on_cursor_moved = opts.on_cursor_moved
  local on_viewport_change = opts.on_viewport_change

  local win = vim.fn.bufwinid(bufnr)
  local limit = (win ~= -1) and vim.api.nvim_win_get_height(win) or 50

  -- Window options (now + on future BufWinEnter)
  if win ~= -1 then M.set_win_options(win) end
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = bufnr,
    group = group,
    callback = function()
      local w = vim.fn.bufwinid(bufnr)
      if w ~= -1 then M.set_win_options(w) end
    end,
  })

  local state = {
    view = view,
    ns_id = opts.ns_id or vim.api.nvim_create_namespace("dap-view-" .. bufnr),
    offset = 0,
    viewport_limit = limit,
    subscriptions = {},
  }

  -- Debounced render (16ms ≈ 60fps)
  local render_timer = nil
  local function cancel_render_timer()
    if render_timer then
      render_timer:stop()
      render_timer:close()
      render_timer = nil
    end
  end

  local function schedule_render()
    if render_timer then return end
    render_timer = vim.defer_fn(function()
      render_timer = nil
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      if on_viewport_change then on_viewport_change(state) end
      render_fn(state)
    end, 16)
  end

  -- View subscriptions
  local subs = state.subscriptions
  subs[#subs + 1] = view:on("enter", function(entity)
    if on_enter then on_enter(entity) end
    schedule_render()
  end)
  subs[#subs + 1] = view:on("leave", schedule_render)
  subs[#subs + 1] = view:on("change", schedule_render)

  -- Viewport tracking
  local function update_viewport()
    local w = vim.fn.bufwinid(bufnr)
    if w == -1 then return end
    local cursor = vim.api.nvim_win_get_cursor(w)[1] - 1
    local h = vim.api.nvim_win_get_height(w)
    local off = state.offset
    local top = vim.fn.line("w0", w) - 1
    if cursor < off or cursor >= off + h or top ~= off then
      state.offset = top ~= off and top or math.max(0, cursor - math.floor(h / 2))
      state.view:scroll(state.offset)
      render_fn(state)
    end
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = bufnr,
    group = group,
    callback = function()
      update_viewport()
      if on_cursor_moved then on_cursor_moved(state) end
    end,
  })

  vim.api.nvim_create_autocmd("WinResized", {
    buffer = bufnr,
    group = group,
    callback = function()
      local w = vim.fn.bufwinid(bufnr)
      if w == -1 then return end
      local h = vim.api.nvim_win_get_height(w)
      if h ~= state.viewport_limit then
        state.viewport_limit = h
        if state.view.set_limit then
          state.view:set_limit(h)
        end
        render_fn(state)
      end
    end,
  })

  local function cleanup()
    cancel_render_timer()
    for _, unsub in ipairs(subs) do pcall(unsub) end
    if view.destroy then pcall(view.destroy, view) end
    if view.off then pcall(view.off, view) end
  end

  return {
    state = state,
    render = function() render_fn(state) end,
    schedule_render = schedule_render,
    cleanup = cleanup,
  }
end

return M
