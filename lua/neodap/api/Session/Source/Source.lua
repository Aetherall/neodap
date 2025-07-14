local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')

-- Additional imports for inlined logic
local nio = require('nio')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')
local VirtualBufferRegistry = require('neodap.api.VirtualBuffer.Registry')
local VirtualBufferManager = require('neodap.api.VirtualBuffer.Manager')
local VirtualBufferMetadata = require('neodap.api.VirtualBuffer.Metadata')

---@class api.SourceProps
---@field type 'file' | 'virtual' | 'generic'
---@field session api.Session
---@field ref dap.Source
---@field _content string | nil
---@field _identifier SourceIdentifier? -- Cached SourceIdentifier
---@field _contentType 'file' | 'virtual' | 'hybrid' -- Content type for direct method dispatch
---@field _identifierType 'path' | 'virtual' | 'hybrid' -- Identifier type for direct method dispatch
---@field _bufferType 'file' | 'virtual' | 'hybrid' -- Buffer type for direct method dispatch

---@class api.Source: api.SourceProps
---@field new Constructor<api.SourceProps>
local Source = Class()

---Create a unified source instance
---@param session api.Session
---@param source dap.Source
---@return api.Source
function Source.instanciate(session, source)
  local log = Logger.get()
  
  -- Determine strategies based on source properties
  local contentType = Source._determineContentType(session, source)
  local identifierType = Source._determineIdentifierType(session, source)
  local bufferType = Source._determineBufferType(session, source)
  
  -- Determine legacy type for backward compatibility
  local legacyType = Source._determineLegacyType(source)
  
  log:debug("Source: Creating with inlined strategies", {
    contentType = contentType,
    identifierType = identifierType,
    bufferType = bufferType,
    legacyType = legacyType
  })
  
  local instance = Source:new({
    session = session,
    ref = source,
    type = legacyType, -- For backward compatibility
    _content = nil,
    _contentType = contentType,
    _identifierType = identifierType,
    _bufferType = bufferType,
    _identifier = nil -- Cached SourceIdentifier
  })
  
  return instance
end

---Determine content type based on source properties
---@param session api.Session
---@param source dap.Source
---@return 'file' | 'virtual' | 'hybrid'
function Source._determineContentType(session, source)
  local hasPath = source.path and source.path ~= ''
  local hasSourceRef = source.sourceReference and source.sourceReference > 0
  
  if hasPath and hasSourceRef then
    return 'hybrid'
  elseif hasPath then
    return 'file'
  elseif hasSourceRef then
    return 'virtual'
  else
    -- Fallback to file type
    return 'file'
  end
end

---Determine identifier type based on source properties
---@param session api.Session
---@param source dap.Source
---@return 'path' | 'virtual' | 'hybrid'
function Source._determineIdentifierType(session, source)
  local hasPath = source.path and source.path ~= ''
  local hasSourceRef = source.sourceReference and source.sourceReference > 0
  
  if hasPath and hasSourceRef then
    return 'hybrid'
  elseif hasPath then
    return 'path'
  elseif hasSourceRef then
    return 'virtual'
  else
    error("Source: Cannot create identifier without path or sourceReference")
  end
end

---Determine buffer type based on source properties
---@param session api.Session
---@param source dap.Source
---@return 'file' | 'virtual' | 'hybrid'
function Source._determineBufferType(session, source)
  local hasPath = source.path and source.path ~= ''
  local hasSourceRef = source.sourceReference and source.sourceReference > 0
  
  if hasPath and hasSourceRef then
    return 'hybrid'
  elseif hasPath then
    return 'file'
  elseif hasSourceRef then
    return 'virtual'
  else
    -- Fallback to file type
    return 'file'
  end
end

---Determine legacy type for backward compatibility
---@param source dap.Source
---@return 'file' | 'virtual' | 'generic'
function Source._determineLegacyType(source)
  -- Use the same logic as the original Source.lua factory
  if source.sourceReference and source.sourceReference > 0 then
    return 'virtual'
  elseif source.path and source.path ~= '' then
    return 'file'
  else
    return 'generic'
  end
end

-- Unified API methods using direct dispatch

---Get session-independent identifier for this source
---@return SourceIdentifier
function Source:identifier()
  if not self._identifier then
    if self._identifierType == 'path' then
      self._identifier = self:_createPathIdentifier()
    elseif self._identifierType == 'virtual' then
      self._identifier = self:_createVirtualIdentifier()
    elseif self._identifierType == 'hybrid' then
      self._identifier = self:_createHybridIdentifier()
    else
      error("Source: Invalid identifier type: " .. tostring(self._identifierType))
    end
  end
  return self._identifier
end

---Get or create buffer for this source
---@return integer?
function Source:bufnr()
  local identifier = self:identifier()
  if self._bufferType == 'file' then
    return self:_getFileBuffer(identifier)
  elseif self._bufferType == 'virtual' then
    return self:_getVirtualBuffer(identifier)
  elseif self._bufferType == 'hybrid' then
    return self:_getHybridBuffer(identifier)
  else
    return nil
  end
end

---Get content for this source
---@return string?
function Source:content()
  if self._contentType == 'file' then
    return self:_getFileContent()
  elseif self._contentType == 'virtual' then
    return self:_getVirtualContent()
  elseif self._contentType == 'hybrid' then
    return self:_getHybridContent()
  else
    return nil
  end
end

---Check if content is available
---@return boolean
function Source:hasContent()
  if self._contentType == 'file' then
    return self:_hasFileContent()
  elseif self._contentType == 'virtual' then
    return self:_hasVirtualContent()
  elseif self._contentType == 'hybrid' then
    return self:_hasHybridContent()
  else
    return false
  end
end

---Get content hash for validation
---@return string
function Source:contentHash()
  if self._contentType == 'file' then
    return self:_getFileContentHash()
  elseif self._contentType == 'virtual' then
    return self:_getVirtualContentHash()
  elseif self._contentType == 'hybrid' then
    return self:_getHybridContentHash()
  else
    return ''
  end
end

-- BaseSource legacy methods for backward compatibility

---Create a unique identifier for this source, or nil if unidentifiable
---@return string | nil
function Source:dap_identifier()
  return Source.dap_identifier(self.ref)
end

---Static function to create dap identifier from source ref
---@param source_ref dap.Source
---@return string | nil
function Source.dap_identifier(source_ref)
  if source_ref.sourceReference and source_ref.sourceReference > 0 then
    return string.format("sourceReference:%d", source_ref.sourceReference)
  elseif source_ref.path and source_ref.path ~= '' then
    return string.format("path:%s", vim.fn.fnamemodify(source_ref.path, ':p'))
  end
  return nil
end

---Check if this source is identifiable
---@return boolean
function Source:isIdentifiable()
  return self:dap_identifier() ~= nil
end

---Check if this source matches a LoadedSource event
---@param loaded_source dap.Source
---@return boolean
function Source:matchesLoadedSource(loaded_source)
  -- Can't match if we're not identifiable
  if not self:isIdentifiable() then
    return false
  end
  
  local our_id = self:dap_identifier()
  local their_id = Source.dap_identifier(loaded_source)
  
  return our_id == their_id
end

---Check if this source matches DAP checksums
---@param checksums dap.Checksum[]
---@return boolean
function Source:matchesChecksums(checksums)
  if not checksums or #checksums == 0 then
    return true
  end
  
  local content = self:content()
  if not content then
    return false
  end
  
  for _, checksum in ipairs(checksums) do
    if checksum.algorithm == 'MD5' then
      if vim.fn.md5(content) == checksum.checksum then
        return true
      end
    elseif checksum.algorithm == 'SHA1' then
      if vim.fn.sha1(content) == checksum.checksum then
        return true
      end
    elseif checksum.algorithm == 'SHA256' then
      if vim.fn.sha256(content) == checksum.checksum then
        return true
      end
    end
  end
  
  return false
end

---Check if this source equals another source
---@param other api.Source
---@return boolean
function Source:is(other)
  return self == other
end

---Check if this source equals another source by identifier
---@param other api.Source
---@return boolean
function Source:equals(other)
  if not self:isIdentifiable() or not other:isIdentifiable() then
    return false
  end
  
  return self:dap_identifier() == other:dap_identifier()
end

---Get string representation
---@return string
function Source:toString()
  return string.format("Source(%s)", self:identifier():toString())
end

-- bufnr method is already defined above with proper dispatch logic

-- Backward compatibility methods

---@return string
function Source:filename()
  if self.type == 'file' and self.ref.path then
    return vim.fn.fnamemodify(self.ref.path, ':t')
  else
    return self.ref.name or 'unnamed'
  end
end

---@return string
function Source:relativePath()
  if self.type == 'file' and self.ref.path then
    return vim.fn.fnamemodify(self.ref.path, ':~:.')
  else
    return self:identifier():toString()
  end
end

---@return string
function Source:absolutePath()
  if self.type == 'file' and self.ref.path then
    return vim.fn.fnamemodify(self.ref.path, ':p')
  else
    return self:identifier():toString()
  end
end

---@return string
function Source:origin()
  return self.ref.origin or 'unknown'
end

---Cleanup when source is destroyed
function Source:destroy()
  if self._identifier then
    if self._bufferType == 'virtual' then
      self:_cleanupVirtualBuffer(self._identifier)
    elseif self._bufferType == 'hybrid' then
      self:_cleanupHybridBuffer(self._identifier)
    end
    -- File buffers don't need cleanup
  end
end

-- Inlined Content Strategy Methods --

---Get file content by reading from filesystem
---@return string?
function Source:_getFileContent()
  local log = Logger.get()
  
  if not self.ref.path or self.ref.path == '' then
    log:warn("FileContent: No path available for content retrieval")
    return nil
  end
  
  local path = vim.fn.fnamemodify(self.ref.path, ':p')
  
  -- Check if file exists
  if vim.fn.filereadable(path) == 0 then
    log:warn("FileContent: File not readable:", path)
    return nil
  end
  
  -- Read file content
  local ok, content = pcall(function()
    local lines = vim.fn.readfile(path)
    return table.concat(lines, '\n')
  end)
  
  if not ok then
    log:error("FileContent: Failed to read file:", path, content)
    return nil
  end
  
  log:debug("FileContent: Successfully read file content:", path)
  return content
end

---Check if file content is available
---@return boolean
function Source:_hasFileContent()
  if not self.ref.path or self.ref.path == '' then
    return false
  end
  
  local path = vim.fn.fnamemodify(self.ref.path, ':p')
  return vim.fn.filereadable(path) == 1
end

---Get file content hash
---@return string
function Source:_getFileContentHash()
  local content = self:_getFileContent()
  if not content then
    return ''
  end
  return vim.fn.sha256(content)
end

---Get virtual content via DAP source request
---@return string?
function Source:_getVirtualContent()
  local log = Logger.get()
  
  if not self.ref.sourceReference or self.ref.sourceReference <= 0 then
    log:warn("VirtualContent: No sourceReference available for content retrieval")
    return nil
  end
  
  log:debug("VirtualContent: Requesting content for sourceReference:", self.ref.sourceReference)
  
  -- Make DAP source request
  local ok, result = pcall(function()
    return self.session.ref.calls:source({
      source = self.ref,
      sourceReference = self.ref.sourceReference
    }):wait()
  end)
  
  if not ok then
    log:error("VirtualContent: DAP source request failed:", result)
    return nil
  end
  
  if not result or not result.content then
    log:warn("VirtualContent: DAP returned no content for sourceReference:", self.ref.sourceReference)
    return nil
  end
  
  log:debug("VirtualContent: Successfully retrieved content via DAP")
  return result.content
end

---Check if virtual content is available
---@return boolean
function Source:_hasVirtualContent()
  return self.ref.sourceReference and self.ref.sourceReference > 0
end

---Get virtual content hash
---@return string
function Source:_getVirtualContentHash()
  local content = self:_getVirtualContent()
  if not content then
    return ''
  end
  return vim.fn.sha256(content)
end

---Get hybrid content (try DAP first, then file)
---@return string?
function Source:_getHybridContent()
  local log = Logger.get()

  log:debug("HybridContent: Attempting DAP content first")

  -- Try DAP content first
  if self:_hasVirtualContent() then
    local content = self:_getVirtualContent()
    if content then
      log:debug("HybridContent: Using DAP content")
      return content
    end
  end

  log:debug("HybridContent: Falling back to file content")

  -- Fallback to file content
  if self:_hasFileContent() then
    local content = self:_getFileContent()
    if content then
      log:debug("HybridContent: Using file content")
      return content
    end
  end
  
  log:warn("HybridContent: No content available from either strategy")
  return nil
end

---Check if hybrid content is available
---@return boolean
function Source:_hasHybridContent()
  return self:_hasVirtualContent() or self:_hasFileContent()
end

---Get hybrid content hash (prefer virtual for consistency)
---@return string
function Source:_getHybridContentHash()
  -- Prefer virtual content hash for consistency across sessions
  if self:_hasVirtualContent() then
    return self:_getVirtualContentHash()
  end
  return self:_getFileContentHash()
end

-- Inlined Identifier Strategy Methods --

---Create a path-based identifier
---@return SourceIdentifier
function Source:_createPathIdentifier()
  if not self.ref.path or self.ref.path == '' then
    error("PathIdentifier: Cannot create identifier without source path")
  end
  
  return SourceIdentifier.fromPath(self.ref.path)
end

---Create a virtual identifier using stability hash
---@return SourceIdentifier
function Source:_createVirtualIdentifier()
  if not self.ref.sourceReference or self.ref.sourceReference <= 0 then
    error("VirtualIdentifier: Cannot create identifier without sourceReference")
  end
  
  return SourceIdentifier.fromDapSource(self.ref, self.session)
end

---Create a hybrid identifier (prefer virtual for stability)
---@return SourceIdentifier
function Source:_createHybridIdentifier()
  local log = Logger.get()
  
  -- Prefer Virtual identifier (more stable across sessions)
  if self.ref.sourceReference and self.ref.sourceReference > 0 then
    log:debug("HybridIdentifier: Using virtual identifier")
    return self:_createVirtualIdentifier()
  end
  
  -- Fallback to path identifier
  if self.ref.path and self.ref.path ~= '' then
    log:debug("HybridIdentifier: Using path-based identifier")
    return self:_createPathIdentifier()
  end
  
  error("HybridIdentifier: No viable identifier strategy available")
end

-- Inlined Buffer Strategy Methods --

---Get or create file buffer using Neovim's file buffer management
---@param identifier SourceIdentifier
---@return integer?
function Source:_getFileBuffer(identifier)
  local log = Logger.get()
  
  if not identifier:isFile() then
    log:error("FileBuffer: Cannot handle non-file identifier")
    return nil
  end
  
  if not self.ref.path or self.ref.path == '' then
    log:warn("FileBuffer: No path available for buffer creation")
    return nil
  end
  
  local path = vim.fn.fnamemodify(self.ref.path, ':p')
  local uri = vim.uri_from_fname(path)
  local bufnr = vim.uri_to_bufnr(uri)
  
  if bufnr == -1 then
    log:debug("FileBuffer: No existing buffer, creating new buffer for:", path)
    
    -- Check if file exists before creating buffer
    if vim.fn.filereadable(path) == 0 then
      log:warn("FileBuffer: File not readable, cannot create buffer:", path)
      return nil
    end
    
    -- Create buffer for the file
    bufnr = vim.fn.bufnr(path, true)
    
    if bufnr == -1 then
      log:error("FileBuffer: Failed to create buffer for:", path)
      return nil
    end
    
    log:debug("FileBuffer: Created buffer", bufnr, "for file:", path)
  else
    log:debug("FileBuffer: Using existing buffer", bufnr, "for file:", path)
  end
  
  return bufnr
end

---Get or create virtual buffer using neodap's VirtualBuffer system
---@param identifier SourceIdentifier
---@return integer?
function Source:_getVirtualBuffer(identifier)
  local log = Logger.get()
  
  if not identifier:isVirtual() then
    log:error("VirtualBuffer: Cannot handle non-virtual identifier")
    return nil
  end
  
  local registry = self.session.api._virtual_buffer_registry
  local uri = identifier:toUri()
  
  log:debug("VirtualBuffer: Getting buffer for URI:", uri)
  
  -- Check if buffer already exists
  local existing = registry:getBufferByUri(uri)
  if existing and existing:isValid() then
    -- Verify content hasn't changed
    local content_hash = self:contentHash()
    if existing.content_hash == content_hash then
      -- Add session reference and return existing buffer
      registry:addSessionReference(uri, self.session.id)
      log:debug("VirtualBuffer: Reusing existing buffer", existing.bufnr, "for:", uri)
      return existing.bufnr
    else
      -- Content changed, need to recreate buffer
      log:warn("VirtualBuffer: Content changed for", uri, "recreating buffer")
      vim.api.nvim_buf_delete(existing.bufnr, { force = true })
    end
  end
  
  -- Need to create new buffer
  local content = self:content()
  if not content then
    log:error("VirtualBuffer: Failed to retrieve content for:", uri)
    return nil
  end
  
  -- Detect filetype
  local filetype = self:_detectVirtualFiletype()
  
  -- Create buffer via manager
  local bufnr = registry.manager:createBuffer(uri, content, filetype)
  
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
  
  log:info("VirtualBuffer: Created new buffer", bufnr, "for:", uri)
  return bufnr
end

---Get hybrid buffer (prefer virtual for better DAP integration)
---@param identifier SourceIdentifier
---@return integer?
function Source:_getHybridBuffer(identifier)
  local log = Logger.get()

  -- Prefer virtual buffer (better integration with DAP)
  if self.ref.sourceReference and self.ref.sourceReference > 0 then
    log:debug("HybridBuffer: Using virtual buffer strategy")
    return self:_getVirtualBuffer(identifier)
  end

  log:warn("HybridBuffer: No viable buffer strategy available")
  return nil
end

---Detect appropriate filetype for virtual source
---@return string?
function Source:_detectVirtualFiletype()
  return VirtualBufferManager.detectFiletype(
    self.ref.name or "",
    self.ref.origin,
    self:content()
  )
end

---Cleanup virtual buffer when source is destroyed
---@param identifier SourceIdentifier
function Source:_cleanupVirtualBuffer(identifier)
  if identifier:isVirtual() then
    local log = Logger.get()
    local uri = identifier:toUri()
    log:debug("VirtualBuffer: Cleaning up, removing session reference for:", uri)
    local registry = self.session.api._virtual_buffer_registry
    registry:removeSessionReference(uri, self.session.id)
  end
end

---Cleanup hybrid buffer when source is destroyed
---@param identifier SourceIdentifier
function Source:_cleanupHybridBuffer(identifier)
  if identifier:isFile() then
    -- File buffers don't need cleanup
    return
  elseif identifier:isVirtual() then
    self:_cleanupVirtualBuffer(identifier)
  end
end

return Source