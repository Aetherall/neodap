local Class = require('neodap.tools.class')
local ContentStrategy = require('neodap.api.Session.Source.strategies.ContentStrategy')
local FileContentStrategy = require('neodap.api.Session.Source.strategies.FileContentStrategy')
local VirtualContentStrategy = require('neodap.api.Session.Source.strategies.VirtualContentStrategy')
local Logger = require('neodap.tools.logger')

---@class HybridContentStrategy: ContentStrategy
---@field fileStrategy FileContentStrategy
---@field virtualStrategy VirtualContentStrategy
local HybridContentStrategy = Class(ContentStrategy)

---Create hybrid strategy with both file and virtual strategies
---@param session api.Session
---@param source dap.Source
---@return HybridContentStrategy
function HybridContentStrategy.create(session, source)
  local instance = HybridContentStrategy:new({
    session = session,
    source = source
  })
  instance.fileStrategy = FileContentStrategy.create(session, source)
  instance.virtualStrategy = VirtualContentStrategy.create(session, source)
  return instance
end

---Retrieve content trying DAP first, then file
---@return string? content
function HybridContentStrategy:getContent()
  local log = Logger.get()

  log:debug("HybridContentStrategy: Attempting DAP content first")

  -- Try DAP content first
  if self.virtualStrategy:hasContent() then
    local content = self.virtualStrategy:getContent()
    if content then
      log:debug("HybridContentStrategy: Using DAP content")
      return content
    end
  end

  log:debug("HybridContentStrategy: Falling back to file content")

  -- Fallback to file content
  if self.fileStrategy:hasContent() then
    local content = self.fileStrategy:getContent()
    if content then
      log:debug("HybridContentStrategy: Using file content")
      return content
    end
  end
  
  log:warn("HybridContentStrategy: No content available from either strategy")
  return nil
end

---Check if any content source is available
---@return boolean
function HybridContentStrategy:hasContent()
  return self.virtualStrategy:hasContent() or self.fileStrategy:hasContent()
end

---Get content hash preferring file strategy for consistency
---@return string
function HybridContentStrategy:getContentHash()
  -- Prefer virtual content hash for consistency across sessions
  if self.virtualStrategy:hasContent() then
    return self.virtualStrategy:getContentHash()
  end
  return self.fileStrategy:getContentHash()
end

return HybridContentStrategy