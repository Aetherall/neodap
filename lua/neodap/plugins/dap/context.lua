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

return M
