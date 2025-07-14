local Class = require('neodap.tools.class')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')

---@class api.LocationProps
---@field source_identifier SourceIdentifier -- Unified source identification
---@field line integer? -- Optional line number (1-based)
---@field column integer? -- Optional column number (1-based)
---@field key string -- Computed unique identifier
---@field path string? -- DEPRECATED: Kept for backward compatibility

---@class api.Location: api.LocationProps
---@field new Constructor<api.LocationProps>
local Location = Class()

-- Private: Compute key for location identity
---@return string
function Location:_computeKey()
  local base = self.source_identifier:toString()
  if self.line and self.column then
    return base .. ":" .. self.line .. ":" .. self.column
  elseif self.line then
    return base .. ":" .. self.line
  else
    return base
  end
end

-- Factory Methods

---Create location with flexible parameters (unified method)
---@param opts { path?: string, source_identifier?: SourceIdentifier, line?: integer, column?: integer }
---@return api.Location
function Location.create(opts)
  if not opts.path and not opts.source_identifier then
    error("Location.create requires either 'path' or 'source_identifier'")
  end
  
  local source_identifier = opts.source_identifier
  if not source_identifier then
    source_identifier = SourceIdentifier.fromPath(opts.path)
  end
  
  local instance = Location:new({
    source_identifier = source_identifier,
    line = opts.line,
    column = opts.column,
  })
  
  -- Compute key after creation
  instance.key = instance:_computeKey()
  
  return instance
end

---Create with source identifier (modern preferred method)
---@param opts { source_identifier: SourceIdentifier, line?: integer, column?: integer }
---@return api.Location
function Location.createWithIdentifier(opts)
  return Location.create(opts)
end

---Create location from source object
---@param source api.Source
---@param opts { line?: integer, column?: integer }
---@return api.Location
function Location.fromSource(source, opts)
  local identifier = source:identifier()
  return Location.createWithIdentifier({
    source_identifier = identifier,
    line = opts.line,
    column = opts.column
  })
end

---Create location from DAP binding
---@param dapBinding dap.Breakpoint
---@return api.Location | nil
function Location.fromDapBinding(dapBinding)
  if not dapBinding.source then
    return nil
  end
  
  -- Create source identifier from DAP source
  local success, identifier = pcall(SourceIdentifier.fromDapSource, dapBinding.source)
  if not success then
    return nil -- Cannot identify this source
  end
  
  return Location.createWithIdentifier({
    source_identifier = identifier,
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

  -- Check if this is a virtual buffer
  if path:match("^virtual://") then
    local identifier = SourceIdentifier.fromVirtualUri(path)
    return Location.createWithIdentifier({
      source_identifier = identifier,
      line = line,
      column = column
    })
  end

  -- Regular file buffer
  local identifier = SourceIdentifier.fromPath(path)
  return Location.createWithIdentifier({
    source_identifier = identifier,
    line = line,
    column = column
  })
end

-- Instance Methods

---Get the source identifier for this location
---@return SourceIdentifier
function Location:getSourceIdentifier()
  -- Lazy migration from path to source_identifier (backward compatibility)
  if not self.source_identifier and self.path then
    self.source_identifier = SourceIdentifier.fromPath(self.path)
  end
  return self.source_identifier
end

---@param opts { line?: integer, column?: integer }
function Location:adjusted(opts)
  local new_line = opts.line or self.line
  local new_column = opts.column or self.column

  if not new_line and not new_column then
    return self -- No adjustment needed
  end

  return Location.createWithIdentifier({
    source_identifier = self.source_identifier,
    line = new_line,
    column = new_column
  })
end
---Get buffer number for this location
---@return integer?
function Location:bufnr()
  local identifier = self:getSourceIdentifier()
  return identifier:bufnr()
end

---Check if this location represents a file source
---@return boolean
function Location:isFileSource()
  local identifier = self:getSourceIdentifier()
  return identifier.type == 'file'
end

---Check if this location represents a virtual source
---@return boolean
function Location:isVirtualSource()
  local identifier = self:getSourceIdentifier()
  return identifier.type == 'virtual'
end

---Get display name for this location's source
---@return string
function Location:getSourceDisplayName()
  local identifier = self:getSourceIdentifier()
  return identifier:getDisplayName()
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

---Get debug string for this location
---@return string
function Location:debug()
  local identifier = self:getSourceIdentifier()
  local coords = ""
  if self.line and self.column then
    coords = string.format(" (%d:%d)", self.line, self.column)
  elseif self.line then
    coords = string.format(" (%d)", self.line)
  end
  return string.format("Location[%s%s]", identifier:debug(), coords)
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

-- Backward Compatibility Type Checking (deprecated but preserved)

---@deprecated Use unified Location instead
---@return boolean
function Location:isSourceFilePosition()
  return self.line ~= nil and self.column ~= nil
end

---@deprecated Use unified Location instead
---@return boolean  
function Location:isSourceFileLine()
  return self.line ~= nil and self.column == nil
end

---@deprecated Use unified Location instead
---@return boolean
function Location:isSourceFile()
  return self.line == nil and self.column == nil
end

---@deprecated Use unified Location instead
---@return api.Location?
function Location:asSourceFilePosition()
  return self:isSourceFilePosition() and self or nil
end

---@deprecated Use unified Location instead
---@return api.Location?
function Location:asSourceFileLine()
  return self:isSourceFileLine() and self or nil
end

---@deprecated Use unified Location instead
---@return api.Location?
function Location:asSourceFile()
  return self:isSourceFile() and self or nil
end

return Location