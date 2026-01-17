-- Frame entity DAP methods
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local a = require("neodap.async")

local Frame = entities.Frame

local get_dap_session = context.get_dap_session
local output_seqs = context.output_seqs

---Fetch scopes and populate Scope entities
---@param self neodap.entities.Frame
function Frame:fetchScopes()
  -- Check if scopes already exist (avoid duplicate fetches)
  for _ in self.scopes:iter() do
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
  for _, scope_data in ipairs(body.scopes or {}) do
    local scope = entities.Scope.new(graph, {
      uri = uri.scope(session_id, stop_seq, frame_id, scope_data.name),
      name = scope_data.name,
      presentationHint = scope_data.presentationHint,
      expensive = scope_data.expensive or false,
      variablesReference = scope_data.variablesReference,
    })
    self.scopes:link(scope)
  end
end

Frame.fetchScopes = a.memoize(Frame.fetchScopes)

---Evaluate expression in frame context
---@param self neodap.entities.Frame
---@param expression string
---@return string result, number? variablesReference
function Frame:evaluate(expression)
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

  if not ok then
    -- Create error output (protected)
    pcall(function()
      local graph = session._graph
      local session_id = session.sessionId:get()
      output_seqs[session] = (output_seqs[session] or 0) + 1
      local seq = output_seqs[session]

      local output = entities.Output.new(graph, {
        uri = uri.output(session_id, seq),
        seq = seq,
        text = "❌ " .. tostring(body),
        category = "stderr",
      })
      -- Link from session.outputs (where subscriptions exist)
      session.outputs:link(output)
    end)

    error(body, 0)
  end

  -- Create result output (protected)
  pcall(function()
    local graph = session._graph
    local session_id = session.sessionId:get()
    output_seqs[session] = (output_seqs[session] or 0) + 1
    local seq = output_seqs[session]

    local result_text = expression .. " → " .. tostring(body.result)
    local output = entities.Output.new(graph, {
      uri = uri.output(session_id, seq),
      seq = seq,
      text = result_text,
      category = "repl",
      variablesReference = body.variablesReference,
    })
    -- Link from session.outputs (where subscriptions exist)
    session.outputs:link(output)
  end)

  return body.result, body.variablesReference
end
Frame.evaluate = a.fn(Frame.evaluate)

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
