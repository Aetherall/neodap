local Class = require('neodap.tools.class')
local BaseSource = require('neodap.api.Session.Source.BaseSource')
local Logger = require('neodap.tools.logger')

-- Strategy imports
local FileContentStrategy = require('neodap.api.Session.Source.strategies.FileContentStrategy')
local VirtualContentStrategy = require('neodap.api.Session.Source.strategies.VirtualContentStrategy')
local HybridContentStrategy = require('neodap.api.Session.Source.strategies.HybridContentStrategy')

local PathIdentifierStrategy = require('neodap.api.Session.Source.strategies.PathIdentifierStrategy')
local VirtualIdentifierStrategy = require('neodap.api.Session.Source.strategies.VirtualIdentifierStrategy')
local HybridIdentifierStrategy = require('neodap.api.Session.Source.strategies.HybridIdentifierStrategy')

local FileBufferStrategy = require('neodap.api.Session.Source.strategies.FileBufferStrategy')
local VirtualBufferStrategy = require('neodap.api.Session.Source.strategies.VirtualBufferStrategy')
local HybridBufferStrategy = require('neodap.api.Session.Source.strategies.HybridBufferStrategy')

---@class api.UnifiedSource: api.BaseSource
---@field contentStrategy ContentStrategy
---@field identifierStrategy IdentifierStrategy
---@field bufferStrategy BufferStrategy
---@field _identifier SourceIdentifier? -- Cached SourceIdentifier
local UnifiedSource = Class(BaseSource)

---Create a unified source with strategy composition
---@param session api.Session
---@param source dap.Source
---@return api.UnifiedSource
function UnifiedSource.instanciate(session, source)
  local log = Logger.get()
  
  -- Determine strategies based on source properties
  local contentStrategy = UnifiedSource._determineContentStrategy(session, source)
  local identifierStrategy = UnifiedSource._determineIdentifierStrategy(session, source)
  local bufferStrategy = UnifiedSource._determineBufferStrategy(session, source)
  
  -- Determine legacy type for backward compatibility
  local legacyType = UnifiedSource._determineLegacyType(source)
  
  log:debug("UnifiedSource: Creating with strategies", {
    content = contentStrategy.__class,
    identifier = identifierStrategy.__class,
    buffer = bufferStrategy.__class,
    legacyType = legacyType
  })
  
  local instance = UnifiedSource:new({
    session = session,
    ref = source,
    type = legacyType, -- For backward compatibility
    _content = nil,
    contentStrategy = contentStrategy,
    identifierStrategy = identifierStrategy,
    bufferStrategy = bufferStrategy,
    _identifier = nil -- Cached SourceIdentifier
  })
  
  return instance
end

---Determine content strategy based on source properties
---@param session api.Session
---@param source dap.Source
---@return ContentStrategy
function UnifiedSource._determineContentStrategy(session, source)
  local hasPath = source.path and source.path ~= ''
  local hasSourceRef = source.sourceReference and source.sourceReference > 0
  
  if hasPath and hasSourceRef then
    return HybridContentStrategy.create(session, source)
  elseif hasPath then
    return FileContentStrategy.create(session, source)
  elseif hasSourceRef then
    return VirtualContentStrategy.create(session, source)
  else
    -- Fallback to file strategy with no content
    return FileContentStrategy.create(session, source)
  end
end

---Determine identifier strategy based on source properties
---@param session api.Session
---@param source dap.Source
---@return IdentifierStrategy
function UnifiedSource._determineIdentifierStrategy(session, source)
  local hasPath = source.path and source.path ~= ''
  local hasSourceRef = source.sourceReference and source.sourceReference > 0
  
  if hasPath and hasSourceRef then
    return HybridIdentifierStrategy.create(session, source)
  elseif hasPath then
    return PathIdentifierStrategy.create(session, source)
  elseif hasSourceRef then
    return VirtualIdentifierStrategy.create(session, source)
  else
    error("UnifiedSource: Cannot create identifier strategy without path or sourceReference")
  end
end

---Determine buffer strategy based on source properties
---@param session api.Session
---@param source dap.Source
---@return BufferStrategy
function UnifiedSource._determineBufferStrategy(session, source)
  local hasPath = source.path and source.path ~= ''
  local hasSourceRef = source.sourceReference and source.sourceReference > 0
  
  if hasPath and hasSourceRef then
    return HybridBufferStrategy.create(session, source)
  elseif hasPath then
    return FileBufferStrategy.create(session, source)
  elseif hasSourceRef then
    return VirtualBufferStrategy.create(session, source)
  else
    -- Fallback to file strategy (might not work but graceful degradation)
    return FileBufferStrategy.create(session, source)
  end
end

---Determine legacy type for backward compatibility
---@param source dap.Source
---@return 'file' | 'virtual' | 'generic'
function UnifiedSource._determineLegacyType(source)
  -- Use the same logic as the original Source.lua factory
  if source.sourceReference and source.sourceReference > 0 then
    return 'virtual'
  elseif source.path and source.path ~= '' then
    return 'file'
  else
    return 'generic'
  end
end

-- Unified API methods using strategies

---Get session-independent identifier for this source
---@return SourceIdentifier
function UnifiedSource:identifier()
  if not self._identifier then
    self._identifier = self.identifierStrategy:createIdentifier()
  end
  return self._identifier
end

---Get or create buffer for this source
---@return integer?
function UnifiedSource:bufnr()
  local identifier = self:identifier()
  return self.bufferStrategy:getBuffer(identifier, self.contentStrategy)
end

---Get content for this source (override BaseSource/ContentAccessTrait)
---@return string?
function UnifiedSource:content()
  return self.contentStrategy:getContent()
end

---Check if content is available
---@return boolean
function UnifiedSource:hasContent()
  return self.contentStrategy:hasContent()
end

---Get content hash for validation
---@return string
function UnifiedSource:contentHash()
  return self.contentStrategy:getContentHash()
end

-- Backward compatibility methods (delegate to legacy type)

---@return string
function UnifiedSource:filename()
  if self.type == 'file' and self.ref.path then
    return vim.fn.fnamemodify(self.ref.path, ':t')
  else
    return self.ref.name or 'unnamed'
  end
end

---@return string
function UnifiedSource:relativePath()
  if self.type == 'file' and self.ref.path then
    return vim.fn.fnamemodify(self.ref.path, ':~:.')
  else
    return self:identifier():toString()
  end
end

---@return string
function UnifiedSource:absolutePath()
  if self.type == 'file' and self.ref.path then
    return vim.fn.fnamemodify(self.ref.path, ':p')
  else
    error("UnifiedSource: absolutePath() only available for file sources")
  end
end

---@return integer?
function UnifiedSource:reference()
  return self.ref.sourceReference
end

---@return string
function UnifiedSource:origin()
  return self.ref.origin or 'unknown'
end

---Enhanced toString using identifier
---@return string
function UnifiedSource:toString()
  return string.format("UnifiedSource(%s)", self:identifier():toString())
end

---Cleanup when source is destroyed
function UnifiedSource:destroy()
  if self._identifier then
    self.bufferStrategy:cleanup(self._identifier)
  end
end

return UnifiedSource