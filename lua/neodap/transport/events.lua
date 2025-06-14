local Class = require("neodap.tools.class")
local Hookable = require("neodap.transport.hookable")
local nio = require("nio")

---@class EventsProps
---@field hookable Hookable

---@class Events: EventsProps
---@field new Constructor<EventsProps>
local Events = Class()

function Events.create()
  local instance = Events:new({
    hookable = Hookable.create(),
  })

  return instance
end

---@param event dap.AnyEvent
function Events:push(event)
  self.hookable:emit(event.event, event.body)
end

---@alias On<N, B> fun(self: Events, event: N, handler: async fun(body: B), opts?: HookOptions): fun()
---@alias OnHandlers On<'breakpoint', dap.BreakpointEventBody>| On<'capabilities', dap.CapabilitiesEventBody>| On<'continued', dap.ContinuedEventBody>| On<'exited', dap.ExitedEventBody>| On<'initialized', {}>| On<'invalidated', dap.InvalidatedEventBody>| On<'loadedSource', dap.LoadedSourceEventBody>| On<'memory', dap.MemoryEventBody>| On<'module', dap.ModuleEventBody>| On<'output', dap.OutputEventBody>| On<'process', dap.ProcessEventBody>| On<'progressEnd', dap.ProgressEndEventBody>| On<'progressStart', dap.ProgressStartEventBody>| On<'progressUpdate', dap.ProgressUpdateEventBody>| On<'stopped', dap.StoppedEventBody>| On<'terminated', dap.TerminatedEventBody>| On<'thread', dap.ThreadEventBody>
---@type OnHandlers
function Events:on(event, handler, opts)
  return self.hookable:on(event, handler, opts)
end

function Events:off(event, name)
  self.hookable:off(event, name)
end

return Events
