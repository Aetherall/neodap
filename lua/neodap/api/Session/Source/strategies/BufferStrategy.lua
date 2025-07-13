local Class = require('neodap.tools.class')

---@class BufferStrategyProps
---@field source dap.Source
---@field session api.Session

---@class BufferStrategy: BufferStrategyProps
---@field new Constructor<BufferStrategyProps>
local BufferStrategy = Class()

---Create a buffer strategy instance
---@param session api.Session
---@param source dap.Source
---@return BufferStrategy
function BufferStrategy.create(session, source)
  return BufferStrategy:new({
    session = session,
    source = source
  })
end

---Get or create buffer for this source
---@param identifier SourceIdentifier
---@param contentStrategy ContentStrategy
---@return integer? bufnr
function BufferStrategy:getBuffer(identifier, contentStrategy)
  error("BufferStrategy:getBuffer() must be implemented by subclass")
end

---Check if buffer management is available for this source
---@return boolean
function BufferStrategy:canManageBuffer()
  error("BufferStrategy:canManageBuffer() must be implemented by subclass")
end

---Cleanup buffer resources if needed
---@param identifier SourceIdentifier
function BufferStrategy:cleanup(identifier)
  -- Default: no cleanup needed
end

return BufferStrategy