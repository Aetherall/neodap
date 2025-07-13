local Class = require('neodap.tools.class')

---@class api.BaseLocationProps
---@field key string
---@field type 'source_file_position' | 'source_file_line' | 'source_file_range' | 'source_file'

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



return BaseLocation