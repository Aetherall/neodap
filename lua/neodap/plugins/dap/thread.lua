-- Thread entity DAP methods
local a = require("neodap.async")
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local log = require("neodap.logger")

local Thread = entities.Thread
local get_dap_session = context.get_dap_session

---Ensure a source and its session binding exist for a frame's source data.
---Links the frame to the source and creates a SourceBinding if needed.
---@param graph table
---@param debugger neodap.entities.Debugger
---@param session neodap.entities.Session
---@param frame_data table DAP stackFrame with .source
---@param frame neodap.entities.Frame
local function ensure_source_binding(graph, debugger, session, frame_data, frame)
  if not frame_data.source then return end

  local source = utils.get_or_create_source(graph, debugger, frame_data.source)
  if not source then return end

  source.frames:link(frame)

  for binding in source.bindings:iter() do
    if binding.session:get() == session then return end
  end

  local session_id = session.sessionId:get()
  local binding = entities.SourceBinding.new(graph, {
    uri = uri.sourceBinding(session_id, source.key:get()),
    sourceReference = frame_data.source.sourceReference or 0,
  })
  binding.sources:link(source); binding.sessions:link(session)
  source.bindings:link(binding); session.sourceBindings:link(binding)
  binding:syncBreakpoints()
end

local function get_session_and_client(self)
  local session = self.session:get()
  if not session then error("No session", 0) end
  if session:isTerminated() then error("Session terminated", 0) end
  local dap_session = get_dap_session(session)
  if not dap_session then error("No DAP session", 0) end
  if not dap_session.client then error("No DAP client", 0) end
  return session, dap_session
end

function Thread:continue()
  local _, dap_session = get_session_and_client(self)
  a.wait(function(cb)
    dap_session.client:request("continue", { threadId = self.threadId:get() }, cb)
  end)
  self:update({ state = "running" })
end
Thread.continue = a.fn(Thread.continue)

function Thread:pause()
  local _, dap_session = get_session_and_client(self)
  a.wait(function(cb)
    dap_session.client:request("pause", { threadId = self.threadId:get() }, cb)
  end)
end
Thread.pause = a.fn(Thread.pause)

---@param opts? { granularity?: "statement"|"line"|"instruction" }
function Thread:stepOver(opts)
  local _, dap_session = get_session_and_client(self)
  local args = { threadId = self.threadId:get() }
  if opts and opts.granularity then
    args.granularity = opts.granularity
  end
  a.wait(function(cb)
    dap_session.client:request("next", args, cb)
  end)
end
Thread.stepOver = a.fn(Thread.stepOver)

---@param opts? { granularity?: "statement"|"line"|"instruction", targetId?: number }
function Thread:stepIn(opts)
  local _, dap_session = get_session_and_client(self)
  local args = { threadId = self.threadId:get() }
  if opts and opts.granularity then
    args.granularity = opts.granularity
  end
  if opts and opts.targetId then
    args.targetId = opts.targetId
  end
  a.wait(function(cb)
    dap_session.client:request("stepIn", args, cb)
  end)
end
Thread.stepIn = a.fn(Thread.stepIn)

---@param opts? { granularity?: "statement"|"line"|"instruction" }
function Thread:stepOut(opts)
  local _, dap_session = get_session_and_client(self)
  local args = { threadId = self.threadId:get() }
  if opts and opts.granularity then
    args.granularity = opts.granularity
  end
  a.wait(function(cb)
    dap_session.client:request("stepOut", args, cb)
  end)
end
Thread.stepOut = a.fn(Thread.stepOut)

function Thread:fetchStackTrace()
  local session, dap_session = get_session_and_client(self)
  local graph = self._graph
  local stop_count = self.stops:get() or 0

  log:trace("fetchStackTrace: start " .. self.uri:get() .. " stop_count=" .. stop_count)

  -- Collect existing stacks first (avoid modifying during iteration)
  local existing_stacks = {}
  for s in self.stacks:iter() do
    table.insert(existing_stacks, s)
  end

  -- Check if we already have a stack for this stop
  -- stops increments on each stop, so stack count should match
  -- Guard: only skip if we actually have stacks and stops is set
  if stop_count > 0 and #existing_stacks >= stop_count then
    log:trace("fetchStackTrace: skip (have " .. #existing_stacks .. " stacks for stop_count=" .. stop_count .. ")")
    return
  end

  log:trace("fetchStackTrace: requesting stackTrace")
  local body = a.wait(function(cb)
    dap_session.client:request("stackTrace", { threadId = self.threadId:get() }, cb)
  end, "fetchStackTrace:request")
  log:trace("fetchStackTrace: got " .. (body.stackFrames and #body.stackFrames or 0) .. " frames")

  local debugger = session.debugger:get()
  local session_id = session.sessionId:get()
  local thread_id = self.threadId:get()

  -- Shift existing stacks' indexes up (new stack will be index 0)
  for _, existing_stack in ipairs(existing_stacks) do
    local old_index = existing_stack.index:get()
    local new_index = old_index + 1
    existing_stack:update({
      uri = uri.stack(session_id, thread_id, new_index),
      index = new_index,
    })
  end

  -- Create new stack with index 0 (latest), seq matches thread's stops
  local stack = entities.Stack.new(graph, { uri = uri.stack(session_id, thread_id, 0), index = 0, seq = stop_count })
  self.stacks:link(stack)
  log:debug("Stack created: " .. stack.uri:get() .. " seq=" .. stop_count)

  for old_stack in self.currentStacks:iter() do
    -- Mark old frames as inactive
    for frame in old_stack.frames:iter() do
      frame.active:set(false)
    end
    self.currentStacks:unlink(old_stack)
  end
  self.currentStacks:link(stack)

  local stop_seq = self.stops:get() or 0
  for i, frame_data in ipairs(body.stackFrames or {}) do
    local frame = entities.Frame.new(graph, {
      uri = uri.frame(session_id, stop_seq, frame_data.id),
      frameId = frame_data.id, index = i - 1, name = frame_data.name,
      line = frame_data.line, column = frame_data.column,
      active = true,
      presentationHint = frame_data.presentationHint,
    })
    stack.frames:link(frame)

    if debugger then
      ensure_source_binding(graph, debugger, session, frame_data, frame)
    end
  end
  log:trace("fetchStackTrace: complete")
end
Thread.fetchStackTrace = a.memoize(Thread.fetchStackTrace)

return Thread
