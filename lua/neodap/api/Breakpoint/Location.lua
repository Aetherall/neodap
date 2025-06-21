local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")

---@class api.SourceFileLocationProps
---@field key string
---@field path string
---@field line integer
---@field column? integer

---@class api.VirtualFileLocationProps
---@field key string
---@field identifier string
---@field line integer
---@field column? integer

---@class api.SourceFileLocation: api.SourceFileLocationProps
---@field new Constructor<api.SourceFileLocationProps>
local SourceFileLocation = Class()

---@param source api.FileSource
---@param opts { line: integer, column?: integer }
---@return api.SourceFileLocation
function SourceFileLocation.fromSource(source, opts)
  local path = source:absolutePath()
  return SourceFileLocation:new({
    path = path,
    line = opts.line,
    column = opts.column,
    key = path .. ":" .. (opts.line or 0) .. ":" .. (opts.column or 0),
  })
end

---@param dapBinding dap.Breakpoint
function SourceFileLocation.fromDapBinding(dapBinding)
  if not dapBinding.source or not dapBinding.source.path or not dapBinding.line then
    return nil
  end

  return SourceFileLocation:new({
    path = dapBinding.source.path,
    line = dapBinding.line,
    column = dapBinding.column,
    key = dapBinding.source.path .. ":" .. (dapBinding.line or 0) .. ":" .. (dapBinding.column or 0),
  })
end

function SourceFileLocation.fromCursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local column = cursor[2] + 1 -- Convert to 1-based index
  local path = vim.api.nvim_buf_get_name(0)

  return SourceFileLocation:new({
    path = path,
    line = line,
    column = column,
    key = path .. ":" .. line .. ":" .. column,
  })
end


function SourceFileLocation:matches(other)
  return self.key == other.key
end

function SourceFileLocation:isAtSourceId(sourceId)
  return sourceId  == ("path:".. self.path)
end

---@class api.VirtualFileLocation: api.VirtualFileLocationProps
---@field new Constructor<api.VirtualFileLocationProps>
local VirtualFileLocation = Class()


return {
  SourceFile = SourceFileLocation,
  VirtualFile = VirtualFileLocation,
}