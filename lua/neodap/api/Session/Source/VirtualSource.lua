local Class = require('neodap.tools.class')
local BaseSource = require('neodap.api.Session.Source.BaseSource')

---@class api.VirtualSource: api.BaseSource
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

---@return_cast self api.VirtualSource
function BaseSource:isVirtual()
  return self.type == 'virtual'
end

---@return_cast self api.FileSource
function BaseSource:isFile()
  return self.type == 'file'
end

---@return_cast self api.GenericSource
function BaseSource:isGeneric()
  return self.type == 'generic'
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
