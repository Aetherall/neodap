local Class = require('neodap.tools.class')
local BaseSource = require('neodap.api.Session.Source.BaseSource')

---@class api.FileSource: api.BaseSource
---@field id string
---@field _identifier FileSourceIdentifier? -- Cached SourceIdentifier
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
    _identifier = nil -- Cached SourceIdentifier
  })
  return instance
end

---Create a unique identifier for this source
---@return FileSourceIdentifier
function FileSource:identifier()
  if not self._identifier then
    local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')
    self._identifier = SourceIdentifier.fromDapSource(self.ref, self.session)
  end
  return self._identifier
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
