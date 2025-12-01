-- Plugin: Highlight exceptions with red background and virtual text
-- Shows exception message as virtual text when thread stops on exception

local neostate = require("neostate")

---@class ExceptionHighlightConfig
---@field priority? number Extmark priority (default: 20, higher than frame highlights)
---@field namespace? string Namespace name (default: "dap_exception_highlight")

local default_config = {
  priority = 20,
  namespace = "dap_exception_highlight",
}

local exception_red = { fg = "#f38ba8", bg = "#4a1e28" }

---@param debugger Debugger
---@param config? ExceptionHighlightConfig
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local ns = vim.api.nvim_create_namespace(config.namespace)

  -- Define highlight groups
  vim.api.nvim_set_hl(0, "DapException", { fg = exception_red.fg, bg = exception_red.bg, default = true })
  vim.api.nvim_set_hl(0, "DapExceptionText", { fg = exception_red.fg, italic = true, default = true })

  -- Track active exception highlights per thread
  local active_highlights = {} -- thread.global_id -> { bufnr, extmark_id }

  local function clear_highlight(thread_id)
    local highlight = active_highlights[thread_id]
    if highlight then
      pcall(vim.api.nvim_buf_del_extmark, highlight.bufnr, ns, highlight.extmark_id)
      active_highlights[thread_id] = nil
    end
  end

  local function set_exception_highlight(thread, frame, exception_message)
    if not frame or not frame.source then return end

    local path = frame.source.path
    if not path then return end

    -- Find buffer for this file
    local bufnr = vim.fn.bufnr(path)
    if bufnr == -1 then return end
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    -- Clear any existing highlight for this thread
    clear_highlight(thread.global_id)

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local line_idx = math.max(0, math.min(frame.line - 1, line_count - 1))

    -- Get line text for end column
    local line_text = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)[1] or ""
    local start_col = math.max(0, (frame.column or 1) - 1)
    local end_col = #line_text

    -- Format virtual text
    local virt_text = exception_message and { { "  " .. exception_message, "DapExceptionText" } } or nil

    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, start_col, {
      end_col = end_col,
      hl_group = "DapException",
      priority = config.priority,
      virt_text = virt_text,
      virt_text_pos = "eol",
    })

    active_highlights[thread.global_id] = {
      bufnr = bufnr,
      extmark_id = extmark_id,
    }
  end

  -- Subscribe to thread events
  local unsubscribe = debugger:onThread(function(thread)
    -- When thread stops, check if it's an exception
    local stop_cleanup = thread:onStopped(function()
      if not thread:stoppedOnException() then return end

      vim.schedule(function()
        neostate.void(function()
          -- Get stack to find exception location
          local stack = thread:stack()
          if not stack then return end

          local top = stack:top()
          if not top then return end

          -- Fetch exception info
          local info, err = thread:exceptionInfo()
          local message = nil
          if info then
            -- Build message from exception info
            if info.details and info.details.message then
              message = info.details.message
            elseif info.description then
              message = info.description
            elseif info.exceptionId then
              message = info.exceptionId
            end
          end

          set_exception_highlight(thread, top, message)
        end)()
      end)
    end)

    -- Clear highlight when thread resumes
    local resume_cleanup = thread:onResumed(function()
      vim.schedule(function()
        clear_highlight(thread.global_id)
      end)
    end)

    -- Cleanup on thread dispose
    thread:on_dispose(function()
      clear_highlight(thread.global_id)
    end)

    return function()
      stop_cleanup()
      resume_cleanup()
    end
  end)

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    for thread_id in pairs(active_highlights) do
      clear_highlight(thread_id)
    end
  end)

  -- Return manual cleanup function
  return function()
    unsubscribe()
    for thread_id in pairs(active_highlights) do
      clear_highlight(thread_id)
    end
  end
end
