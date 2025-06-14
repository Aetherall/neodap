local Class = require('neodap.tools.class')
local BaseSource = require('neodap.api.Session.Source.BaseSource')

---@class api.VirtualSource: api.Source
local VirtualSource = Class(BaseSource)

---@param session api.Session
---@param source dap.Source
---@return api.VirtualSource
function VirtualSource.instanciate(session, source)
  if not source.sourceReference or source.sourceReference == 0 then
    error("Should not be able to instantiate a VirtualSource without a sourceReference")
  end

  local instance = VirtualSource:new({
    session = session,
    ref = source,
    _content = nil,
    type = 'virtual',
  })
  return instance
end

function VirtualSource:reference()
  return self.ref.sourceReference
end

function VirtualSource:origin()
  return self.ref.origin or 'unknown'
end

function VirtualSource:toString()
  return string.format("VirtualSource(%s, %s)", self:origin(), self:reference())
end

return VirtualSource
