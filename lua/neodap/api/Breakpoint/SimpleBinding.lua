local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")
local session = require("neodap.session.session")

---@class api.SimpleBindingProps
---@field session api.Session
---@field verified boolean
---@field actualLine? integer
---@field actualColumn? integer
---@field message? string
---@field source? api.Source
---@field ref table -- Compatibility property for existing tests
---@field hookable Hookable

---@class api.SimpleBinding: api.SimpleBindingProps
---@field new Constructor<api.SimpleBindingProps>
local SimpleBinding = Class()

---Create a new SimpleBinding instance
---@param session api.Session
---@param source? api.Source
---@return api.SimpleBinding
function SimpleBinding.create(session, source)
  return SimpleBinding:new({
    session = session,
    source = source,
    verified = false,
    actualLine = nil,
    actualColumn = nil,
    message = nil,
    ref = {}, -- Initialize compatibility ref
    hookable = Hookable.create()
  })
end

function SimpleBinding.unverified(session, source, breakpoint)
  return SimpleBinding:new({
    session = session,
    source = source,
    verified = false,
    actualLine = breakpoint.line,
    actualColumn = breakpoint.column,
    message = breakpoint.message,
    ref = breakpoint, -- Use the original breakpoint as ref
    hookable = Hookable.create()
  })
end

---Update binding from DAP breakpoint response
---@param dapBreakpoint dap.Breakpoint
function SimpleBinding:update(dapBreakpoint)
  self.verified = dapBreakpoint.verified or false
  self.actualLine = dapBreakpoint.line
  self.actualColumn = dapBreakpoint.column
  self.message = dapBreakpoint.message
  
  -- Update compatibility ref object
  self.ref = dapBreakpoint
end

---Check if binding is verified
---@return boolean
function SimpleBinding:isVerified()
  return self.verified == true
end

---Get actual location of breakpoint
---@return {line: integer?, column: integer?}
function SimpleBinding:getActualLocation()
  return {
    line = self.actualLine,
    column = self.actualColumn
  }
end

---Get verification message
---@return string?
function SimpleBinding:getMessage()
  return self.message
end

---Get the session for this binding
---@return api.Session
function SimpleBinding:getSession()
  return self.session
end

---Get the source for this binding
---@return api.Source?
function SimpleBinding:getSource()
  return self.source
end

---Listen for hit events on this binding
---@param listener fun(hit: table)
---@param opts? HookOptions
function SimpleBinding:onHit(listener, opts)
  return self.hookable:on('Hit', listener, opts)
end

return SimpleBinding
