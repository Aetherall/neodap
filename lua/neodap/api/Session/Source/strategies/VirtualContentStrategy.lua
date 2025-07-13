local Class = require('neodap.tools.class')
local ContentStrategy = require('neodap.api.Session.Source.strategies.ContentStrategy')
local Logger = require('neodap.tools.logger')
local nio = require('nio')

---@class VirtualContentStrategy: ContentStrategy
local VirtualContentStrategy = Class(ContentStrategy)

---Create a virtual content strategy instance
---@param session api.Session
---@param source dap.Source
---@return VirtualContentStrategy
function VirtualContentStrategy.create(session, source)
  return VirtualContentStrategy:new({
    session = session,
    source = source
  })
end

---Retrieve content via DAP source request
---@return string? content
function VirtualContentStrategy:getContent()
  local log = Logger.get()
  
  if not self.source.sourceReference or self.source.sourceReference <= 0 then
    log:warn("VirtualContentStrategy: No sourceReference available for content retrieval")
    return nil
  end
  
  log:debug("VirtualContentStrategy: Requesting content for sourceReference:", self.source.sourceReference)
  
  -- Make DAP source request
  local ok, result = pcall(function()
    return self.session.ref.calls:source({
      source = self.source,
      sourceReference = self.source.sourceReference
    }):wait()
  end)
  
  if not ok then
    log:error("VirtualContentStrategy: DAP source request failed:", result)
    return nil
  end
  
  if not result or not result.content then
    log:warn("VirtualContentStrategy: DAP returned no content for sourceReference:", self.source.sourceReference)
    return nil
  end
  
  log:debug("VirtualContentStrategy: Successfully retrieved content via DAP")
  return result.content
end

---Check if virtual content is available (assumes DAP can provide it)
---@return boolean
function VirtualContentStrategy:hasContent()
  return self.source.sourceReference and self.source.sourceReference > 0
end

return VirtualContentStrategy