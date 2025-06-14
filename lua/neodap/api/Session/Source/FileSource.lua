local Class = require('neodap.tools.class')
local BaseSource = require('neodap.api.Session.Source.BaseSource')

---@class api.FileSource: api.Source
local FileSource = Class(BaseSource)

---@param session api.Session
---@param source dap.Source
---@return api.FileSource
function FileSource.instanciate(session, source)
  if not source.path or source.path == '' then
    error("Should not be able to instantiate a FileSource without a path")
  end

  local instance = FileSource:new({
    session = session,
    ref = source,
    _content = nil,
    type = 'file',
  })
  return instance
end

---@return string
function FileSource:filename()
  return vim.fn.fnamemodify(self.ref.path, ':t')
end

function FileSource:relativePath()
  return vim.fn.fnamemodify(self.ref.path, ':~:.')
end

function FileSource:absolutePath()
  return vim.fn.fnamemodify(self.ref.path, ':p')
end

function FileSource:toString()
  return string.format("FileSource(%s)", self:relativePath())
end

return FileSource
