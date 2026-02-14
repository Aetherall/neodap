-- Shared edit buffer utilities for variable_edit and expression_edit
--
-- Provides the common patterns: virtual text indicator, keymaps,
-- dirty tracking, and async submit with status feedback.

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local a = require("neodap.async")

local M = {}

---Build status virtual text segments
---@param status? string "modified"|"saved"|"error:..."|nil
---@return {[1]: string, [2]: string}[]
local function status_segments(status)
  if not status then return {} end
  if status == "modified" then
    return { { " [modified]", "DiffChange" } }
  elseif status == "saved" then
    return { { " [saved]", "DiffAdd" } }
  elseif status:match("^error:") then
    local err_msg = status:gsub("^error:", "")
    return { { " [" .. err_msg .. "]", "ErrorMsg" } }
  end
  return {}
end

---Update virtual text indicator on an edit buffer
---@param bufnr number
---@param ns_id number Namespace ID for extmarks
---@param debugger table Debugger entity (for render_text)
---@param entity table? Variable entity (or nil)
---@param status? string "modified"|"saved"|"error:..."|nil
function M.update_indicator(bufnr, ns_id, debugger, entity, status)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local info
  local info_hl = "Comment"
  if entity then
    info = debugger:render_text(entity, { { "title", prefix = " " }, { "type", prefix = ": " } })
  else
    info = " No variable"
    info_hl = "WarningMsg"
  end

  local virt_text = { { info, info_hl } }
  for _, seg in ipairs(status_segments(status)) do
    table.insert(virt_text, seg)
  end

  vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, 0, {
    virt_text = virt_text,
    virt_text_pos = "right_align",
  })
end

---Setup standard edit buffer keymaps: <CR>, <C-s> → submit, u → reset, q → close
---@param bufnr number
---@param opts? { desc_prefix?: string, escape_insert?: boolean }
function M.setup_keymaps(bufnr, opts)
  opts = opts or {}
  local desc_prefix = opts.desc_prefix or "Submit value"

  -- Submit on Enter (normal mode)
  vim.keymap.set("n", "<CR>", function()
    entity_buffer.submit(bufnr)
  end, { buffer = bufnr, desc = desc_prefix })

  -- Submit on Ctrl-S (both modes)
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    if opts.escape_insert then
      vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
    end
    entity_buffer.submit(bufnr)
  end, { buffer = bufnr, desc = desc_prefix })

  -- Reset to original value
  vim.keymap.set("n", "u", function()
    if entity_buffer.is_dirty(bufnr) then
      entity_buffer.reset(bufnr)
    else
      vim.cmd("normal! u")
    end
  end, { buffer = bufnr, desc = "Reset to original value" })

  -- Close without saving
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end, { buffer = bufnr, desc = "Close without saving" })
end

---Setup dirty tracking with TextChanged autocmd that updates the indicator
---@param bufnr number
---@param ns_id number
---@param debugger table
---@param get_entity fun(): table? Function that returns the current entity
function M.setup_dirty_tracking(bufnr, ns_id, debugger, get_entity)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    callback = function()
      local entity = get_entity()
      local status = entity_buffer.is_dirty(bufnr) and "modified" or nil
      M.update_indicator(bufnr, ns_id, debugger, entity, status)
    end,
  })
end

---Run an async submit operation with saved/error indicator feedback
---@param bufnr number
---@param ns_id number
---@param debugger table
---@param fn fun() Async function to run (should call setValue etc.)
---@param get_entity fun(): table? Function that returns the current entity
function M.async_submit(bufnr, ns_id, debugger, fn, get_entity)
  a.run(function()
    fn()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      local entity = get_entity()
      M.update_indicator(bufnr, ns_id, debugger, entity, "saved")
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          M.update_indicator(bufnr, ns_id, debugger, get_entity(), nil)
        end
      end, 2000)
    end)
  end, function(err)
    if err then
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        M.update_indicator(bufnr, ns_id, debugger, get_entity(), "error:" .. tostring(err))
      end)
    end
  end)
end

---Position cursor at end of buffer content and optionally enter insert mode
---@param bufnr number
---@param opts? { insert?: boolean }
function M.cursor_to_end(bufnr, opts)
  opts = opts or {}
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local last_line = #lines
    local last_col = #lines[last_line]
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      vim.api.nvim_win_set_cursor(win, { last_line, last_col })
    end
    if opts.insert then
      vim.cmd("startinsert!")
    end
  end)
end

return M
