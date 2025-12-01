---@class Frame : Class
---@field stack Stack
---@field id number
---@field uri string
---@field name string
---@field source Source
---@field line number
---@field column number
---@field endLine number?
---@field endColumn number?
---@field presentationHint string?

local neostate = require("neostate")
local Scope = require("neodap.sdk.session.scope")
local Source = require("neodap.sdk.debugger.source")

local M = {}

-- =============================================================================
-- FRAME
-- =============================================================================

---@class Frame : Class
local Frame = neostate.Class("Frame")

function Frame:init(stack, data, index)
  self.stack = stack
  self.id = data.id
  self.index = self:signal(index or 0, "index")
  self.name = data.name

  -- URI and key for EntityStore
  -- Include stack in URI to make frames unique (frame IDs can be reused across stacks)
  self.uri = string.format(
    "dap:session:%s/thread:%d/stack:%d/frame:%d",
    stack.thread.session.id,
    stack.thread.id,
    stack.sequence,
    data.id
  )
  self.key = "frame:" .. data.id
  self._type = "frame"

  -- Get or create Source entity (reuses existing from session.sources)
  if data.source then
    self.source = stack.thread.session:get_or_create_source(data.source)
  end

  self.line = data.line
  self.column = data.column
  self.endLine = data.endLine
  self.endColumn = data.endColumn
  self.presentationHint = data.presentationHint

  -- Helper property for location-based lookups
  if self.source and self.source.path and self.line then
    self.location = self.source.path .. ":" .. self.line
  else
    self.location = nil
  end

  self._scopes_fetched = false  -- Track if scopes have been fetched
  self._is_current = self:signal(true, "is_current")

  -- Mark bindings as hit if this frame is at a breakpoint location
  -- Only mark if this is the top frame (index 0) and stack is current
  if self.index:get() == 0 and stack:is_current() and self.location and stack.reason == "breakpoint" then
    local session = stack.thread.session

    -- Find matching bindings by iterating and checking both requested and actual lines
    -- This handles the case where debugger adjusts breakpoint lines
    local matching_bindings = {}
    for binding in session:bindings():iter() do
      local bp = binding.breakpoint
      -- Check if this binding's source matches
      if bp.source.path == self.source.path then
        local actual_line = binding.actualLine:get()
        -- Match if frame line equals either the requested line or the actual line
        if bp.line == self.line or (actual_line and actual_line == self.line) then
          table.insert(matching_bindings, binding)
        end
      end
    end

    if #matching_bindings > 0 then
      for _, binding in ipairs(matching_bindings) do
        binding.active_frame:set(self.uri)
      end
    end
  end
end

---Check if this frame is current (stack not expired)
---@return boolean
function Frame:is_current()
  return self._is_current:get()
end

---Mark this frame as expired (stack expired)
---Propagates expiration to all scopes
---@private
function Frame:_mark_expired()
  -- Skip if already disposed (prevents errors when trying to set signals on disposed objects)
  if self._disposed then
    return
  end

  self._is_current:set(false)

  -- Propagate to scopes (if loaded) via EntityStore View
  if self._scopes_fetched then
    local debugger = self.stack.thread.session.debugger
    for scope in debugger.scopes:where("by_frame_id", self.uri):iter() do
      scope:_mark_expired()
    end
  end
end

---Fetch scopes for this frame (lazy)
---@return View scopes View of scopes for this frame
function Frame:scopes()
  -- Fetch from DAP if not yet loaded
  if not self._scopes_fetched then
    self:_fetch_scopes()
  end

  -- Return cached View
  if not self._scopes_view then
    local debugger = self.stack.thread.session.debugger
    self._scopes_view = debugger.scopes:where(
      "by_frame_id",
      self.uri,
      "Scopes:Frame:" .. self.uri
    )
  end
  return self._scopes_view
end

---Internal: Fetch scopes from DAP
---@private
function Frame:_fetch_scopes()
  -- Check if already loaded or in progress
  if self._scopes_fetched then
    return
  end

  -- Mark as fetched BEFORE async request to prevent concurrent fetches
  -- (settle yields, allowing other coroutines to call this method)
  self._scopes_fetched = true

  local session = self.stack.thread.session
  local debugger = session.debugger
  local result, err = neostate.settle(self.stack.thread.session.client:request("scopes", {
    frameId = self.id,
  }))

  if err or not result or not result.scopes then
    return
  end

  for _, scope_data in ipairs(result.scopes) do
    local scope = Scope.Scope:new(self, scope_data)
    scope:set_parent(self)

    -- Add to EntityStore with "scope" edge to frame
    debugger.store:add(scope, "scope", {
      { type = "scope", to = self.uri }
    })
  end
end

---Fetch children (alias for scopes)
---@return View scopes View of scopes for this frame
function Frame:children()
  return self:scopes()
end

---Register callback for when this frame expires (stack expired)
---@param fn function  -- Called with no arguments
---@return function unsubscribe
function Frame:onExpired(fn)
  return self._is_current:watch(function(is_current)
    if not is_current then
      fn()
    end
  end)
end

---Get completions for text at cursor position in this frame's context
---@param text string  Text typed so far (e.g., "user.na")
---@param column integer  Cursor position within text (1-based)
---@param line? integer  Line within text (default 1)
---@return string? error, dap.CompletionItem[]? completions
function Frame:completions(text, column, line)
  local session = self.stack.thread.session
  return session:completions(text, column, {
    frameId = self.id,
    line = line,
  })
end

---Evaluate an expression in this frame's context
---@param expression string
---@param context? "watch"|"repl"|"hover"|"clipboard"|"variables"
---@return string? error, EvaluateResult? result
function Frame:evaluate(expression, context)
  local session = self.stack.thread.session

  local result, err = neostate.settle(session.client:request("evaluate", {
    expression = expression,
    frameId = self.id,
    context = context or "repl",
  }))

  if err then
    return err, nil
  end

  if not result then
    return nil, nil
  end

  local EvaluateResult = require("neodap.sdk.session.evaluate_result")

  -- Create EvaluateResult with session reference (independent of frame lifecycle)
  -- It gets disposed when the session ends
  local eval_result = EvaluateResult.EvaluateResult:new(session, expression, context, result)
  eval_result:set_parent(session)

  return nil, eval_result
end

M.Frame = Frame

-- Backwards compatibility
function M.create(stack, data)
  return Frame:new(stack, data)
end

return M
