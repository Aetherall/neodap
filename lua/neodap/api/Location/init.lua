local Class = require('neodap.tools.class')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')
local Logger = require('neodap.tools.logger')
local VirtualBufferRegistry = require('neodap.api.VirtualBuffer.Registry')
local VirtualBufferManager = require('neodap.api.VirtualBuffer.Manager')
local VirtualBufferMetadata = require('neodap.api.VirtualBuffer.Metadata')

---@class api.LocationProps
---@field id SourceIdentifier -- Unified source identification
---@field line integer? -- Optional line number (1-based)
---@field column integer? -- Optional column number (1-based)
---@field key string -- Computed unique identifier

---@class api.Location: api.LocationProps
---@field new Constructor<api.LocationProps>
local Location = Class()

---Create location with flexible parameters (unified method)
---@param opts { sourceId: SourceIdentifier, line?: integer, column?: integer }
---@return api.Location
function Location.create(opts)
  
  local key = opts.sourceId:toString()
  
  if opts.line then
    key = key .. ":" .. opts.line
  end

  if opts.column then
    key = key .. ":" .. opts.column
  end

  
  return Location:new({
    id = opts.sourceId,
    line = opts.line,
    column = opts.column,
    key = key
  })
end

---Create location from source object
---@param source api.Source
---@param opts { line?: integer, column?: integer }
---@return api.Location
function Location.fromSource(source, opts)
  return Location.create({
    sourceId = source:identifier(),
    line = opts.line,
    column = opts.column,
  })
end

---Create location from DAP binding
---@param dapBinding dap.Breakpoint
---@return api.Location | nil
function Location.fromDapBinding(dapBinding)
  local identifier = SourceIdentifier.fromDapSource(dapBinding.source)
  
  if not identifier then
    return nil -- Cannot identify this source
  end

  return Location.create({
    sourceId = identifier,
    line = dapBinding.line,
    column = dapBinding.column
  })
end

---Create location from cursor position
---@return api.Location
function Location.fromCursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] or 0
  local column = (cursor[2] or 0) + 1 -- Convert to 1-based index
  local path = vim.api.nvim_buf_get_name(0)

  return Location.create({
    sourceId = SourceIdentifier.fromPath(path),
    line = line,
    column = column
  })
end

---@param opts { line?: integer, column?: integer }
function Location:adjusted(opts)
  local new_line = opts.line or self.line
  local new_column = opts.column or self.column

  if not new_line and not new_column then
    return self -- No adjustment needed
  end

  return Location.create({
    sourceId = self.id,
    line = new_line,
    column = new_column
  })
end

---Get buffer number for this location (passive lookup)
---@return integer?
function Location:bufnr()
  -- Passive lookup only - use manifests(session) for creation
  if self.id:isFile() then
    return self:_getFileBuffer()
  elseif self.id:isVirtual() then
    return self:_getVirtualBuffer()
  end
  return nil
end

---Manifest this location in the physical world (create buffer if needed)
---@param session api.Session Session context for content retrieval and buffer creation
---@return integer? bufnr Buffer number of the manifested location
function Location:manifests(session)
  -- Cross-session buffer management with proper lifecycle
  if self.id:isFile() then
    return self:_getOrCreateFileBuffer()
  elseif self.id:isVirtual() then
    return self:_getOrCreateVirtualBuffer(session)
  end
  return nil
end

---Get URI for buffer operations (concrete addressing)
---@return string
function Location:toUri()
  -- Location handles physical addressing in the material world
  if self.id:isFile() then
    if not self.id.path then
      local log = Logger.get()
      log:error("Location:toUri - File identifier missing path field")
      return ""
    end
    return vim.uri_from_fname(self.id.path)
  else
    return string.format("virtual://%s/%s", 
      self.id.stability_hash, 
      self.id.name
    )
  end
end

-- Private buffer implementation methods

-- Passive lookup methods (no creation)

---Get file buffer (passive lookup only)
---@return integer?
function Location:_getFileBuffer()
  if not self.id.path then
    return nil
  end
  local uri = vim.uri_from_fname(self.id.path)
  local bufnr = vim.uri_to_bufnr(uri)
  return bufnr ~= -1 and bufnr or nil
end

---Get virtual buffer (passive lookup only)
---@return integer?
function Location:_getVirtualBuffer()
  local registry = VirtualBufferRegistry.get()
  
  if not self.id.stability_hash then
    return nil
  end

  -- Try lookup by stability hash first
  local metadata = registry:getBufferByStabilityHash(self.id.stability_hash)
  return metadata and metadata:isValid() and metadata.bufnr or nil
end

-- Active creation methods (for cross-session buffer management)

---Get or create file buffer (active creation)
---@return integer?
function Location:_getOrCreateFileBuffer()
  local log = Logger.get()
  
  if not self.id.path then
    log:error("Location: File identifier missing path field")
    return nil
  end
  
  -- First try passive lookup
  local existing = self:_getFileBuffer()
  if existing then
    return existing
  end
  
  -- Create new file buffer
  local path = vim.fn.fnamemodify(self.id.path, ':p')
  
  if vim.fn.filereadable(path) == 0 then
    log:warn("Location: File not readable:", path)
    return nil
  end
  
  local bufnr = vim.fn.bufnr(path, true)
  
  if bufnr == -1 then
    log:error("Location: Failed to create buffer for:", path)
    return nil
  end
  
  log:debug("Location: Created file buffer", bufnr, "for:", path)
  return bufnr
end

---Get or create virtual buffer (active creation with session context)
---@param session api.Session Session for content retrieval
---@return integer?
function Location:_getOrCreateVirtualBuffer(session)
  local log = Logger.get()
  
  if not self.id:isVirtual() then
    log:error("Location: Cannot create virtual buffer for non-virtual identifier")
    return nil
  end
  
  -- First try passive lookup (cross-session buffer reuse)
  local existing = self:_getVirtualBuffer()
  if existing then
    -- Add session reference for cross-session sharing
    local registry = VirtualBufferRegistry.get()
    registry:addSessionReference(self:toUri(), session.id)
    log:debug("Location: Reusing existing virtual buffer", existing, "for session", session.id)
    return existing
  end
  
  -- Need to create new buffer - get content from session
  local source = session:getSourceByIdentifier(self.id)
  if not source then
    log:error("Location: No source found for virtual buffer creation")
    return nil
  end
  
  local content = source:content()
  if not content then
    log:error("Location: Failed to retrieve content for virtual buffer")
    return nil
  end
  
  -- Create buffer with cross-session persistence
  local registry = VirtualBufferRegistry.get()
  local uri = self:toUri()
  
  -- Detect filetype
  local filetype = VirtualBufferManager.detectFiletype(
    self.id.name or "",
    self.id.origin,
    content
  )
  
  -- Create buffer via manager
  local bufnr = registry.manager:createBuffer(uri, content, filetype)
  
  -- Register in cross-session registry
  local metadata = VirtualBufferMetadata.create({
    uri = uri,
    bufnr = bufnr,
    content_hash = vim.fn.sha256(content),
    stability_hash = self.id.stability_hash,
    referencing_sessions = { [session.id] = true },
    source_info = {
      name = self.id.name,
      origin = self.id.origin,
      sourceReference = source.ref.sourceReference -- Get from current session's source
    }
  })
  
  registry:registerBuffer(uri, metadata)
  
  log:info("Location: Created virtual buffer", bufnr, "for cross-session use:", uri)
  return bufnr
end

---Check if two locations are equal
---@param other api.Location
---@return boolean
function Location:equals(other)
  if not other then
    return false
  end
  
  -- Compare by key for exact equality
  return self.key == other.key
end

---Mark this location in a buffer with an extmark
---@param ns integer
---@param opts vim.api.keyset.set_extmark
---@return integer?
function Location:mark(ns, opts)
  local bufnr = self:bufnr()
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end

  local line = math.max(0, (self.line or 1) - 1)
  local column = math.max(0, (self.column or 1) - 1)
  local bufpos = { line, column }

  -- Check if there is an existing extmark at this location
  local existing_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, bufpos, bufpos, { details = true })
  if #existing_extmarks > 0 then
    -- Update existing extmark
    local id = existing_extmarks[1][1]
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, column, vim.tbl_extend("force", opts, { id = id }))
    return id
  end

  -- Create new extmark
  return vim.api.nvim_buf_set_extmark(bufnr, ns, line, column, opts)
end

---Remove marks for this location from a buffer
---@param ns integer
function Location:unmark(ns)
  local bufnr = self:bufnr()
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local line = math.max(0, (self.line or 1) - 1)
  local column = math.max(0, (self.column or 1) - 1)
  local bufpos = { line, column }

  -- Get all extmarks at this location
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, bufpos, bufpos, { details = true })

  for _, extmark in ipairs(extmarks) do
    local id = extmark[1]
    vim.api.nvim_buf_del_extmark(bufnr, ns, id)
  end
end

return Location