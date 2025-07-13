local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")
local nio = require("nio")
local SourceFilePosition = require("neodap.api.Location.SourceFilePosition")

---@class api.FileSourceBindingProps
---@field manager api.BreakpointManager
---@field session api.Session
---@field source api.FileSource
---@field breakpointId string
---@field id integer
---@field verified boolean
---@field line integer
---@field column integer
---@field actualLine? integer
---@field actualColumn? integer
---@field message? string
---@field hookable Hookable

---@class api.FileSourceBinding: api.FileSourceBindingProps
---@field new Constructor<api.FileSourceBindingProps>
local FileSourceBinding = Class()

---Create a verified binding from DAP response
---@param manager api.BreakpointManager
---@param session api.Session
---@param source api.FileSource
---@param breakpoint api.FileSourceBreakpoint
---@param dapBreakpoint dap.Breakpoint
---@return api.FileSourceBinding
function FileSourceBinding.verified(manager, session, source, breakpoint, dapBreakpoint)
  if not dapBreakpoint or not dapBreakpoint.id then
    error("Invalid DAP breakpoint provided")
  end
  return FileSourceBinding:new({
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
function FileSourceBinding:update(dapBreakpoint)
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
function FileSourceBinding:emit(event, data)
  return self.hookable:emit(event, data)
end

-- API Methods: Event Registration

---@param listener async fun(hit: { thread: api.Thread, body: dap.StoppedEventBody }, resumed: nio.control.Future)
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBinding:onHit(listener, opts)
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
function FileSourceBinding:onUpdated(listener, opts)
  return self.hookable:on('Updated', listener, opts)
end

---@param listener fun()
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBinding:onDispose(listener, opts)
  return self.hookable:onDispose(listener, opts)
end


-- Query Methods

---@return api.FileSourceBreakpoint?
function FileSourceBinding:getBreakpoint()
  return self.manager.breakpoints:get(self.breakpointId)
end

---@return api.SourceFilePosition
function FileSourceBinding:getActualLocation()
  return SourceFilePosition.create({
    path = self.source:absolutePath(),
    line = self.actualLine or self.line,
    column = self.actualColumn or self.column,
  })
end

---@return api.SourceFilePosition
function FileSourceBinding:getRequestedLocation()
  return SourceFilePosition.create({
    path = self.source:absolutePath(),
    line = self.line,
    column = self.column,
  })
end

---@return boolean
function FileSourceBinding:wasMoved()
  return self.actualLine ~= self.line or self.actualColumn ~= self.column
end

-- Utility Methods

---@return dap.SourceBreakpoint
function FileSourceBinding:toDapSourceBreakpoint()
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
function FileSourceBinding:triggerHit(thread, body)
  self:emit('Hit', {
    thread = thread,
    body = body,
  })
end

-- Internal lifecycle method (called by manager)
function FileSourceBinding:destroy()
  self.hookable:destroy()  -- Hookable will emit 'Dispose' event automatically
end

return FileSourceBinding