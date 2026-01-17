-- Plugin: Create stdout/stderr buffers for each debug session
-- Each session gets dedicated buffers that receive output in real-time

---@class StdioBuffersConfig
---@field stdout? boolean Create stdout buffer (default: true)
---@field stderr? boolean Create stderr buffer (default: true)
---@field console? boolean Create console/debug output buffer (default: false)
---@field max_lines? number Maximum lines to keep in buffer (default: 10000)

local default_config = {
  stdout = true,
  stderr = true,
  console = false,
  max_lines = 10000,
}

---@param debugger neodap.entities.Debugger
---@param config? StdioBuffersConfig
---@return table api Plugin API
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local api = {}

  -- Track buffers per session: { [session_id] = { stdout = bufnr, stderr = bufnr, ... } }
  local session_buffers = {}

  ---Create a buffer for a specific output category
  ---@param session_id string
  ---@param category string stdout|stderr|console
  ---@return number bufnr
  local function create_buffer(session_id, category)
    local bufname = string.format("dap://%s/%s", category, session_id)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, bufname)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].filetype = "dap-output"
    return bufnr
  end

  ---Append text to a buffer (with line limit)
  ---@param bufnr number
  ---@param text string
  local function append_to_buffer(bufnr, text)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    local lines = vim.split(text, "\n", { plain = true })
    if lines[#lines] == "" then
      table.remove(lines)
    end
    if #lines == 0 then return end

    vim.bo[bufnr].modifiable = true

    -- Check if buffer is empty (single empty line)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local is_empty = line_count == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == ""

    if is_empty then
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, lines)
    else
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
    end

    -- Truncate from start if over limit
    line_count = vim.api.nvim_buf_line_count(bufnr)
    if line_count > config.max_lines then
      local overflow = line_count - config.max_lines
      vim.api.nvim_buf_set_lines(bufnr, 0, overflow, false, {})
    end

    vim.bo[bufnr].modifiable = false
  end

  ---Get or create buffers for a session
  ---@param session neodap.entities.Session
  ---@return table<string, number> buffers
  local function get_session_buffers(session)
    local session_id = session.sessionId:get()
    if session_buffers[session_id] then
      return session_buffers[session_id]
    end

    local buffers = {}
    if config.stdout then
      buffers.stdout = create_buffer(session_id, "stdout")
    end
    if config.stderr then
      buffers.stderr = create_buffer(session_id, "stderr")
    end
    if config.console then
      buffers.console = create_buffer(session_id, "console")
    end

    session_buffers[session_id] = buffers
    return buffers
  end

  -- Subscribe to sessions and their outputs
  debugger.sessions:each(function(session)
    local buffers = get_session_buffers(session)

    -- Subscribe to outputs
    session.outputs:each(function(output)
      local category = output.category:get()
      local text = output.text:get() or ""

      -- Skip telemetry
      if category == "telemetry" then return end

      -- Map category to buffer
      local bufnr = buffers[category]
      if not bufnr then
        -- Default: stdout for unknown categories (except stderr/console)
        if category ~= "stderr" and category ~= "console" then
          bufnr = buffers.stdout
        end
      end

      if bufnr then
        vim.schedule(function()
          append_to_buffer(bufnr, text)
        end)
      end
    end)

    -- Cleanup on session termination
    session.state:use(function(state)
      if state == "terminated" then
        local session_id = session.sessionId:get()
        local bufs = session_buffers[session_id]
        if bufs then
          vim.schedule(function()
            for _, bufnr in pairs(bufs) do
              if vim.api.nvim_buf_is_valid(bufnr) then
                local name = vim.api.nvim_buf_get_name(bufnr)
                vim.api.nvim_buf_set_name(bufnr, name .. " [terminated]")
              end
            end
          end)
        end
      end
    end)
  end)

  ---Get stdout buffer for a session
  ---@param session neodap.entities.Session
  ---@return number|nil bufnr
  function api.stdout(session)
    local session_id = session.sessionId:get()
    local bufs = session_buffers[session_id]
    return bufs and bufs.stdout
  end

  ---Get stderr buffer for a session
  ---@param session neodap.entities.Session
  ---@return number|nil bufnr
  function api.stderr(session)
    local session_id = session.sessionId:get()
    local bufs = session_buffers[session_id]
    return bufs and bufs.stderr
  end

  ---Get console buffer for a session
  ---@param session neodap.entities.Session
  ---@return number|nil bufnr
  function api.console(session)
    local session_id = session.sessionId:get()
    local bufs = session_buffers[session_id]
    return bufs and bufs.console
  end

  ---Get all buffers for a session
  ---@param session neodap.entities.Session
  ---@return table<string, number>|nil buffers
  function api.buffers(session)
    local session_id = session.sessionId:get()
    return session_buffers[session_id]
  end

  ---Open stdout buffer for focused session
  function api.open_stdout()
    local session = debugger.ctx.session:get()
    if not session then
      vim.notify("No focused session", vim.log.levels.WARN)
      return
    end
    local bufnr = api.stdout(session)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.cmd("split")
      vim.api.nvim_set_current_buf(bufnr)
    end
  end

  ---Open stderr buffer for focused session
  function api.open_stderr()
    local session = debugger.ctx.session:get()
    if not session then
      vim.notify("No focused session", vim.log.levels.WARN)
      return
    end
    local bufnr = api.stderr(session)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.cmd("split")
      vim.api.nvim_set_current_buf(bufnr)
    end
  end

  -- Commands
  vim.api.nvim_create_user_command("DapStdout", function()
    api.open_stdout()
  end, { desc = "Open stdout buffer for focused debug session" })

  vim.api.nvim_create_user_command("DapStderr", function()
    api.open_stderr()
  end, { desc = "Open stderr buffer for focused debug session" })

  return api
end
