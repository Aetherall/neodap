local Class = require('neodap.tools.class')
local BaseSource = require('neodap.api.Session.Source.BaseSource')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')
local VirtualBufferRegistry = require('neodap.api.VirtualBuffer.Registry')
local VirtualBufferManager = require('neodap.api.VirtualBuffer.Manager')
local VirtualBufferMetadata = require('neodap.api.VirtualBuffer.Metadata')
local Logger = require('neodap.tools.logger')

---@class api.VirtualSource: api.BaseSource
---@field _identifier SourceIdentifier? -- Cached SourceIdentifier
---@field _uri string? -- Cached URI
local VirtualSource = Class(BaseSource)

---@param session api.Session
---@param source dap.Source
---@return api.VirtualSource
function VirtualSource.instanciate(session, source)
  if not source.sourceReference or source.sourceReference == 0 then
    error("Should not be able to instantiate a VirtualSource without a sourceReference")
  end

  local instance = VirtualSource:new({
    session = session,
    ref = source,
    _content = nil,
    type = 'virtual',
    _identifier = nil, -- Cached SourceIdentifier
    _uri = nil -- Cached URI
  })
  return instance
end

---Get session-independent identifier for this virtual source
---@return VirtualSourceIdentifier
function VirtualSource:identifier()
  if not self._identifier then
    self._identifier = SourceIdentifier.fromDapSource(self.ref, self.session)
  end
  return self._identifier
end

---Get URI for this virtual source
---@return string
function VirtualSource:uri()
  if not self._uri then
    self._uri = self:identifier():toUri()
  end
  return self._uri
end

---Get or create buffer for this virtual source
---@return integer?
function VirtualSource:bufnr()
  local log = Logger.get()
  local registry = VirtualBufferRegistry.get()
  local uri = self:uri()
  local identifier = self:identifier()
  
  log:debug("VirtualSource:bufnr called for", uri)
  
  -- Check if buffer already exists
  local existing = registry:getBufferByUri(uri)
  if existing and existing:isValid() then
    -- Verify content hasn't changed
    local content_hash = self:contentHash()
    if existing.content_hash == content_hash then
      -- Add session reference and return existing buffer
      registry:addSessionReference(uri, self.session.id)
      log:debug("VirtualSource: Reusing existing buffer", existing.bufnr, "for", uri)
      return existing.bufnr
    else
      -- Content changed, need to recreate buffer
      log:warn("VirtualSource: Content changed for", uri, "recreating buffer")
      vim.api.nvim_buf_delete(existing.bufnr, { force = true })
    end
  end
  
  -- Need to create new buffer
  local content = self:content() -- From ContentAccessTrait
  if not content then
    log:error("VirtualSource: Failed to retrieve content for", uri)
    return nil
  end
  
  -- Detect filetype
  local filetype = self:detectFiletype()
  
  -- Create buffer via manager
  local bufnr = VirtualBufferManager.createBuffer(uri, content, filetype)
  
  -- Register in registry
  local metadata = VirtualBufferMetadata.create({
    uri = uri,
    bufnr = bufnr,
    content_hash = self:contentHash(),
    stability_hash = identifier.stability_hash,
    referencing_sessions = { [self.session.id] = true },
    source_info = {
      name = self.ref.name,
      origin = self.ref.origin,
      sourceReference = self.ref.sourceReference
    }
  })
  
  registry:registerBuffer(uri, metadata)
  
  log:info("VirtualSource: Created new buffer", bufnr, "for", uri)
  return bufnr
end

---Calculate content hash for validation
---@return string
function VirtualSource:contentHash()
  local content = self:content()
  if not content then
    return ""
  end
  return vim.fn.sha256(content)
end

---Detect appropriate filetype for this virtual source
---@return string?
function VirtualSource:detectFiletype()
  return VirtualBufferManager.detectFiletype(
    self.ref.name or "",
    self.ref.origin,
    self:content()
  )
end

function VirtualSource:reference()
  return self.ref.sourceReference
end

function VirtualSource:origin()
  return self.ref.origin or 'unknown'
end

function VirtualSource:toString()
  return string.format("VirtualSource(%s, %s)", self:origin(), self:reference())
end

---Cleanup when source is destroyed
function VirtualSource:destroy()
  if self._uri then
    local log = Logger.get()
    log:debug("VirtualSource: Destroying, removing session reference for", self._uri)
    local registry = VirtualBufferRegistry.get()
    registry:removeSessionReference(self._uri, self.session.id)
  end
end

return VirtualSource
