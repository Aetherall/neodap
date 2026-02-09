-- Builtin backend using core process/session modules
-- Provides process management for DAP adapters without external dependencies.

local log = require("neodap.logger")
local process = require("neodap.process")
local session = require("neodap.session")

---@type neodap.TaskBackend
local M = {}

M.name = "builtin"

-- Task ID counter
local task_id_counter = 0

local function next_task_id()
  task_id_counter = task_id_counter + 1
  return task_id_counter
end

---Spawn a process with stdio communication
---@param opts neodap.SpawnOpts
---@return neodap.ProcessHandle
function M.spawn(opts)
  local handle = process.spawn({
    command = opts.command,
    args = opts.args,
    cwd = opts.cwd,
    env = opts.env,
  })
  handle.task_id = next_task_id()
  log:info("Adapter spawned: " .. opts.command)
  return handle
end

---Connect to create a session
---@param opts neodap.ConnectOpts
---@return neodap.ProcessHandle
function M.connect(opts)
  local host = opts.host or "127.0.0.1"
  local handle = session.connect({
    process = opts.process,
    host = host,
    port = opts.port,
    retries = opts.retries,
    retry_delay = opts.retry_delay,
    timeout = opts.timeout,
    on_connect = opts.on_connect,
  })
  if handle then
    handle.task_id = next_task_id()
    log:info("Connected to adapter: " .. host .. ":" .. opts.port)
    -- Register on_close callback for cleanup (e.g., kill server process)
    if opts.on_close then
      handle.on_exit(function()
        opts.on_close()
      end)
    end
  end
  return handle
end

-- Pool of terminal buffers for reuse (similar to nvim-dap)
local terminal_pool = {}

local function acquire_terminal_buffer(title)
  -- Try to reuse an existing buffer from the pool
  for bufnr, available in pairs(terminal_pool) do
    if available and vim.api.nvim_buf_is_valid(bufnr) then
      terminal_pool[bufnr] = false
      -- Terminal buffers have modifiable=false, need to enable before clearing
      vim.bo[bufnr].modifiable = true
      -- Clear buffer content and reset modified state for reuse
      -- This is required because jobstart with term=true needs an unmodified buffer
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      vim.bo[bufnr].modified = false
      return bufnr
    end
  end

  -- Create a new terminal buffer (hidden - no window)
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Configure buffer to persist when window is closed
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].buflisted = false  -- Don't show in buffer list

  terminal_pool[bufnr] = false
  return bufnr
end

local function release_terminal_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    terminal_pool[bufnr] = true
  end
end

---Run a command in a terminal
---@param opts neodap.RunInTerminalOpts
---@return neodap.TaskHandle
function M.run_in_terminal(opts)
  local task_id = next_task_id()
  local exit_callbacks = {}
  local exited = false
  local jobid = nil
  local bufnr = nil

  -- Create terminal buffer
  local title = opts.title or (opts.args and opts.args[1]) or "dap-terminal"
  bufnr = acquire_terminal_buffer(title)

  -- Run command in terminal buffer
  vim.api.nvim_buf_call(bufnr, function()
    local termopen_fn = vim.fn.has("nvim-0.11") == 1 and vim.fn.jobstart or vim.fn.termopen
    local term_opts = {
      env = opts.env and next(opts.env) and opts.env or vim.empty_dict(),
      cwd = (opts.cwd and opts.cwd ~= "") and opts.cwd or nil,
      on_exit = function(_, code)
        if not exited then
          exited = true
          release_terminal_buffer(bufnr)
          vim.schedule(function()
            for _, cb in ipairs(exit_callbacks) do
              cb(code or -1)
            end
          end)
        end
      end,
    }
    -- nvim 0.11+ needs term=true for jobstart to create terminal
    if vim.fn.has("nvim-0.11") == 1 then
      term_opts.term = true
    end
    jobid = termopen_fn(opts.args, term_opts)
  end)

  -- Set buffer name
  local buf_name = "[dap-terminal] " .. title
  pcall(vim.api.nvim_buf_set_name, bufnr, buf_name)

  -- Get pid from job
  local pid = jobid and vim.fn.jobpid(jobid)

  log:info("Terminal task started: " .. title)

  return {
    task_id = task_id,
    pid = pid,
    bufnr = bufnr,
    on_exit = function(cb)
      if exited then
        vim.schedule(function() cb(-1) end)
      else
        table.insert(exit_callbacks, cb)
      end
    end,
    kill = function()
      if jobid then
        pcall(vim.fn.jobstop, jobid)
      end
    end,
  }
end

return M
