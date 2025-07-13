local Class = require('neodap.tools.class')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')

---@class api.BaseLocationProps
---@field key string
---@field type 'source_file_position' | 'source_file_line' | 'source_file_range' | 'source_file'
---@field source_identifier SourceIdentifier -- NEW: Unified source identification
---@field path string? -- DEPRECATED: Kept for backward compatibility
---@field line integer?
---@field column integer?

---@class api.BaseLocation: api.BaseLocationProps
---@field new Constructor<api.BaseLocationProps>
local BaseLocation = Class()

---@return_cast self api.SourceFilePosition
function BaseLocation:isSourceFilePosition()
  return self.type == 'source_file_position'
end

---@return api.SourceFilePosition?
function BaseLocation:asSourceFilePosition()
  if not self:isSourceFilePosition() then
    return nil
  end
  ---@cast self api.SourceFilePosition
  return self
end

---@return_cast self api.SourceFileLine
function BaseLocation:isSourceFileLine()
  return self.type == 'source_file_line'
end

---@return api.SourceFileLine?
function BaseLocation:asSourceFileLine()
  if not self:isSourceFileLine() then
    return nil
  end
  ---@cast self api.SourceFileLine
  return self
end

---@return_cast self api.SourceFile
function BaseLocation:isSourceFile()
  return self.type == 'source_file'
end

---@return api.SourceFile?
function BaseLocation:asSourceFile()
  if not self:isSourceFile() then
    return nil
  end
  ---@cast self api.SourceFile
  return self
end

-- NEW: Source identifier support

---Get the source identifier for this location
---@return SourceIdentifier
function BaseLocation:getSourceIdentifier()
  -- Lazy migration from path to source_identifier
  if not self.source_identifier and self.path then
    self.source_identifier = SourceIdentifier.fromPath(self.path)
  end
  return self.source_identifier
end

---Get buffer number for this location (delegates to source identifier)
---@return integer?
function BaseLocation:bufnr()
  local identifier = self:getSourceIdentifier()
  return identifier:bufnr()
end

---Check if this location represents a file source
---@return boolean
function BaseLocation:isFileSource()
  local identifier = self:getSourceIdentifier()
  return identifier.type == 'file'
end

---Check if this location represents a virtual source
---@return boolean
function BaseLocation:isVirtualSource()
  local identifier = self:getSourceIdentifier()
  return identifier.type == 'virtual'
end

---Get display name for this location's source
---@return string
function BaseLocation:getSourceDisplayName()
  local identifier = self:getSourceIdentifier()
  return identifier:getDisplayName()
end

---Get debug string for this location
---@return string
function BaseLocation:debug()
  local identifier = self:getSourceIdentifier()
  return string.format("%s at %s", self.type, identifier:debug())
end

return BaseLocation