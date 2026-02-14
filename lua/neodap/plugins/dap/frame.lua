-- Frame entity DAP methods
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local a = require("neodap.async")
local log = require("neodap.logger")

local Frame = entities.Frame

local get_dap_session = context.get_dap_session
local output_seqs = context.output_seqs
local next_global_seq = context.next_global_seq

---Create an Output entity linked to a session (protected, never throws)
---@param session neodap.entities.Session
---@param text string
---@param category string
---@param extra? table Additional output fields (variablesReference, etc.)
local function create_output(session, text, category, extra)
  pcall(function()
    local graph = session._graph
    local session_id = session.sessionId:get()
    output_seqs[session] = (output_seqs[session] or 0) + 1
    local seq = output_seqs[session]

    local props = {
      uri = uri.output(session_id, seq),
      seq = seq,
      globalSeq = next_global_seq(),
      text = text,
      category = category,
      visible = true,
      matched = true,
    }
    if extra then
      for k, v in pairs(extra) do props[k] = v end
    end

    local output = entities.Output.new(graph, props)
    session.outputs:link(output)
    session.allOutputs:link(output)

    local log_dir = session.logDir:get()
    if log_dir then
      local f = io.open(log_dir .. "/output.log", "a")
      if f then
        f:write(text)
        f:close()
      end
    end
  end)
end

---Get the DAP session for this frame (Frame → Session → DapSession)
---@return DapSession? dap_session, neodap.entities.Session? session
function Frame:dapSession()
  local session = self:session()
  if not session then return nil, nil end
  return get_dap_session(session), session
end

---Fetch scopes and populate Scope entities
---@param self neodap.entities.Frame
function Frame:fetchScopes()
  log:debug("fetchScopes: starting for " .. self.uri:get())
  -- Check if scopes already exist (avoid duplicate fetches)
  if self.scopes:count() > 0 then
    log:debug("fetchScopes: skipping (scopes exist)")
    return
  end

  local dap_session, session = self:dapSession()
  if not session then error("No session", 0) end
  if not dap_session then error("No DAP session", 0) end

  local graph = self._graph
  local frame_id = self.frameId:get()

  local body = a.wait(function(cb)
    dap_session.client:request("scopes", {
      frameId = frame_id,
    }, cb)
  end, "fetchScopes:request")

  -- Get sessionId and stops for URI
  local session_id = session.sessionId:get()
  local thread = self:thread()
  local stop_seq = thread and thread.stops:get() or 0

  -- Create Scope entities
  local count = 0
  for _, scope_data in ipairs(body.scopes or {}) do
    local scope = entities.Scope.new(graph, {
      uri = uri.scope(session_id, stop_seq, frame_id, scope_data.name),
      name = scope_data.name,
      presentationHint = scope_data.presentationHint,
      expensive = scope_data.expensive or false,
      variablesReference = scope_data.variablesReference,
    })
    self.scopes:link(scope)
    count = count + 1
  end
  log:debug("fetchScopes: created " .. count .. " scopes for " .. self.uri:get())
end

Frame.fetchScopes = a.memoize(Frame.fetchScopes)

---Evaluate expression in frame context
---@param self neodap.entities.Frame
---@param expression string
---@param opts? { silent?: boolean, context?: string } Options: silent=true skips output creation, context defaults to "repl"
---@return string result, number? variablesReference
function Frame:evaluate(expression, opts)
  local dap_session, session = self:dapSession()
  if not session then error("No session", 0) end
  if not dap_session then error("No DAP session", 0) end

  opts = opts or {}

  local ok, body = pcall(function()
    return a.wait(function(cb)
      dap_session.client:request("evaluate", {
        expression = expression,
        frameId = self.frameId:get(),
        context = opts.context or "repl",
      }, cb)
    end, "Frame:evaluate")
  end)

  if not ok then
    if not opts.silent then
      create_output(session, "❌ " .. tostring(body) .. "\n", "stderr")
    end
    error(body, 0)
  end

  if not opts.silent then
    create_output(session, expression .. " → " .. tostring(body.result) .. "\n", "repl",
      { variablesReference = body.variablesReference })
  end

  return body.result, body.variablesReference, body.type
end
Frame.evaluate = a.fn(Frame.evaluate)

---Get or create a Variable entity for an expression
---Unlike evaluate(), this returns a persistent entity that can be modified
---@param self neodap.entities.Frame
---@param expression string
---@return neodap.entities.Variable
function Frame:variable(expression)
  local dap_session, session = self:dapSession()
  if not session then error("No session", 0) end

  -- Check thread is stopped - frameId is only valid when stopped
  local thread = self:thread()
  if not thread or not thread:isStopped() then
    error("Thread is not stopped", 0)
  end

  -- Check frame's stack is the current stack (not stale from a previous stop)
  local stack = self.stack:get()
  local current_stack = thread.stack:get()
  if not current_stack or current_stack ~= stack then
    error("Frame is from a previous stop", 0)
  end

  if not dap_session then error("No DAP session", 0) end

  local graph = self._graph
  local session_id = session.sessionId:get()
  local frame_id = self.frameId:get()

  -- Check for existing variable with same evaluateName
  for var in self.variables:filter({
    filters = {{ field = "evaluateName", op = "eq", value = expression }}
  }):iter() do
    -- Re-evaluate and update existing entity
    local body = a.wait(function(cb)
      dap_session.client:request("evaluate", {
        expression = expression,
        frameId = frame_id,
        context = "repl",
      }, cb)
    end, "Frame:variable:update")

    var:update({
      value = body.result,
      varType = body.type,
      variablesReference = body.variablesReference or 0,
    })
    return var
  end

  -- Create new Variable entity
  local body = a.wait(function(cb)
    dap_session.client:request("evaluate", {
      expression = expression,
      frameId = frame_id,
      context = "repl",
    }, cb)
  end, "Frame:variable:create")

  -- Use expression as both name and evaluateName
  -- URI uses a special "eval" varRef (0) to distinguish from scope-found variables
  local variable = entities.Variable.new(graph, {
    uri = uri.variable(session_id, 0, expression),
    name = expression,
    value = body.result,
    varType = body.type,
    variablesReference = body.variablesReference or 0,
    evaluateName = expression,
  })
  self.variables:link(variable)

  return variable
end
Frame.variable = a.fn(Frame.variable)

---Get completions for expression text in frame context
---@param self neodap.entities.Frame
---@param text string The full text to complete
---@param column number 1-indexed column position
---@return dap.CompletionItem[] targets
function Frame:completions(text, column)
  local dap_session, session = self:dapSession()
  if not session then error("No session", 0) end
  if not dap_session then error("No DAP session", 0) end

  -- Check if adapter supports completions
  if not dap_session.capabilities or not dap_session.capabilities.supportsCompletionsRequest then
    return {}
  end

  local body = a.wait(function(cb)
    dap_session.client:request("completions", {
      text = text,
      column = column,
      frameId = self.frameId:get(),
    }, cb)
  end, "Frame:completions")

  return body and body.targets or {}
end
Frame.completions = a.fn(Frame.completions)

return Frame
