local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')
local nio = require('nio')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')
local VirtualBufferManager = require('neodap.api.VirtualBuffer.Manager')
local VirtualBufferMetadata = require('neodap.api.VirtualBuffer.Metadata')

---@class api.SourceProps
---@field session api.Session
---@field ref dap.Source
---@field _identifier SourceIdentifier? -- Cached SourceIdentifier
---@field _content string? -- Cached content

---@class api.Source: api.SourceProps
---@field new Constructor<api.SourceProps>
local Source = Class()

---Create a source instance
---@param session api.Session
---@param source dap.Source
---@return api.Source
function Source.instanciate(session, source)
  local instance = Source:new({
    session = session,
    ref = source,
    _identifier = nil, -- Lazy-loaded
    _content = nil     -- Lazy-loaded
  })
  return instance
end

-- Core Type Checking Methods

---Check if this is a virtual source (has sourceReference > 0)
---@return boolean
function Source:isVirtual()
  return self.ref.sourceReference and self.ref.sourceReference > 0
end

---Check if this is a file source (no sourceReference, has path)
---@return boolean
function Source:isFile()
  return not self:isVirtual() and self.ref.path and self.ref.path ~= ''
end


-- Core Consumer Methods

---Get session-independent identifier for this source
---@return SourceIdentifier
function Source:identifier()
  if not self._identifier then
    if self:isVirtual() then
      self._identifier = SourceIdentifier.fromDapSource(self.ref, self.session)
    elseif self:isFile() then
      self._identifier = SourceIdentifier.fromPath(self.ref.path)
    else
      error("Source: Cannot create identifier without path or sourceReference")
    end
  end
  return self._identifier
end

---Get or create buffer for this source
---@return integer?
function Source:bufnr()
  if self:isVirtual() then
    return self:_getVirtualBuffer()
  elseif self:isFile() then
    return self:_getFileBuffer()
  end
  return nil
end

---Get filename for display
---@return string
function Source:filename()
  if self:isFile() and self.ref.path then
    return vim.fn.fnamemodify(self.ref.path, ':t')
  else
    return self.ref.name or 'unnamed'
  end
end

---Get string representation
---@return string
function Source:toString()
  return string.format("Source(%s)", self:identifier():toString())
end

-- Content Access (Internal Use)

---Get content for this source
---@return string?
function Source:content()
  if self._content then
    return self._content
  end
  
  if self:isVirtual() then
    self._content = self:_getDapContent()
  elseif self:isFile() then
    self._content = self:_getFileContent()
  end
  
  return self._content
end

-- Legacy DAP Methods (for backward compatibility)

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

---Cleanup when source is destroyed
function Source:destroy()
  if self._identifier and self:isVirtual() then
    local log = Logger.get()
    local Location = require('neodap.api.Location')
    local location = Location.create({ sourceId = self._identifier })
    local uri = location:toUri()
    log:debug("Source: Cleaning up virtual buffer for:", uri)
    local registry = self.session.api._virtual_buffer_registry
    registry:removeSessionReference(uri, self.session.id)
  end
end

-- Private Implementation Methods

---Get file content by reading from filesystem
---@return string?
function Source:_getFileContent()
  local log = Logger.get()
  
  if not self.ref.path or self.ref.path == '' then
    log:warn("Source: No path available for file content")
    return nil
  end
  
  local path = vim.fn.fnamemodify(self.ref.path, ':p')
  
  if vim.fn.filereadable(path) == 0 then
    log:warn("Source: File not readable:", path)
    return nil
  end
  
  local ok, content = pcall(function()
    local lines = vim.fn.readfile(path)
    return table.concat(lines, '\n')
  end)
  
  if not ok then
    log:error("Source: Failed to read file:", path, content)
    return nil
  end
  
  return content
end

---Get virtual content via DAP source request
---@return string?
function Source:_getDapContent()
  local log = Logger.get()
  
  if not self.ref.sourceReference or self.ref.sourceReference <= 0 then
    log:warn("Source: No sourceReference for DAP content")
    return nil
  end
  
  log:debug("Source: Requesting DAP content for sourceReference:", self.ref.sourceReference)
  
  local ok, result = pcall(function()
    return self.session.ref.calls:source({
      source = self.ref,
      sourceReference = self.ref.sourceReference
    }):wait()
  end)
  
  if not ok then
    log:error("Source: DAP source request failed:", result)
    return nil
  end
  
  if not result or not result.content then
    log:warn("Source: DAP returned no content for sourceReference:", self.ref.sourceReference)
    return nil
  end
  
  return result.content
end

---Get or create file buffer
---@return integer?
function Source:_getFileBuffer()
  local log = Logger.get()
  
  if not self.ref.path or self.ref.path == '' then
    log:warn("Source: No path for file buffer")
    return nil
  end
  
  local path = vim.fn.fnamemodify(self.ref.path, ':p')
  local uri = vim.uri_from_fname(path)
  local bufnr = vim.uri_to_bufnr(uri)
  
  if bufnr == -1 then
    log:debug("Source: Creating file buffer for:", path)
    
    if vim.fn.filereadable(path) == 0 then
      log:warn("Source: File not readable:", path)
      return nil
    end
    
    bufnr = vim.fn.bufnr(path, true)
    
    if bufnr == -1 then
      log:error("Source: Failed to create buffer for:", path)
      return nil
    end
  end
  
  return bufnr
end

---Get or create virtual buffer
---@return integer?
function Source:_getVirtualBuffer()
  local log = Logger.get()
  local identifier = self:identifier()
  
  if not identifier:isVirtual() then
    log:error("Source: Cannot create virtual buffer for non-virtual source")
    return nil
  end
  
  local registry = self.session.api._virtual_buffer_registry
  local Location = require('neodap.api.Location')
  local location = Location.create({ sourceId = identifier })
  local uri = location:toUri()
  
  log:debug("Source: Getting virtual buffer for URI:", uri)
  
  -- Check if buffer already exists
  local existing = registry:getBufferByUri(uri)
  if existing and existing:isValid() then
    -- Add session reference and return existing buffer
    registry:addSessionReference(uri, self.session.id)
    log:debug("Source: Reusing existing buffer", existing.bufnr)
    return existing.bufnr
  end
  
  -- Need to create new buffer
  local content = self:content()
  if not content then
    log:error("Source: Failed to retrieve content for virtual buffer")
    return nil
  end
  
  -- Detect filetype
  local filetype = VirtualBufferManager.detectFiletype(
    self.ref.name or "",
    self.ref.origin,
    content
  )
  
  -- Create buffer via manager
  local bufnr = registry.manager:createBuffer(uri, content, filetype)
  
  -- Register in registry
  local metadata = VirtualBufferMetadata.create({
    uri = uri,
    bufnr = bufnr,
    content_hash = vim.fn.sha256(content),
    stability_hash = identifier.stability_hash,
    referencing_sessions = { [self.session.id] = true },
    source_info = {
      name = self.ref.name,
      origin = self.ref.origin,
      sourceReference = self.ref.sourceReference
    }
  })
  
  registry:registerBuffer(uri, metadata)
  
  log:info("Source: Created virtual buffer", bufnr, "for:", uri)
  return bufnr
end

return Source