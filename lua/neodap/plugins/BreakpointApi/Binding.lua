local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")
local nio = require("nio")
local Location = require("neodap.api.Location")

---@class api.BindingProps
---@field manager api.BreakpointManager
---@field session api.Session
---@field source api.Source
---@field breakpointId string
---@field id integer
---@field verified boolean
---@field line integer
---@field column integer
---@field actualLine? integer
---@field actualColumn? integer
---@field message? string
---@field hookable Hookable

---@class api.Binding: api.BindingProps
---@field new Constructor<api.BindingProps>
local Binding = Class()

---Create a verified binding from DAP response
---@param manager api.BreakpointManager
---@param session api.Session
---@param source api.Source
---@param breakpoint api.Breakpoint
---@param dapBreakpoint dap.Breakpoint
---@return api.Binding
function Binding.verified(manager, session, source, breakpoint, dapBreakpoint)
  if not dapBreakpoint or not dapBreakpoint.id then
    error("Invalid DAP breakpoint provided")
  end
  return Binding:new({
    manager = manager,
    session = session,
    source = source,
    breakpointId = breakpoint.id,
    id = dapBreakpoint.id,
    verified = true, -- Always true in lazy approach
    line = breakpoint.location.line,
    column = breakpoint.location.column,
    actualLine = dapBreakpoint.line,
    actualColumn = dapBreakpoint.column,
    message = dapBreakpoint.message,
    hookable = Hookable.create(manager.hookable),
  })
end

---Update binding from DAP response
---@param dapBreakpoint dap.Breakpoint
function Binding:update(dapBreakpoint)
  local changed = false
  
  if self.id ~= dapBreakpoint.id then
    self.id = dapBreakpoint.id
    changed = true
  end
  
  if self.actualLine ~= dapBreakpoint.line then
    self.actualLine = dapBreakpoint.line
    changed = true
  end
  
  if self.actualColumn ~= dapBreakpoint.column then
    self.actualColumn = dapBreakpoint.column
    changed = true
  end
  
  if self.message ~= dapBreakpoint.message then
    self.message = dapBreakpoint.message
    changed = true
  end
  
  if changed then
    self:emit('Updated', dapBreakpoint)
  end
end

-- Internal method to emit events
---@param event string
---@param data any
function Binding:emit(event, data)
  return self.hookable:emit(event, data)
end

-- API Methods: Event Registration

---@param listener async fun(hit: { thread: api.Thread, body: dap.StoppedEventBody }, resumed: nio.control.Future)
---@param opts? HookOptions
---@return fun() unsubscribe
function Binding:onHit(listener, opts)
  return self.hookable:on('Hit', 
  ---@param data { thread: api.Thread, body: dap.StoppedEventBody }
  function (data)
    local resumed = nio.control.future()
    data.thread:onResumed(function()
      if not self.hookable.destroyed then
        if not resumed.is_set() then
          resumed.set()
        end
      end
    end, { once = true })
   

    listener({
      thread = data.thread,
      body = data.body,
      binding = self,
    }, resumed)
  end, opts)
end

---@param listener fun(dapBreakpoint: dap.Breakpoint)
---@param opts? HookOptions
---@return fun() unsubscribe
function Binding:onUpdated(listener, opts)
  return self.hookable:on('Updated', listener, opts)
end

---@param listener fun()
---@param opts? HookOptions
---@return fun() unsubscribe
function Binding:onDispose(listener, opts)
  return self.hookable:onDispose(listener, opts)
end


-- Query Methods

---@return api.Breakpoint?
function Binding:getBreakpoint()
  return self.manager.breakpoints:get(self.breakpointId)
end

---@return api.Location
function Binding:getActualLocation()
  return Location.create({
    sourceId = self.source.id,
    line = self.actualLine or self.line,
    column = self.actualColumn or self.column,
  })
end

---@return api.Location
function Binding:getRequestedLocation()
  return Location.create({
    sourceId = self.source.id,
    line = self.line,
    column = self.column,
  })
end

---@return boolean
function Binding:wasMoved()
  return self.actualLine ~= self.line or self.actualColumn ~= self.column
end

-- Utility Methods

---@return dap.SourceBreakpoint
function Binding:toDapSourceBreakpoint()
  local breakpoint = self:getBreakpoint()
  return {
    id = self.id,
    line = self.actualLine or self.line,
    column = self.actualColumn or self.column,
    condition = breakpoint and breakpoint.condition,
    logMessage = breakpoint and breakpoint.logMessage,
  }
end

-- Hit handling (called by manager)
---@param thread api.Thread
---@param body dap.StoppedEventBody
function Binding:triggerHit(thread, body)
  self:emit('Hit', {
    thread = thread,
    body = body,
  })
end

-- Internal lifecycle method (called by manager)
function Binding:destroy()
  self.hookable:destroy()  -- Hookable will emit 'Dispose' event automatically
end

return Binding