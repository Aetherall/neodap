-- DAP plugin shared context/state
-- This module holds the mapping between Session entities and DapSession instances

local M = {}

-- Session entity → DapSession instance
M.dap_sessions = setmetatable({}, { __mode = "k" })

-- DapSession → Session entity (reverse lookup)
M.session_entities = setmetatable({}, { __mode = "k" })

-- Track output sequence per session
-- Key: session entity, Value: number
M.output_seqs = setmetatable({}, { __mode = "k" })

-- Session entity → list of TaskHandles from runInTerminal
-- Each session can have multiple terminal tasks (one per runInTerminal call)
M.terminal_tasks = setmetatable({}, { __mode = "k" })

-- Set of DapSession instances currently being terminated (not disconnected)
-- Used to distinguish terminate vs disconnect in the "closing" event handler
M.terminating_sessions = setmetatable({}, { __mode = "k" })

-- Session entity → supervisor handle (ConfigHandle or CompoundHandle)
-- Used to stop the supervisor process group when the session closes
M.supervisor_handles = setmetatable({}, { __mode = "k" })

-- Global output sequence counter (across all sessions for ordering)
M.global_output_seq = 0

---Get next global output sequence number
---@return number
function M.next_global_seq()
  M.global_output_seq = M.global_output_seq + 1
  return M.global_output_seq
end

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

---Register a session mapping
---@param session neodap.entities.Session
---@param dap_session DapSession
function M.register_session(session, dap_session)
  M.dap_sessions[session] = dap_session
  M.session_entities[dap_session] = session
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

---Kill all terminal tasks for a session
---@param session neodap.entities.Session
function M.kill_terminal_tasks(session)
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
