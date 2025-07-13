local Class = require('neodap.tools.class')
local BufferStrategy = require('neodap.api.Session.Source.strategies.BufferStrategy')
local VirtualBufferRegistry = require('neodap.api.VirtualBuffer.Registry')
local VirtualBufferManager = require('neodap.api.VirtualBuffer.Manager')
local VirtualBufferMetadata = require('neodap.api.VirtualBuffer.Metadata')
local Logger = require('neodap.tools.logger')

---@class VirtualBufferStrategy: BufferStrategy
local VirtualBufferStrategy = Class(BufferStrategy)

---Create a virtual buffer strategy instance
---@param session api.Session
---@param source dap.Source
---@return VirtualBufferStrategy
function VirtualBufferStrategy.create(session, source)
  return VirtualBufferStrategy:new({
    session = session,
    source = source
  })
end

---Get or create buffer using neodap's VirtualBuffer system
---@param identifier SourceIdentifier
---@param contentStrategy ContentStrategy
---@return integer? bufnr
function VirtualBufferStrategy:getBuffer(identifier, contentStrategy)
  local log = Logger.get()
  
  if not identifier:isVirtual() then
    log:error("VirtualBufferStrategy: Cannot handle non-virtual identifier")
    return nil
  end
  
  local registry = self.session.api._virtual_buffer_registry
  local uri = identifier:toUri()
  
  log:debug("VirtualBufferStrategy: Getting buffer for URI:", uri)
  
  -- Check if buffer already exists
  local existing = registry:getBufferByUri(uri)
  if existing and existing:isValid() then
    -- Verify content hasn't changed
    local content_hash = contentStrategy:getContentHash()
    if existing.content_hash == content_hash then
      -- Add session reference and return existing buffer
      registry:addSessionReference(uri, self.session.id)
      log:debug("VirtualBufferStrategy: Reusing existing buffer", existing.bufnr, "for:", uri)
      return existing.bufnr
    else
      -- Content changed, need to recreate buffer
      log:warn("VirtualBufferStrategy: Content changed for", uri, "recreating buffer")
      vim.api.nvim_buf_delete(existing.bufnr, { force = true })
    end
  end
  
  -- Need to create new buffer
  local content = contentStrategy:getContent()
  if not content then
    log:error("VirtualBufferStrategy: Failed to retrieve content for:", uri)
    return nil
  end
  
  -- Detect filetype
  local filetype = self:detectFiletype(contentStrategy)
  
  -- Create buffer via manager
  local bufnr = registry.manager:createBuffer(uri, content, filetype)
  
  -- Register in registry
  local metadata = VirtualBufferMetadata.create({
    uri = uri,
    bufnr = bufnr,
    content_hash = contentStrategy:getContentHash(),
    stability_hash = identifier.stability_hash,
    referencing_sessions = { [self.session.id] = true },
    source_info = {
      name = self.source.name,
      origin = self.source.origin,
      sourceReference = self.source.sourceReference
    }
  })
  
  registry:registerBuffer(uri, metadata)
  
  log:info("VirtualBufferStrategy: Created new buffer", bufnr, "for:", uri)
  return bufnr
end

---Virtual buffer management is available if we have a sourceReference
---@return boolean
function VirtualBufferStrategy:canManageBuffer()
  return self.source.sourceReference and self.source.sourceReference > 0
end

---Detect appropriate filetype for this virtual source
---@param contentStrategy ContentStrategy
---@return string?
function VirtualBufferStrategy:detectFiletype(contentStrategy)
  return VirtualBufferManager.detectFiletype(
    self.source.name or "",
    self.source.origin,
    contentStrategy:getContent()
  )
end

---Cleanup when source is destroyed
---@param identifier SourceIdentifier
function VirtualBufferStrategy:cleanup(identifier)
  if identifier:isVirtual() then
    local log = Logger.get()
    local uri = identifier:toUri()
    log:debug("VirtualBufferStrategy: Cleaning up, removing session reference for:", uri)
    local registry = self.session.api._virtual_buffer_registry
    registry:removeSessionReference(uri, self.session.id)
  end
end

return VirtualBufferStrategy