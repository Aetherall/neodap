-- Plugin: Highlight frames in source buffers
-- Green for context frame
-- Blues for context session frames (brighter = top frame)
-- Purples for other session frames (almost pink = top frame)
--
-- Pure reactive chaining: sources:where():each() -> source:onFrame()

local neostate = require("neostate")

---@class FrameHighlightsConfig
---@field priority? number Extmark priority (default: 15)
---@field namespace? string Namespace name (default: "dap_frame_highlights")
---@field max_index? number Max stack index to differentiate colors (default: 4)

local default_config = {
  priority = 15,
  namespace = "dap_frame_highlights",
  max_index = 4,
}

local blues = {
  [0] = { fg = "#89dceb", bg = "#1e4a5c" },
  [1] = { fg = "#74c7ec", bg = "#1a3f4d" },
  [2] = { fg = "#5fb3d9", bg = "#16343f" },
  [3] = { fg = "#4a9fc6", bg = "#122931" },
  [4] = { fg = "#358bb3", bg = "#0e1e23" },
}

local purples = {
  [0] = { fg = "#f5c2e7", bg = "#4a2040" },
  [1] = { fg = "#dda8d3", bg = "#3d1a36" },
  [2] = { fg = "#c58ebf", bg = "#30142c" },
  [3] = { fg = "#ad74ab", bg = "#230e22" },
  [4] = { fg = "#955a97", bg = "#160818" },
}

local context_green = { fg = "#a6e3a1", bg = "#1e3a1e" }

---@param debugger Debugger
---@param config? FrameHighlightsConfig
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local ns = vim.api.nvim_create_namespace(config.namespace)

  -- Define highlight groups
  vim.api.nvim_set_hl(0, "DapFrameContext", { fg = context_green.fg, bg = context_green.bg, default = true })
  for i = 0, config.max_index do
    local blue = blues[i] or blues[config.max_index]
    local purple = purples[i] or purples[config.max_index]
    vim.api.nvim_set_hl(0, "DapFrameSessionTop" .. i, { fg = blue.fg, bg = blue.bg, default = true })
    vim.api.nvim_set_hl(0, "DapFrameOther" .. i, { fg = purple.fg, bg = purple.bg, default = true })
  end

  local function get_hl_group(frame, context_frame, context_session)
    if context_frame and frame.uri == context_frame.uri then
      return "DapFrameContext"
    end
    local index = math.min(frame.index:get(), config.max_index)
    if context_session and frame.stack.thread.session.id == context_session.id then
      return "DapFrameSessionTop" .. index
    end
    return "DapFrameOther" .. index
  end

  -- Buffer contexts for cleanup
  local buffer_contexts = {} -- bufnr -> Disposable

  ---Setup reactive highlights for a buffer
  ---@param bufnr number
  local function setup_buffer(bufnr)
    if buffer_contexts[bufnr] then return end

    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    if buf_name == "" then return end

    -- Get correlation key for this buffer
    local key = buf_name:match("dap:source:(.+)$") or buf_name

    -- Create context for this buffer
    local ctx = neostate.Disposable({}, nil, "FrameHL:" .. bufnr)
    ctx:set_parent(debugger)
    buffer_contexts[bufnr] = ctx

    -- Extmarks in closure
    local extmarks = {}

    local function set_extmark(frame)
      if not vim.api.nvim_buf_is_valid(bufnr) or not frame:is_current() then return end

      local buf_ctx = debugger:context(bufnr)
      local frame_uri = buf_ctx.frame_uri:get()
      local context_frame = frame_uri and debugger:resolve_one(frame_uri) or nil
      local context_session = context_frame and context_frame.stack.thread.session or nil
      local hl_group = get_hl_group(frame, context_frame, context_session)

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      local line_idx = math.max(0, math.min(frame.line - 1, line_count - 1))

      -- Get start column (DAP is 1-indexed, nvim extmarks are 0-indexed)
      local start_col = math.max(0, (frame.column or 1) - 1)

      -- Get end position - use endLine/endColumn if available, otherwise end of line
      local end_line_idx = line_idx
      local end_col = nil

      if frame.endLine and frame.endColumn then
        end_line_idx = math.max(0, math.min(frame.endLine - 1, line_count - 1))
        end_col = frame.endColumn  -- DAP endColumn is exclusive, same as nvim
      else
        -- Highlight to end of line
        local line_text = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)[1] or ""
        end_col = #line_text
      end

      if extmarks[frame.uri] then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, extmarks[frame.uri])
      end

      extmarks[frame.uri] = vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, start_col, {
        end_row = end_line_idx,
        end_col = end_col,
        hl_group = hl_group,
        priority = config.priority,
      })
    end

    local function remove_extmark(frame)
      if extmarks[frame.uri] then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, extmarks[frame.uri])
        extmarks[frame.uri] = nil
      end
    end

    -- Pure reactive chain: when source appears -> watch its frames
    ctx:run(function()
      local view = debugger:view("source"):where("by_correlation_key", key)
      view:set_parent(ctx)
      view:each(function(source)
        -- Watch context changes to update highlights (uses buffer context, falls back to global)
        debugger:context(bufnr).frame_uri:use(function()
          vim.schedule(function()
            for frame in source:frames():iter() do
              if frame:is_current() then set_extmark(frame) end
            end
          end)
        end)

        -- Watch frames at this source
        return source:onFrame(function(frame)
          vim.schedule(function() set_extmark(frame) end)

          frame.index:watch(function()
            vim.schedule(function() set_extmark(frame) end)
          end)

          frame:onExpired(function()
            vim.schedule(function() remove_extmark(frame) end)
          end)
        end)
      end)
    end)

    ctx:on_dispose(function()
      for _, id in pairs(extmarks) do
        pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, id)
      end
      buffer_contexts[bufnr] = nil
    end)
  end

  -- Autocmds
  local augroup = vim.api.nvim_create_augroup("DapFrameHighlights", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "BufReadPost" }, {
    group = augroup,
    callback = function(ev)
      if vim.api.nvim_buf_is_valid(ev.buf) then
        setup_buffer(ev.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    callback = function(ev)
      if buffer_contexts[ev.buf] then
        buffer_contexts[ev.buf]:dispose()
      end
    end,
  })

  -- Setup open buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      setup_buffer(bufnr)
    end
  end

  debugger:on_dispose(function()
    pcall(vim.api.nvim_del_augroup_by_name, "DapFrameHighlights")
  end)

  return function()
    for _, ctx in pairs(buffer_contexts) do
      ctx:dispose()
    end
    pcall(vim.api.nvim_del_augroup_by_name, "DapFrameHighlights")
  end
end
