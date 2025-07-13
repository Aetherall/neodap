local Class = require('neodap.tools.class')
local BaseLocation = require('neodap.api.Location.Base')
local nio = require("nio")
local SourceFile = require("neodap.api.Location.SourceFile")

---@class api.SourceFileLineProps: api.BaseLocationProps
---@field path string
---@field line integer

---@class api.SourceFileLine: api.SourceFileLineProps & api.BaseLocationProps
---@field new Constructor<api.SourceFileLineProps>
local SourceFileLine = Class(BaseLocation)


---@param opts { path: string, line: integer }
function SourceFileLine.create(opts)
  return SourceFileLine:new({
    type = 'source_file_line',
    key = opts.path .. ":" .. (opts.line or 0),
    path = opts.path,
    line = opts.line,
  })
end

---NEW: Create with source identifier
---@param opts { source_identifier: SourceIdentifier, line: integer }
function SourceFileLine.createWithIdentifier(opts)
  local key
  if opts.source_identifier.type == 'file' then
    key = opts.source_identifier.path .. ":" .. (opts.line or 0)
  else
    key = opts.source_identifier:toString() .. ":" .. (opts.line or 0)
  end
  
  return SourceFileLine:new({
    type = 'source_file_line',
    key = key,
    source_identifier = opts.source_identifier,
    line = opts.line,
    -- Backward compatibility
    path = opts.source_identifier.type == 'file' and opts.source_identifier.path or nil
  })
end


---@param source api.FileSource
---@param opts { line: integer }
---@return api.SourceFileLine
function SourceFileLine.fromSource(source, opts)
  local path = source:absolutePath()
  return SourceFileLine.create({
    path = path,
    line = opts.line,
  })
end

---@return api.SourceFileLine
function SourceFileLine.fromCursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  if not line then
    error("Cursor position is invalid or not set.")
  end

  local path = vim.api.nvim_buf_get_name(0)

  return SourceFileLine:new({
    type = 'source_file_line',
    key = path .. ":" .. line,
    path = path,
    line = line,
  })
end

---@param other api.Location
---@return_cast other api.SourceFileLine
function SourceFileLine:equals(other)
  return self.key == other.key
end

---@return integer?
function SourceFileLine:bufnr()
  local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(self.path))
  if bufnr == -1 then
    return nil
  end
  return bufnr
end

function SourceFileLine:SourceFile()
  return SourceFile.create({
    path = self.path,
  })
end


return SourceFileLine