local Class = require('neodap.tools.class')

---@class IdentifierStrategyProps
---@field source dap.Source
---@field session api.Session

---@class IdentifierStrategy: IdentifierStrategyProps
---@field new Constructor<IdentifierStrategyProps>
local IdentifierStrategy = Class()

---Create an identifier strategy instance
---@param session api.Session
---@param source dap.Source
---@return IdentifierStrategy
function IdentifierStrategy.create(session, source)
  return IdentifierStrategy:new({
    session = session,
    source = source
  })
end

---Create a SourceIdentifier for this source
---@return SourceIdentifier
function IdentifierStrategy:createIdentifier()
  error("IdentifierStrategy:createIdentifier() must be implemented by subclass")
end

---Get string representation of the identifier
---@return string
function IdentifierStrategy:toString()
  return self:createIdentifier():toString()
end

---Check if this strategy can create a stable identifier
---@return boolean
function IdentifierStrategy:isStable()
  error("IdentifierStrategy:isStable() must be implemented by subclass")
end

return IdentifierStrategy