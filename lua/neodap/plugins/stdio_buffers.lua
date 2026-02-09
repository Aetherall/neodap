-- Plugin: Output buffer backed by temp file on disk
-- Output is written to session.logDir/output.log, buffer just views that file.
--
-- The dap://output URI scheme redirects to open the actual file.

local log = require("neodap.logger")

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  local group = vim.api.nvim_create_augroup("neodap-stdio-buffers", { clear = true })

  -- Track file buffers per session for auto-reload
  local session_buffers = {} -- session_id -> bufnr

  ---Get log file path for a session
  ---@param session neodap.entities.Session
  ---@return string|nil path
  local function get_log_path(session)
    local log_dir = session.logDir and session.logDir:get()
    if not log_dir then return nil end
    return log_dir .. "/output.log"
  end

  ---Open the log file buffer for a session
  ---@param session neodap.entities.Session
  ---@param opts? { split?: "horizontal"|"vertical"|"tab" }
  local function open_log(session, opts)
    opts = opts or {}
    local path = get_log_path(session)
    if not path then
      vim.notify("Session has no log directory", vim.log.levels.WARN)
      return
    end

    -- Ensure file exists
    if vim.fn.filereadable(path) == 0 then
      local f = io.open(path, "w")
      if f then f:close() end
    end

    local cmd
    if opts.split == "horizontal" then
      cmd = "split"
    elseif opts.split == "vertical" then
      cmd = "vsplit"
    elseif opts.split == "tab" then
      cmd = "tabedit"
    else
      cmd = "edit"
    end

    vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Configure buffer
    vim.bo[bufnr].filetype = "dap-output"
    vim.bo[bufnr].bufhidden = "hide"

    -- Track buffer for auto-reload
    local session_id = session.sessionId:get()
    session_buffers[session_id] = bufnr

    -- Jump to end of file
    vim.cmd("normal! G")

    return bufnr
  end

  ---Reload log buffer if it exists and is visible
  ---@param session_id string
  local function reload_log_buffer(session_id)
    local bufnr = session_buffers[session_id]
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

    -- Only reload if buffer is displayed in a window
    local wins = vim.fn.win_findbuf(bufnr)
    if #wins == 0 then return end

    -- Reload file content
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        -- Save cursor position
        local cursor_positions = {}
        for _, win in ipairs(wins) do
          cursor_positions[win] = vim.api.nvim_win_get_cursor(win)
        end

        -- Check if cursor was at the end (for auto-scroll)
        local was_at_end = {}
        for _, win in ipairs(wins) do
          local cursor = cursor_positions[win]
          local line_count = vim.api.nvim_buf_line_count(bufnr)
          was_at_end[win] = cursor[1] >= line_count
        end

        -- Reload
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("silent! checktime")
        end)

        -- Restore cursor or scroll to end
        vim.schedule(function()
          for _, win in ipairs(wins) do
            if vim.api.nvim_win_is_valid(win) then
              if was_at_end[win] then
                -- Auto-scroll to end
                local new_line_count = vim.api.nvim_buf_line_count(bufnr)
                pcall(vim.api.nvim_win_set_cursor, win, { new_line_count, 0 })
              else
                -- Restore previous position
                pcall(vim.api.nvim_win_set_cursor, win, cursor_positions[win])
              end
            end
          end
        end)
      end
    end)
  end

  -- Watch for new outputs and reload buffers
  debugger.sessions:each(function(session)
    local session_id = session.sessionId:get()

    -- Watch for outputs to trigger reload
    session.outputs:each(function(output)
      reload_log_buffer(session_id)
    end)
  end)

  -- Handle dap://output URI scheme
  -- Redirect to open the actual log file
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "dap://output/*",
    callback = function(ev)
      local uri = ev.file
      local session_id = uri:match("dap://output/session:([^/]+)")
      if not session_id then return end

      -- Find session
      for session in debugger.sessions:iter() do
        if session.sessionId:get() == session_id then
          -- Delete the URI buffer and open the actual file
          vim.api.nvim_buf_delete(ev.buf, { force = true })
          open_log(session)
          return
        end
      end

      -- Session not found
      vim.bo[ev.buf].buftype = "nofile"
      vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, { "-- Session not found: " .. session_id })
    end,
  })

  local api = {}

  ---Open output log for a session
  ---@param session neodap.entities.Session
  ---@param opts? { split?: "horizontal"|"vertical"|"tab" }
  function api.open(session, opts)
    return open_log(session, opts)
  end

  ---Get log file path for a session
  ---@param session neodap.entities.Session
  ---@return string|nil
  function api.get_path(session)
    return get_log_path(session)
  end

  -- Command for focused session
  vim.api.nvim_create_user_command("DapOutput", function()
    local session = debugger.ctx.session:get()
    if not session then
      vim.notify("No focused session", vim.log.levels.WARN)
      return
    end
    api.open(session)
  end, { desc = "Open output log for focused debug session" })

  return api
end
