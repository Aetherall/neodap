local Class = require('neodap.tools.class')
local BaseSource = require('neodap.api.Session.Source.BaseSource')

---@class api.GenericSource: api.BaseSource
local GenericSource = Class(BaseSource)

---@param session api.Session
---@param source dap.Source
---@return api.GenericSource
function GenericSource.instanciate(session, source)
  local instance = GenericSource:new({
    session = session,
    ref = source,
    _content = nil,
    type = 'generic',
  })
  return instance
end

function GenericSource:toString()
  local name = self.ref.name or 'unnamed'
  local ref = self.ref.sourceReference or 'no-ref'
  local path = self.ref.path or 'no-path'

  return string.format("GenericSource(%s, ref:%s, path:%s)", name, ref, path)
end

---Override to provide more graceful content access for generic sources
function GenericSource:hasContent()
  -- Generic sources might not be identifiable but could still have content
  -- Be more permissive than base implementation
  return (self.ref.sourceReference and self.ref.sourceReference > 0) or
      (self.ref.path and self.ref.path ~= '') or
      (self.ref.name and self.ref.name ~= '')
end

return GenericSource
