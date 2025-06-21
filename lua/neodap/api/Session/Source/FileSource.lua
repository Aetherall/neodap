local Class = require('neodap.tools.class')
local BaseSource = require('neodap.api.Session.Source.BaseSource')

---@class api.FileSource: api.BaseSource
---@field id string
local FileSource = Class(BaseSource)

---@param session api.Session
---@param source dap.Source
---@return api.FileSource
function FileSource.instanciate(session, source)
  if not source.path or source.path == '' then
    error("Should not be able to instantiate a FileSource without a path")
  end

  local instance = FileSource:new({
    id = BaseSource.dap_identifier(source) or '',
    session = session,
    ref = source,
    _content = nil,
    type = 'file',
  })
  return instance
end

---Create a unique identifier for this source, or nil if unidentifiable
---@return string
function FileSource:identifier()
  return BaseSource.dap_identifier(self.ref) or ''
end

---@return_cast self api.VirtualSource
function FileSource:isVirtual()
  return self.type == 'virtual'
end

---@return_cast self api.FileSource
function FileSource:isFile()
  return self.type == 'file'
end

---@return_cast self api.GenericSource
function FileSource:isGeneric()
  return self.type == 'generic'
end

---@return string
function FileSource:filename()
  return vim.fn.fnamemodify(self.ref.path, ':t')
end

function FileSource:relativePath()
  return vim.fn.fnamemodify(self.ref.path, ':~:.')
end

---@return string
function FileSource:absolutePath()
  return vim.fn.fnamemodify(self.ref.path, ':p')
end

function FileSource:toString()
  return string.format("FileSource(%s)", self:relativePath())
end

return FileSource
