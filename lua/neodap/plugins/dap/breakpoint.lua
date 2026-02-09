-- Breakpoint sync logic and entity methods
local a = require("neodap.async")
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local log = require("neodap.logger")

local Source = entities.Source
local SourceBinding = entities.SourceBinding
local Breakpoint = entities.Breakpoint

local get_dap_session = context.get_dap_session

---Remove this breakpoint and all its bindings
---@param self neodap.entities.Breakpoint
function Breakpoint:remove()
  -- Remove all bindings first
  local bindings_to_remove = {}
  for binding in self.bindings:iter() do
    table.insert(bindings_to_remove, binding)
  end
  for _, binding in ipairs(bindings_to_remove) do
    binding:delete()
  end

  log:info("Removing breakpoint: " .. self.uri:get())
  self:delete()
end

---Sync breakpoints to the debug adapter for this source binding
---Sends setBreakpoints request with all breakpoints for this source
---@param self neodap.entities.SourceBinding
function SourceBinding:syncBreakpoints()
  local session = self.session:get()
  if not session then
    error("No session", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

  local source = self.source:get()
  if not source then
    error("No source", 0)
  end

  local graph = self._graph

  -- Build map of existing bindings by breakpoint ID for per-session overrides
  local binding_map = {} -- bp_entity:id() -> binding
  for binding in self.breakpointBindings:iter() do
    local bp = binding.breakpoint:get()
    if bp then
      binding_map[bp:id()] = binding
    end
  end

  -- Collect all enabled breakpoints for this source
  -- Use effective values (binding override or global default)
  local breakpoints = {}
  local bp_entities = {}
  for bp in source.breakpoints:iter() do
    local binding = binding_map[bp:id()]

    -- Get effective enabled state (binding override or global default)
    local bp_enabled
    if binding then
      bp_enabled = binding:getEffectiveEnabled()
    else
      bp_enabled = bp:isEnabled()
    end

    -- Skip disabled breakpoints
    if not bp_enabled then
      goto continue
    end

    table.insert(bp_entities, bp)
    local bp_data = {
      line = bp.line:get(),
    }
    if bp.column:get() then
      bp_data.column = bp.column:get()
    end

    -- Get effective condition/hitCondition/logMessage (binding override or global default)
    local condition, hitCondition, logMessage
    if binding then
      condition = binding:getEffectiveCondition()
      hitCondition = binding:getEffectiveHitCondition()
      logMessage = binding:getEffectiveLogMessage()
    else
      condition = bp.condition:get()
      hitCondition = bp.hitCondition:get()
      logMessage = bp.logMessage:get()
    end

    if condition then
      bp_data.condition = condition
    end
    if hitCondition then
      bp_data.hitCondition = hitCondition
    end
    if logMessage then
      bp_data.logMessage = logMessage
    end
    table.insert(breakpoints, bp_data)
    ::continue::
  end

  log:info("Breakpoint sync started: " .. self.uri:get())
  log:trace("Breakpoints to sync", { source = source.path:get(), breakpoints = breakpoints })

  -- Build source object for DAP
  local dap_source = {
    path = source.path:get(),
    name = source.name:get(),
  }
  local source_ref = self.sourceReference:get()
  if source_ref and source_ref > 0 then
    dap_source.sourceReference = source_ref
  end

  local body = a.wait(function(cb)
    dap_session.client:request("setBreakpoints", {
      source = dap_source,
      breakpoints = breakpoints,
    }, cb)
  end, "SourceBinding:syncBreakpoints")

  log:trace("setBreakpoints response", { body = body })

  -- Guard: SourceBinding may have been deleted (e.g., session terminated)
  if not graph:get(self._id) then
    return
  end

  -- Get info for URIs
  local session_id = session.sessionId:get()
  local source_path = source.key:get()

  -- Build map of existing bindings by breakpoint ID for update-in-place
  local existing_bindings = {} -- bp_entity:id() -> binding
  for binding in self.breakpointBindings:iter() do
    -- breakpoint is a reference rollup, use :get() not :iter()
    local bp = binding.breakpoint:get()
    if bp then
      existing_bindings[bp:id()] = binding
    end
  end

  local updated_bindings = {}

  -- Process responses - DAP spec says responses are in same order as requests
  -- No duplicate detection here - that's handled at toggle time via find_breakpoint_by_binding
  for i, bp_response in ipairs(body.breakpoints or {}) do
    local bp_entity = bp_entities[i]

    if bp_entity then
      local binding = existing_bindings[bp_entity:id()]
      if binding then
        -- Update in place
        binding:update({
          breakpointId = bp_response.id,
          verified = bp_response.verified or false,
          message = bp_response.message,
          actualLine = bp_response.line,
          actualColumn = bp_response.column,
        })
      else
        -- Create new binding
        local bp_line = bp_entity.line:get()
        local bp_column = bp_entity.column:get()
        binding = entities.BreakpointBinding.new(graph, {
          uri = uri.breakpointBinding(session_id, source_path, bp_line, bp_column),
          breakpointId = bp_response.id,
          verified = bp_response.verified or false,
          message = bp_response.message,
          actualLine = bp_response.line,
          actualColumn = bp_response.column,
        })
        bp_entity.bindings:link(binding)
        self.breakpointBindings:link(binding)
      end
      updated_bindings[bp_entity:id()] = true
    end
  end

  -- Remove bindings for breakpoints that are no longer in the response
  -- BUT preserve bindings with overrides (they're intentionally disabled for this session)
  for bp_id, binding in pairs(existing_bindings) do
    if not updated_bindings[bp_id] then
      if binding:hasOverride() then
        -- Keep the binding but mark as not verified (disabled for this session)
        binding:update({ verified = false, hit = false })
      else
        binding:delete()
      end
    end
  end

  log:info("Breakpoint sync completed: " .. self.uri:get())
end
SourceBinding.syncBreakpoints = a.fn(SourceBinding.syncBreakpoints)

---Sync breakpoints across all session bindings for this source
---@param self neodap.entities.Source
function Source:syncBreakpoints()
  local tasks = {}
  for binding in self.bindings:iter() do
    table.insert(tasks, a.run(function() binding:syncBreakpoints() end))
  end
  a.wait_all(tasks, "Source:syncBreakpoints")
end
Source.syncBreakpoints = a.fn(Source.syncBreakpoints)

return {
  Breakpoint = Breakpoint,
  Source = Source,
  SourceBinding = SourceBinding,
}
