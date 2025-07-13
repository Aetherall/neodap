local Class = require('neodap.tools.class')
local IdentifierStrategy = require('neodap.api.Session.Source.strategies.IdentifierStrategy')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')

---@class VirtualIdentifierStrategy: IdentifierStrategy
local VirtualIdentifierStrategy = Class(IdentifierStrategy)

---Create a virtual identifier strategy instance
---@param session api.Session
---@param source dap.Source
---@return VirtualIdentifierStrategy
function VirtualIdentifierStrategy.create(session, source)
  return VirtualIdentifierStrategy:new({
    session = session,
    source = source
  })
end

---Create a virtual SourceIdentifier using stability hash
---@return SourceIdentifier
function VirtualIdentifierStrategy:createIdentifier()
  if not self.source.sourceReference or self.source.sourceReference <= 0 then
    error("VirtualIdentifierStrategy: Cannot create identifier without sourceReference")
  end
  
  return SourceIdentifier.fromDapSource(self.source, self.session)
end

---Virtual identifiers are stable if they have sufficient metadata
---@return boolean
function VirtualIdentifierStrategy:isStable()
  -- Stable if we have name and origin for hash calculation
  return (self.source.name and self.source.name ~= '') and 
         (self.source.origin and self.source.origin ~= '')
end

return VirtualIdentifierStrategy