local Class = require('neodap.tools.class')
local IdentifierStrategy = require('neodap.api.Session.Source.strategies.IdentifierStrategy')
local PathIdentifierStrategy = require('neodap.api.Session.Source.strategies.PathIdentifierStrategy')
local VirtualIdentifierStrategy = require('neodap.api.Session.Source.strategies.VirtualIdentifierStrategy')
local Logger = require('neodap.tools.logger')

---@class HybridIdentifierStrategy: IdentifierStrategy
---@field pathStrategy PathIdentifierStrategy?
---@field virtualStrategy VirtualIdentifierStrategy?
local HybridIdentifierStrategy = Class(IdentifierStrategy)

---Create hybrid strategy with both path and virtual strategies
---@param session api.Session
---@param source dap.Source
---@return HybridIdentifierStrategy
function HybridIdentifierStrategy.create(session, source)
  local instance = HybridIdentifierStrategy:new({
    session = session,
    source = source
  })
  
  if source.sourceReference and source.sourceReference > 0 then
    instance.virtualStrategy = VirtualIdentifierStrategy.create(session, source)
  end
  
  -- Create sub-strategies based on available data
  if source.path and source.path ~= '' then
    instance.pathStrategy = PathIdentifierStrategy.create(session, source)
  end
  
  
  return instance
end

---Create identifier preferring DAP-based for stability
---@return SourceIdentifier
function HybridIdentifierStrategy:createIdentifier()
  local log = Logger.get()
  
  -- Prefer Virtual identifier (more stable across sessions)
  if self.virtualStrategy then
    log:debug("HybridIdentifierStrategy: Using virtual identifier")
    return self.virtualStrategy:createIdentifier()
  end

  
  -- Fallback to path identifier
  if self.pathStrategy then
    log:debug("HybridIdentifierStrategy: Using path-based identifier")
    return self.pathStrategy:createIdentifier()
  end
  
  
  error("HybridIdentifierStrategy: No viable identifier strategy available")
end

---Hybrid identifiers are stable if path strategy is available or virtual is stable
---@return boolean
function HybridIdentifierStrategy:isStable()
  if self.pathStrategy then
    return self.pathStrategy:isStable()
  end
  
  if self.virtualStrategy then
    return self.virtualStrategy:isStable()
  end
  
  return false
end

return HybridIdentifierStrategy