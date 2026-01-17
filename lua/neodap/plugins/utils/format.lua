-- Shared formatting utilities for entity display
-- Used by command_router, list_cmd, and other plugins that display entities

local M = {}

---Format a breakpoint for display
---@param bp any Breakpoint entity
---@return string text
function M.breakpoint(bp)
  local parts = {}

  if bp:isEnabled() then
    table.insert(parts, "[enabled]")
  else
    table.insert(parts, "[disabled]")
  end

  local condition = bp.condition:get()
  if condition and condition ~= "" then
    table.insert(parts, "if: " .. condition)
  end

  local logMessage = bp.logMessage:get()
  if logMessage and logMessage ~= "" then
    table.insert(parts, "log: " .. logMessage)
  end

  local hitCondition = bp.hitCondition:get()
  if hitCondition and hitCondition ~= "" then
    table.insert(parts, "hit: " .. hitCondition)
  end

  if #parts == 1 then
    table.insert(parts, "breakpoint")
  end

  return table.concat(parts, " ")
end

---Format a frame for display
---@param frame any Frame entity
---@return string text
function M.frame(frame)
  local index = frame.index:get() or 0
  local name = frame.name:get() or "<unknown>"
  return string.format("#%d %s", index, name)
end

---Format a thread for display
---@param thread any Thread entity
---@return string text
function M.thread(thread)
  local id = thread.threadId:get() or 0
  local name = thread.name:get() or "Thread"
  local state = thread.state:get() or "unknown"
  return string.format("%s (id=%d): %s", name, id, state)
end

---Format a session for display
---@param session any Session entity
---@return string text
function M.session(session)
  local name = session.name:get() or "Session"
  local state = session.state:get() or "unknown"
  return string.format("%s: %s", name, state)
end

---Format a variable for display
---@param variable any Variable entity
---@return string text
function M.variable(variable)
  local name = variable.name:get() or "<unnamed>"
  local value = variable.value:get() or ""
  local varType = variable.varType:get()

  if varType and varType ~= "" then
    return string.format("%s: %s = %s", name, varType, value)
  else
    return string.format("%s = %s", name, value)
  end
end

---Format a scope for display
---@param scope any Scope entity
---@return string text
function M.scope(scope)
  return string.format("Scope: %s", scope.name:get() or "Scope")
end

---Format a source for display
---@param source any Source entity
---@return string text
function M.source(source)
  return source.name:get() or source.path:get() or "Source"
end

---Format any entity for display (dispatcher)
---@param entity any Entity
---@return string text
function M.entity(entity)
  local t = entity:type()
  if t == "Breakpoint" then return M.breakpoint(entity)
  elseif t == "Frame" then return M.frame(entity)
  elseif t == "Thread" then return M.thread(entity)
  elseif t == "Session" then return M.session(entity)
  elseif t == "Variable" then return M.variable(entity)
  elseif t == "Scope" then return M.scope(entity)
  elseif t == "Source" then return M.source(entity)
  else return string.format("%s: %s", t, entity.uri:get())
  end
end

return M
