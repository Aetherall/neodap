-- Frame entity DAP methods
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local a = require("neodap.async")
local log = require("neodap.logger")

local Frame = entities.Frame

local get_dap_session = context.get_dap_session
local output_seqs = context.output_seqs
local next_global_seq = context.next_global_seq

---Fetch scopes and populate Scope entities
---@param self neodap.entities.Frame
function Frame:fetchScopes()
  log:debug("fetchScopes: starting for " .. self.uri:get())
  -- Check if scopes already exist (avoid duplicate fetches)
  for _ in self.scopes:iter() do
    log:debug("fetchScopes: skipping (scopes exist)")
    return
  end

  -- Traverse to find session for DAP access
  local stack = self.stack:get()
  local thread = stack and stack.thread:get()
  local session = thread and thread.session:get()

  if not session then
    error("No session", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

  local graph = self._graph
  local frame_id = self.frameId:get()

  local body = a.wait(function(cb)
    dap_session.client:request("scopes", {
      frameId = frame_id,
    }, cb)
  end, "fetchScopes:request")

  -- Get sessionId and stops for URI
  local session_id = session.sessionId:get()
  local stop_seq = thread.stops:get() or 0

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
---@param opts? { silent?: boolean } Options: silent=true skips output creation
---@return string result, number? variablesReference
function Frame:evaluate(expression, opts)
  -- Traverse to find session for DAP access
  local stack = self.stack:get()
  local thread = stack and stack.thread:get()
  local session = thread and thread.session:get()

  if not session then
    error("No session", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

  local ok, body = pcall(function()
    return a.wait(function(cb)
      dap_session.client:request("evaluate", {
        expression = expression,
        frameId = self.frameId:get(),
        context = "repl",
      }, cb)
    end, "Frame:evaluate")
  end)

  opts = opts or {}

  if not ok then
    -- Create error output (protected) unless silent
    if not opts.silent then
      pcall(function()
        local graph = session._graph
        local session_id = session.sessionId:get()
        output_seqs[session] = (output_seqs[session] or 0) + 1
        local seq = output_seqs[session]
        local error_text = "❌ " .. tostring(body) .. "\n"

        local output = entities.Output.new(graph, {
          uri = uri.output(session_id, seq),
          seq = seq,
          globalSeq = next_global_seq(),
          text = error_text,
          category = "stderr",
          visible = true,
          matched = true,
        })
        session.outputs:link(output)
        session.allOutputs:link(output)

        -- Write to log file
        local log_dir = session.logDir:get()
        if log_dir then
          local f = io.open(log_dir .. "/output.log", "a")
          if f then
            f:write(error_text)
            f:close()
          end
        end
      end)
    end

    error(body, 0)
  end

  -- Create result output (protected) unless silent
  if not opts.silent then
    pcall(function()
      local graph = session._graph
      local session_id = session.sessionId:get()
      output_seqs[session] = (output_seqs[session] or 0) + 1
      local seq = output_seqs[session]
      local result_text = expression .. " → " .. tostring(body.result) .. "\n"

      local output = entities.Output.new(graph, {
        uri = uri.output(session_id, seq),
        seq = seq,
        globalSeq = next_global_seq(),
        text = result_text,
        category = "repl",
        variablesReference = body.variablesReference,
        visible = true,
        matched = true,
      })
      session.outputs:link(output)
      session.allOutputs:link(output)

      -- Write to log file
      local log_dir = session.logDir:get()
      if log_dir then
        local f = io.open(log_dir .. "/output.log", "a")
        if f then
          f:write(result_text)
          f:close()
        end
      end
    end)
  end

  return body.result, body.variablesReference, body.type
end
Frame.evaluate = a.fn(Frame.evaluate)

---Set expression value in frame context
---@param self neodap.entities.Frame
---@param expression string The expression to assign to
---@param value string The new value (as expression string)
---@return string result The new value after assignment
---@return number? variablesReference If > 0, the value is structured
---@return string? type The type of the value
function Frame:setExpression(expression, value)
  -- Traverse to find session for DAP access
  local stack = self.stack:get()
  local thread = stack and stack.thread:get()
  local session = thread and thread.session:get()

  if not session then
    error("No session", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

  -- Check if adapter supports setExpression
  if not dap_session.capabilities or not dap_session.capabilities.supportsSetExpression then
    error("Adapter does not support setExpression", 0)
  end

  local body = a.wait(function(cb)
    dap_session.client:request("setExpression", {
      expression = expression,
      value = value,
      frameId = self.frameId:get(),
    }, cb)
  end, "Frame:setExpression")

  return body.value, body.variablesReference, body.type
end
Frame.setExpression = a.fn(Frame.setExpression)

---Get or create a Variable entity for an expression
---Unlike evaluate(), this returns a persistent entity that can be modified
---@param self neodap.entities.Frame
---@param expression string
---@return neodap.entities.Variable
function Frame:variable(expression)
  -- Traverse to find session for DAP access
  local stack = self.stack:get()
  local thread = stack and stack.thread:get()
  local session = thread and thread.session:get()

  if not session then
    error("No session", 0)
  end

  -- Check thread is stopped - frameId is only valid when stopped
  if not thread:isStopped() then
    error("Thread is not stopped", 0)
  end

  -- Check frame's stack is the current stack (not stale from a previous stop)
  local current_stack = thread.stack:get()
  if not current_stack or current_stack ~= stack then
    error("Frame is from a previous stop", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

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
  -- Traverse to find session for DAP access
  local stack = self.stack:get()
  local thread = stack and stack.thread:get()
  local session = thread and thread.session:get()

  if not session then
    error("No session", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

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
