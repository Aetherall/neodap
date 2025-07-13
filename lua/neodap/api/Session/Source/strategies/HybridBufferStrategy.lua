local Class = require('neodap.tools.class')
local BufferStrategy = require('neodap.api.Session.Source.strategies.BufferStrategy')
local FileBufferStrategy = require('neodap.api.Session.Source.strategies.FileBufferStrategy')
local VirtualBufferStrategy = require('neodap.api.Session.Source.strategies.VirtualBufferStrategy')
local Logger = require('neodap.tools.logger')

---@class HybridBufferStrategy: BufferStrategy
---@field fileStrategy FileBufferStrategy?
---@field virtualStrategy VirtualBufferStrategy?
local HybridBufferStrategy = Class(BufferStrategy)

---Create hybrid strategy with both file and virtual buffer strategies
---@param session api.Session
---@param source dap.Source
---@return HybridBufferStrategy
function HybridBufferStrategy.create(session, source)
  local instance = HybridBufferStrategy:new({
    session = session,
    source = source
  })
  
  -- Create sub-strategies based on available data
  if source.path and source.path ~= '' then
    instance.fileStrategy = FileBufferStrategy.create(session, source)
  end
  
  if source.sourceReference and source.sourceReference > 0 then
    instance.virtualStrategy = VirtualBufferStrategy.create(session, source)
  end
  
  return instance
end

---Get buffer preferring Virtual strategy for better integration
---@param identifier SourceIdentifier
---@param contentStrategy ContentStrategy
---@return integer? bufnr
function HybridBufferStrategy:getBuffer(identifier, contentStrategy)
  local log = Logger.get()

  -- Prefer virtual buffer (better integration with DAP)
  if self.virtualStrategy and self.virtualStrategy:canManageBuffer() then
    log:debug("HybridBufferStrategy: Using virtual buffer strategy")
    return self.virtualStrategy:getBuffer(identifier, contentStrategy)
  end

  log:warn("HybridBufferStrategy: No viable buffer strategy available")
  return nil
end

---Buffer management is available if either strategy can manage buffers
---@return boolean
function HybridBufferStrategy:canManageBuffer()
  return (self.fileStrategy and self.fileStrategy:canManageBuffer()) or
         (self.virtualStrategy and self.virtualStrategy:canManageBuffer())
end

---Cleanup using appropriate strategy
---@param identifier SourceIdentifier
function HybridBufferStrategy:cleanup(identifier)
  if identifier:isFile() and self.fileStrategy then
    self.fileStrategy:cleanup(identifier)
  elseif identifier:isVirtual() and self.virtualStrategy then
    self.virtualStrategy:cleanup(identifier)
  end
end

return HybridBufferStrategy