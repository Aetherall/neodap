-- Plugin: Highlight frames in source buffers
-- Green for context frame, blues for session frames, purples for other frames

local navigate = require("neodap.plugins.utils.navigate")
local cfg = require("neodap.plugins.tree_buffer.config")
local scoped = require("neodap.scoped")

local default_config = {
  priority = 15,
  namespace = "neodap_frame_highlights",
  max_index = 4,
}

local blues = cfg.frame_colors.blues
local purples = cfg.frame_colors.purples
local context_green = cfg.frame_colors.context

local function define_highlights(max_index)
  vim.api.nvim_set_hl(0, "DapFrameContext", { fg = context_green.fg, bg = context_green.bg, default = true })
  vim.api.nvim_set_hl(0, "DapCurrentFrameSign", { fg = "#f9e2af", default = true })
  for i = 0, max_index do
    local blue = blues[i] or blues[max_index]
    local purple = purples[i] or purples[max_index]
    vim.api.nvim_set_hl(0, "DapFrameSessionTop" .. i, { fg = blue.fg, bg = blue.bg, default = true })
    vim.api.nvim_set_hl(0, "DapFrameOther" .. i, { fg = purple.fg, bg = purple.bg, default = true })
  end
end

---@param debugger neodap.entities.Debugger
---@param config? table
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local ns = vim.api.nvim_create_namespace(config.namespace)
  local plugin_scope = scoped.current()
  local augroup = vim.api.nvim_create_augroup("NeodapFrameHighlights", { clear = true })

  define_highlights(config.max_index)

  local function get_hl_group(frame, context_frame, context_session)
    if context_frame and frame:id() == context_frame:id() then
      return "DapFrameContext"
    end
    local index = math.min(frame.index:get() or 0, config.max_index)
    local stack = frame.stack:get()
    local thread = stack and stack.thread:get()
    local session = thread and thread.session:get()
    if context_session and session and session.uri:get() == context_session.uri:get() then
      return "DapFrameSessionTop" .. index
    end
    return "DapFrameOther" .. index
  end

  local function setup_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    if vim.b[bufnr].neodap_frame_highlights then return end

    local buf_path = vim.api.nvim_buf_get_name(bufnr)
    if buf_path == "" then return end

    -- Find source matching this buffer
    local source
    for s in debugger.sources:iter() do
      if s:bufferUri() == buf_path then source = s; break end
    end
    if not source then return end

    vim.b[bufnr].neodap_frame_highlights = true
    local buffer_scope = scoped.createScope(plugin_scope)

    buffer_scope:onCleanup(function()
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
    end)

    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr, once = true,
      callback = function() buffer_scope:cancel() end,
    })

    scoped.withScope(buffer_scope, function()
      source.activeFrames:each(function(frame)
        local extmark_id = nil

        local function update()
          if not vim.api.nvim_buf_is_valid(bufnr) then return end

          local line = frame.line:get()
          if not line then return end

          local context_frame = debugger.ctx.frame:get()
          local context_session = debugger.ctx.session:get()
          local line_count = vim.api.nvim_buf_line_count(bufnr)
          local line_idx = math.max(0, math.min(line - 1, line_count - 1))
          local line_text = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)[1] or ""
          local end_col = #line_text
          local start_col = math.max(0, math.min((frame.column:get() or 1) - 1, end_col))

          if extmark_id then
            pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, extmark_id)
          end

          local opts = {
            end_col = end_col,
            hl_group = get_hl_group(frame, context_frame, context_session),
            priority = config.priority,
          }
          if frame.index:get() == 0 then
            opts.sign_text = "→"
            opts.sign_hl_group = "DapCurrentFrameSign"
          end

          extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, start_col, opts)
        end

        vim.schedule(update)

        local unsub = debugger.focusedUrl:use(function()
          vim.schedule(update)
        end)

        return function()
          unsub()
          if extmark_id then
            pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, extmark_id)
          end
        end
      end)
    end)
  end

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "BufReadPost" }, {
    group = augroup,
    callback = function(ev) setup_buffer(ev.buf) end,
  })

  debugger.sources:each(function(source)
    local uri = source:bufferUri()
    local bufnr = uri and navigate.get_buffer_for_path(uri)
    if bufnr then vim.schedule(function() setup_buffer(bufnr) end) end

    source.path:use(function()
      local u = source:bufferUri()
      local buf = u and navigate.get_buffer_for_path(u)
      if buf then vim.schedule(function() setup_buffer(buf) end) end
    end)
  end)

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      setup_buffer(bufnr)
    end
  end

  return {}
end
