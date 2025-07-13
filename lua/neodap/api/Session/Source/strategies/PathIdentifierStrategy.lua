local Class = require('neodap.tools.class')
local IdentifierStrategy = require('neodap.api.Session.Source.strategies.IdentifierStrategy')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')

---@class PathIdentifierStrategy: IdentifierStrategy
local PathIdentifierStrategy = Class(IdentifierStrategy)

---Create a path identifier strategy instance
---@param session api.Session
---@param source dap.Source
---@return PathIdentifierStrategy
function PathIdentifierStrategy.create(session, source)
  return PathIdentifierStrategy:new({
    session = session,
    source = source
  })
end

---Create a file-based SourceIdentifier
---@return SourceIdentifier
function PathIdentifierStrategy:createIdentifier()
  if not self.source.path or self.source.path == '' then
    error("PathIdentifierStrategy: Cannot create identifier without source path")
  end
  
  return SourceIdentifier.fromPath(self.source.path)
end

---Path-based identifiers are stable across sessions
---@return boolean
function PathIdentifierStrategy:isStable()
  return true
end

return PathIdentifierStrategy