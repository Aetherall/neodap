local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")
local SimpleBinding = require('neodap.api.Breakpoint.SimpleBinding')

---@class api.SourceBreakpointProps
---@field api Api
---@field public _bindings { [integer]: api.SimpleBinding? }
---@field id string
---@field hookable Hookable
---@field path string
---@field line integer
---@field column? integer

---@class api.SourceBreakpoint: api.SourceBreakpointProps
---@field new Constructor<api.SourceBreakpointProps>
local SourceBreakpoint = Class()

---@param dapBreakpoint dap.Breakpoint
function SourceBreakpoint.getUniqueId(dapBreakpoint)
  if not dapBreakpoint or not dapBreakpoint.source or not dapBreakpoint.line then
    return nil
  end
  return dapBreakpoint.source.path .. ":" .. dapBreakpoint.line .. ":" .. (dapBreakpoint.column or 0)
end

---@param api Api
---@param path string
---@param line integer
---@param column? integer

---@class SourceBreakpointCreateOpts
---@field path string
---@field line? integer
---@field column? integer

---@param api Api
---@param opts SourceBreakpointCreateOpts
function SourceBreakpoint.create(api, opts)
  local id = opts.path .. ":" .. (opts.line or 0) .. ":" .. (opts.column or 0)

  return SourceBreakpoint:new({
    api = api,
    _bindings = {},
    hookable = Hookable.create(),
    id = id,
    line = opts.line or 0,
    column = opts.column or 0,
    path = opts.path,
  })
end

---@param session api.Session
function SourceBreakpoint:binding(session)
  return self._bindings[session.ref.id]
end

---@param session api.Session
function SourceBreakpoint:source(session)
  local binding = self:binding(session)
  if not binding then
    return nil
  end

  return binding.source
end

function SourceBreakpoint:bind(session, source)
  local existing = self:binding(session)
  if existing then return existing end

  local binding = SimpleBinding.unverified(session, source, self)
  self._bindings[session.ref.id] = binding

  -- NOTE: Don't emit 'Bound' event here - it will be emitted by SessionSync
  -- after the BreakpointAdded event to ensure proper timing

  return binding
end

---@param listener fun(binding: api.SimpleBinding)
---@param opts? HookOptions
function SourceBreakpoint:onBound(listener, opts)
  -- Register the listener for future bound events
  return self.hookable:on('Bound', listener, opts)
end

---@param session api.Session
---@param dapBreakpoint dap.Breakpoint
function SourceBreakpoint:handleBindingNew(session, dapBreakpoint)
  local sessionId = session.ref.id
  if not sessionId then return end

  local existing = self._bindings[sessionId]
  if existing then
    existing:update(dapBreakpoint)
    return existing
  end

  local source = dapBreakpoint.source and session:getSourceFor(dapBreakpoint.source) or nil
  local binding = SimpleBinding.create(session, source)
  binding:update(dapBreakpoint)
  self._bindings[sessionId] = binding

  -- NOTE: Don't emit 'Bound' event here - it will be emitted by SessionSync
  -- after the BreakpointAdded event to ensure proper timing

  return binding
end

---@param session api.Session
---@param dapBreakpoint dap.Breakpoint
function SourceBreakpoint:handleBindingChanged(session, dapBreakpoint)
  local sessionId = session.ref.id
  if not sessionId then return end

  local existing = self._bindings[sessionId]
  if existing then
    existing:update(dapBreakpoint)
    return existing
  end

  local source = dapBreakpoint.source and session:getSourceFor(dapBreakpoint.source) or nil
  local binding = SimpleBinding.create(session, source)
  binding:update(dapBreakpoint)
  self._bindings[sessionId] = binding

  -- NOTE: Don't emit 'Bound' event here - it will be emitted by SessionSync
  -- after the BreakpointAdded event to ensure proper timing

  return binding
end

---@param session api.Session
---@param dapBreakpoint dap.Breakpoint
function SourceBreakpoint:handleBindingRemoved(session, dapBreakpoint)
  local sessionId = session.ref.id
  if not sessionId then return end

  local existing = self._bindings[sessionId]
  if existing then
    -- existing:remove()
    self._bindings[sessionId] = nil
  end
end

---@return dap.SourceBreakpoint?
function SourceBreakpoint:toDapBreakpoint(session)
  local binding = self:binding(session)
  if not binding then
    return nil
  end

  return {
    line = binding.actualLine or self.line,
    column = binding.actualColumn or self.column,
  }
end

return SourceBreakpoint
