-- DAP plugin shared context/state
-- This module holds the mapping between Session entities and DapSession instances

local M = {}

-- Session entity → DapSession instance
M.dap_sessions = setmetatable({}, { __mode = "k" })

-- DapSession → Session entity (reverse lookup)
M.session_entities = setmetatable({}, { __mode = "k" })

-- Session entity → list of TaskHandles from runInTerminal
-- Each session can have multiple terminal tasks (one per runInTerminal call)
M.terminal_tasks = setmetatable({}, { __mode = "k" })

-- Set of DapSession instances currently being terminated (not disconnected)
-- Used to distinguish terminate vs disconnect in the "closing" event handler
M.terminating_sessions = setmetatable({}, { __mode = "k" })

-- Session entity → supervisor handle (ConfigHandle or CompoundHandle)
-- Used to stop the supervisor process group when the session closes
M.supervisor_handles = setmetatable({}, { __mode = "k" })

-- Session entity → { output = Output, signature = string } (for repeat collapsing)
-- signature is the normalized text used for fuzzy comparison
M.last_outputs = setmetatable({}, { __mode = "k" })

---Get the DapSession for a Session entity
---@param session neodap.entities.Session
---@return DapSession?
function M.get_dap_session(session)
  return M.dap_sessions[session]
end

---Get the Session entity for a DapSession
---@param dap_session DapSession
---@return neodap.entities.Session?
function M.get_session_entity(dap_session)
  return M.session_entities[dap_session]
end

---Mark a dap_session tree as terminating (not disconnecting)
---This tells the "closing" handler to kill terminal processes.
---@param dap_session DapSession
function M.mark_terminating(dap_session)
  M.terminating_sessions[dap_session] = true
  for _, child in ipairs(dap_session.children or {}) do
    M.mark_terminating(child)
  end
end

---Store a terminal task handle for a session
---@param session neodap.entities.Session
---@param task neodap.TaskHandle
function M.add_terminal_task(session, task)
  if not M.terminal_tasks[session] then
    M.terminal_tasks[session] = {}
  end
  table.insert(M.terminal_tasks[session], task)
end

---Wipe terminal buffers for a session (defensive cleanup).
---Deletes terminal buffers before their processes die to prevent a Neovim nightly
---crash in marktree_lookup during terminal_close → extmark_del_id.
---@param session neodap.entities.Session
function M.wipe_terminal_buffers(session)
  local tasks = M.terminal_tasks[session]
  if not tasks then return end
  for _, task in ipairs(tasks) do
    if task.bufnr and vim.api.nvim_buf_is_valid(task.bufnr) then
      pcall(vim.api.nvim_buf_delete, task.bufnr, { force = true })
    end
  end
end

---Kill all terminal tasks for a session
---@param session neodap.entities.Session
function M.kill_terminal_tasks(session)
  -- Wipe terminal buffers first to prevent Neovim crash in marktree_lookup
  -- during terminal_close → extmark_del_id (nightly bug in terminal cleanup).
  M.wipe_terminal_buffers(session)
  local tasks = M.terminal_tasks[session]
  if not tasks then
    return
  end
  for _, task in ipairs(tasks) do
    task.kill()
  end
  M.terminal_tasks[session] = nil
end

---Store a supervisor handle for a session
---@param session neodap.entities.Session
---@param handle neodap.supervisor.ConfigHandle
function M.set_supervisor_handle(session, handle)
  M.supervisor_handles[session] = handle
end

---Stop the supervisor for a session (kills the process group)
---@param session neodap.entities.Session
function M.stop_supervisor(session)
  local handle = M.supervisor_handles[session]
  if handle then
    M.supervisor_handles[session] = nil
    handle.stop()
  end
end

return M
