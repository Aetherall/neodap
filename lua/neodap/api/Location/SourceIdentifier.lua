local Class = require('neodap.tools.class')

---@class SourceIdentifier
---@field type 'file' | 'virtual'
local SourceIdentifier = Class()

---@class FileSourceIdentifier: SourceIdentifier
---@field type 'file'
---@field path string -- Absolute file path

---@class VirtualSourceIdentifier: SourceIdentifier  
---@field type 'virtual'
---@field stability_hash string -- Cross-session identifier
---@field origin string -- Semantic origin
---@field name string -- Display name
---@field source_reference integer? -- Optional: for session context
---@field session_id integer? -- Optional: for session context

-- Factory: Create from file path
---@param path string
---@return FileSourceIdentifier
function SourceIdentifier.fromPath(path)
  return SourceIdentifier:new({
    type = 'file',
    path = vim.fn.fnamemodify(path, ':p') -- Ensure absolute
  })
end

-- Factory: Create from DAP source (session-independent)
---@param dap_source dap.Source
---@param session? api.Session
---@return FileSourceIdentifier | VirtualSourceIdentifier
function SourceIdentifier.fromDapSource(dap_source, session)
  if dap_source.path and dap_source.path ~= '' then
    return SourceIdentifier.fromPath(dap_source.path)
  elseif dap_source.sourceReference and dap_source.sourceReference > 0 then
    -- Calculate stability hash without session dependency
    local stability_hash = SourceIdentifier.calculateStabilityHash(dap_source)
    
    return SourceIdentifier:new({
      type = 'virtual',
      stability_hash = stability_hash,
      origin = dap_source.origin or 'unknown',
      name = dap_source.name or 'unnamed',
      -- Optional session context
      source_reference = dap_source.sourceReference,
      session_id = session and session.id
    })
  else
    error("Cannot create SourceIdentifier from source without path or sourceReference")
  end
end

-- Calculate stability hash for virtual sources (session-independent)
---@param dap_source dap.Source
---@return string
function SourceIdentifier.calculateStabilityHash(dap_source)
  local components = {
    dap_source.name or "",
    dap_source.origin or "",
    dap_source.checksums and vim.inspect(dap_source.checksums) or "",
    -- Include related sources for sourcemap stability
    dap_source.sources and vim.inspect(vim.tbl_map(function(s) 
      return s.path or s.name 
    end, dap_source.sources)) or ""
  }
  
  local input = table.concat(components, "|")
  return vim.fn.sha256(input):sub(1, 8)
end

-- Instance methods

---Get string representation of the identifier
---@return string
function SourceIdentifier:toString()
  if self.type == 'file' then
    return "file://" .. self.path
  else
    return string.format("virtual:%s:%s", 
      self.stability_hash,
      self.origin
    )
  end
end

---Check if two identifiers refer to the same source
---@param other SourceIdentifier
---@return boolean
function SourceIdentifier:equals(other)
  if not other or self.type ~= other.type then
    return false
  end
  
  if self.type == 'file' then
    return self.path == other.path
  else
    -- Virtual sources equal if same stability hash
    return self.stability_hash == other.stability_hash
  end
end

---Get URI for buffer operations
---@return string
function SourceIdentifier:toUri()
  if self.type == 'file' then
    return vim.uri_from_fname(self.path)
  else
    -- Generate virtual URI
    local sanitized_name = self:sanitizeName(self.name)
    return string.format("neodap-virtual://%s/%s", 
      self.stability_hash, 
      sanitized_name
    )
  end
end

---Sanitize name for use in URIs
---@param name string
---@return string
function SourceIdentifier:sanitizeName(name)
  -- Replace problematic characters for URIs
  local sanitized = name:gsub("[<>:\"/\\|?*]", "-")
  -- Remove leading/trailing dashes
  sanitized = sanitized:gsub("^%-+", ""):gsub("%-+$", "")
  -- Ensure we have something
  if sanitized == "" then
    sanitized = "unnamed"
  end
  return sanitized
end

---Get buffer number for this source (session-independent lookup)
---@return integer?
function SourceIdentifier:bufnr()
  if self.type == 'file' then
    local uri = vim.uri_from_fname(self.path)
    local bufnr = vim.uri_to_bufnr(uri)
    return bufnr ~= -1 and bufnr or nil
  else
    -- Virtual source buffer lookup via singleton registry
    local VirtualBufferRegistry = require('neodap.api.VirtualBuffer.Registry')
    local registry = VirtualBufferRegistry.get()
    
    -- Try lookup by stability hash first
    local metadata = registry:getBufferByStabilityHash(self.stability_hash)
    return metadata and metadata:isValid() and metadata.bufnr or nil
  end
end

---Check if this identifier represents a file source
---@return boolean
function SourceIdentifier:isFile()
  return self.type == 'file'
end

---Check if this identifier represents a virtual source
---@return boolean
function SourceIdentifier:isVirtual()
  return self.type == 'virtual'
end

---Get display name for UI purposes
---@return string
function SourceIdentifier:getDisplayName()
  if self.type == 'file' then
    return vim.fn.fnamemodify(self.path, ':t') -- Just filename
  else
    return self.name
  end
end

---Get a debug-friendly representation
---@return string
function SourceIdentifier:debug()
  if self.type == 'file' then
    return string.format("FileSource(%s)", self.path)
  else
    return string.format("VirtualSource(%s, %s, ref=%s)", 
      self.stability_hash, 
      self.origin,
      self.source_reference or "none"
    )
  end
end

return SourceIdentifier