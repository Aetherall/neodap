-- DAP plugin utilities
local uri = require("neodap.uri")
local a = require("neodap.async")

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
---@param session? neodap.entities.Session Optional session for fallbackFiletype
---@return neodap.entities.Source? source The Source entity, or nil if no key
function M.get_or_create_source(graph, debugger, dap_source, session)
  local key = M.source_key(dap_source)
  if not key then
    return nil
  end

  -- O(1) lookup via graph's by_key index
  local existing = debugger:findSourceByKey(key)
  if existing then
    return existing
  end

  -- Determine fallbackFiletype for virtual sources
  -- Only set if filetype can't be detected from name/path
  local fallback_ft = nil
  local name = dap_source.name or ""
  local path = dap_source.path or ""
  local detected = vim.filetype.match({ filename = name })
    or vim.filetype.match({ filename = path })
  if not detected and session then
    fallback_ft = session.fallbackFiletype:get()
  end

  -- Create new source (automatically indexed by graph)
  local entities = require("neodap.entities")
  local source = entities.Source.new(graph, {
    uri = uri.source(key),
    key = key,
    path = dap_source.path,
    name = dap_source.name,
    fallbackFiletype = fallback_ft,
    presentationHint = dap_source.presentationHint,
  })
  debugger.sources:link(source)

  return source
end

-- Track which sessions have already been cleaned up
local cleaned_sessions = setmetatable({}, { __mode = "k" })

---Clean up all bindings and frames associated with a session
---@param session neodap.entities.Session
function M.cleanup_session_bindings(session)
  if cleaned_sessions[session] then return end
  cleaned_sessions[session] = true

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
  -- Collect first to avoid modifying during iteration
  local bp_bindings_to_delete = {}
  session:forEachBreakpointBinding(function(bpb)
    table.insert(bp_bindings_to_delete, bpb)
  end)
  for _, bpb in ipairs(bp_bindings_to_delete) do
    bpb:delete()
  end

  local source_bindings_to_delete = {}
  for sb in session.sourceBindings:iter() do
    table.insert(source_bindings_to_delete, sb)
  end
  for _, sb in ipairs(source_bindings_to_delete) do
    sb:delete()
  end

  -- Clean up per-session temp directory (output logs, etc.)
  local log_dir = session.logDir and session.logDir:get()
  if log_dir then
    vim.fn.delete(log_dir, "rf")
  end
end

---Create ExceptionFilter entities and ExceptionFilterBinding entities from DAP capabilities
---ExceptionFilters are global (debugger-scoped), ExceptionFilterBindings are per-session
---@param graph any The neograph instance
---@param debugger neodap.entities.Debugger
---@param session neodap.entities.Session
---@param capabilities dap.Capabilities?
function M.create_exception_filters(graph, debugger, session, capabilities)
  if not capabilities or not capabilities.exceptionBreakpointFilters then
    return
  end

  local entities = require("neodap.entities")
  local session_id = session.sessionId:get()

  for _, filter in ipairs(capabilities.exceptionBreakpointFilters) do
    -- Find or create global ExceptionFilter
    local ef = nil
    for existing in debugger.exceptionFilters:filter({
      filters = {{ field = "filterId", op = "eq", value = filter.filter }}
    }):iter() do
      ef = existing
      break
    end

    if not ef then
      ef = entities.ExceptionFilter.new(graph, {
        uri = uri.exceptionFilter(filter.filter),
        filterId = filter.filter,
        label = filter.label,
        description = filter.description,
        defaultEnabled = filter.default or false,
        supportsCondition = filter.supportsCondition or false,
        conditionDescription = filter.conditionDescription,
      })
      ef.debuggers:link(debugger)
      debugger.exceptionFilters:link(ef)
    end

    -- Create session binding
    local binding = entities.ExceptionFilterBinding.new(graph, {
      uri = uri.exceptionFilterBinding(session_id, filter.filter),
      enabled = nil,  -- use global default
      condition = nil,
    })
    binding.exceptionFilters:link(ef)
    binding.sessions:link(session)
    ef.bindings:link(binding)
    session.exceptionFilterBindings:link(binding)
  end
end

---Fetch variables from DAP and create Variable entities linked to a parent edge
---Shared by Scope:fetchVariables and Variable:fetchChildren
---@param parent table Entity with variablesReference signal and a dapSession() method
---@param edge table Edge to link new Variable entities to (parent.variables or parent.children)
---@param label string Label for async wait (e.g., "fetchVariables", "fetchChildren")
function M.fetch_variables(parent, edge, label)
  if edge:count() > 0 then return end

  local dap_session, session = parent:dapSession()
  if not session then error("No session", 0) end
  if not dap_session then error("No DAP session", 0) end

  local vars_ref = parent.variablesReference:get()
  if not vars_ref or vars_ref == 0 then return end

  local entities = require("neodap.entities")
  local session_id = session.sessionId:get()

  local body = a.wait(function(cb)
    dap_session.client:request("variables", {
      variablesReference = vars_ref,
    }, cb)
  end, label .. ":request")

  for _, var_data in ipairs(body.variables or {}) do
    local variable = entities.Variable.new(parent._graph, {
      uri = uri.variable(session_id, vars_ref, var_data.name),
      name = var_data.name,
      value = var_data.value,
      varType = var_data.type,
      variablesReference = var_data.variablesReference or 0,
      evaluateName = var_data.evaluateName,
    })
    edge:link(variable)
  end
end

return M
