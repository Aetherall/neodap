local Class = require('neodap.tools.class')

---@class api.FileSourceProps
---@field type 'file'
---@field thread api.Thread
---@field source api.Source
---@field path string
---@field name string

---@class api.FileSource: api.FileSourceProps
---@field new Constructor<api.FileSourceProps>
local FileSource = Class()

---@param thread api.Thread
---@param source api.Source
function FileSource.instanciate(thread, source)
  if not source.ref.path or source.ref.path == '' then
    error("Should not be able to instantiate a FileSource without a path")
  end
  local instance = FileSource:new({
    type = 'file',
    thread = thread,
    source = source,
    path = source.ref.path,
    name = source.ref.name or 'unnamed', -- maybe do -> or vim.fn.fnamemodify(source.ref.path, ':t'),
  })
  return instance
end

---@param checksums dap.Checksum[]
function FileSource:matchesChecksums(checksums)
  return self.source:matchesChecksums(checksums)
end

function FileSource:content()
  local response = self.thread.session.ref.calls:source({
    source = { path = self.path, sourceReference = self.source.ref.sourceReference },
    threadId = self.thread.id,
  }):wait()

  if not response.content then
    return nil
  end

  return response.content
end

---@param other api.Source | api.FileSource
function FileSource:is(other)
  if other.type == 'file' then
    return self.source:is(other.source)
  end

  return self.source:is(other)
end

---@param other api.Source | api.FileSource
function FileSource:equals(other)
  if other.type == 'file' then
    return self.source:equals(other.source)
  end

  return self.source:equals(other)
end

function FileSource:filename()
  return vim.fn.fnamemodify(self.path, ':t')
end

---@return string
function FileSource:relativePath()
  return vim.fn.fnamemodify(self.path, ':~:.')
end

return FileSource
