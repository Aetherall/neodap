local Class = require("neodap.tools.class")
local nio = require("nio")

---@class HookProps
---@field name string
---@field event dap.AnyEventName
---@field priority number
---@field handler fun(body: dap.AnyEventBody)
---@field once boolean

---@class Hook: HookProps
---@field new Constructor<{}>
local Hook = Class()


---@class EventsProps
---@field listeners { [dap.AnyEventName]?: { [number]?: { [string]?: Hook } } }

---@class Events: EventsProps
---@field new Constructor<EventsProps>
local Events = Class()



function Events.create()
  local instance = Events:new({
    listeners = {},
  })

  return instance
end

---@param event dap.AnyEvent
function Events:push(event)
  local listeners = self.listeners[event.event]
  if listeners then
    for priority, group in pairs(listeners) do
      for name, hook in pairs(group) do
        -- print("\n\nExecuting hook: " .. name .. " for event: " .. event.event)

        nio.run(function()
          hook.handler(event.body)
        end)


        if hook.once then
          group[name] = nil
        end
      end
    end
  end
end

---@alias On<N, B> fun(self: Events, event: N, handler: async fun(body: B), opts?: { name?: string, priority?: number, once?: boolean }): fun()

---@alias OnHandlers On<'breakpoint', dap.BreakpointEventBody>| On<'capabilities', dap.CapabilitiesEventBody>| On<'continued', dap.ContinuedEventBody>| On<'exited', dap.ExitedEventBody>| On<'initialized', {}>| On<'invalidated', dap.InvalidatedEventBody>| On<'loadedSource', dap.LoadedSourceEventBody>| On<'memory', dap.MemoryEventBody>| On<'module', dap.ModuleEventBody>| On<'output', dap.OutputEventBody>| On<'process', dap.ProcessEventBody>| On<'progressEnd', dap.ProgressEndEventBody>| On<'progressStart', dap.ProgressStartEventBody>| On<'progressUpdate', dap.ProgressUpdateEventBody>| On<'stopped', dap.StoppedEventBody>| On<'terminated', dap.TerminatedEventBody>| On<'thread', dap.ThreadEventBody>

---@type OnHandlers
function Events:on(event, handler, opts)
  opts = opts or {}
  local name = opts.name or math.random(1, 1000000) .. "_" .. event
  local priority = opts.priority or 10
  local once = opts.once or false

  if not self.listeners[event] then
    self.listeners[event] = {}
  end

  if not self.listeners[event][priority] then
    self.listeners[event][priority] = {}
  end

  if self.listeners[event][priority][name] then
    error("Hook with name '" .. name .. "' already exists for event '" .. event .. "'")
  end

  self.listeners[event][priority][name] = Hook:new({
    name = name,
    event = event,
    handler = handler,
    priority = priority,
    once = once,
  })

  return function()
    self:off(event, name)
  end
end

function Events:off(event, name)
  if not self.listeners[event] then
    return
  end

  for priority, group in pairs(self.listeners[event]) do
    if group[name] then
      group[name] = nil
      if next(group) == nil then
        self.listeners[event][priority] = nil
      end
    end
  end

  if next(self.listeners[event]) == nil then
    self.listeners[event] = nil
  end
end

return Events
