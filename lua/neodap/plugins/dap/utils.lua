-- DAP plugin utilities
local uri = require("neodap.uri")

local M = {}

---Generate a stable key for a DAP source
---Key is just the path or name - stable across sessions
---@param dap_source table DAP source object
---@return string? key The stable key, or nil if no path/name
function M.source_key(dap_source)
  return dap_source.path or dap_source.name
end

---Find or create a Source entity for a DAP source
---@param graph any The neograph instance
---@param debugger neodap.entities.Debugger
---@param dap_source table DAP source object
---@return neodap.entities.Source? source The Source entity, or nil if no key
function M.get_or_create_source(graph, debugger, dap_source)
  local key = M.source_key(dap_source)
  if not key then
    return nil
  end

  local existing = debugger:findSourceByKey(key)
  if existing then
    return existing
  end

  local entities = require("neodap.entities")
  local source = entities.Source.new(graph, {
    uri = uri.source(key),
    key = key,
    path = dap_source.path,
    name = dap_source.name,
  })
  debugger.sources:link(source)

  return source
end

---Clean up all bindings and frames associated with a session
---@param session neodap.entities.Session
function M.cleanup_session_bindings(session)
  -- Deactivate all frames from this session's threads
  for thread in session.threads:iter() do
    for stack in thread.stacks:iter() do
      for frame in stack.frames:iter() do
        if frame.active:get() then
          frame.active:set(false)
        end
      end
    end
  end

  -- Clean up source bindings and breakpoint bindings
  local source_bindings_to_delete = {}
  for sb in session.sourceBindings:iter() do
    local bp_bindings_to_delete = {}
    for bpb in sb.breakpointBindings:iter() do
      table.insert(bp_bindings_to_delete, bpb)
    end
    for _, bpb in ipairs(bp_bindings_to_delete) do
      bpb:delete()
    end
    table.insert(source_bindings_to_delete, sb)
  end
  for _, sb in ipairs(source_bindings_to_delete) do
    sb:delete()
  end
end

---Create ExceptionFilter entities from DAP capabilities
---@param graph any The neograph instance
---@param session neodap.entities.Session
---@param capabilities dap.Capabilities?
function M.create_exception_filters(graph, session, capabilities)
  if not capabilities or not capabilities.exceptionBreakpointFilters then
    return
  end

  local entities = require("neodap.entities")
  local session_id = session.sessionId:get()

  for _, filter in ipairs(capabilities.exceptionBreakpointFilters) do
    local ef = entities.ExceptionFilter.new(graph, {
      uri = uri.exceptionFilter(session_id, filter.filter),
      filterId = filter.filter,
      label = filter.label,
      description = filter.description,
      defaultEnabled = filter.default or false,
      supportsCondition = filter.supportsCondition or false,
      conditionDescription = filter.conditionDescription,
      enabled = filter.default or false,
      condition = nil,
    })
    ef.sessions:link(session)
    session.exceptionFilters:link(ef)
  end
end

return M
