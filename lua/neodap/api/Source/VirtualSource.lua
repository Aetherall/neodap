local Class = require('neodap.tools.class')

---@class api.VirtualSourceProps
---@field type 'virtual'
---@field thread api.Thread
---@field source api.Source
---@field reference integer
---@field origin string

---@class api.VirtualSource: api.VirtualSourceProps
---@field new Constructor<api.VirtualSourceProps>
local VirtualSource = Class()

---@param thread api.Thread
---@param source api.Source
function VirtualSource.instanciate(thread, source)
  if not source.ref.sourceReference or source.ref.sourceReference == 0 then
    error("Should not be able to instantiate a VirtualSource without a sourceReference")
  end
  local instance = VirtualSource:new({
    type = 'virtual',
    thread = thread,
    source = source,
    reference = source.ref.sourceReference,
    origin = source.ref.origin or 'unknown',
  })
  return instance
end

---@param checksums dap.Checksum[]
function VirtualSource:matchesChecksums(checksums)
  return self.source:matchesChecksums(checksums)
end

function VirtualSource:content()
  local response = self.thread.session.ref.calls:source({
    sourceReference = self.reference,
    threadId = self.thread.id,
  }):wait()

  if not response.content then
    return nil
  end

  return response.content
end

---@param other api.Source | api.VirtualSource
function VirtualSource:is(other)
  if other.type == 'virtual' then
    return self.source:is(other.source)
  end

  return self.source:is(other)
end

---@param other api.Source | api.VirtualSource
function VirtualSource:equals(other)
  if other.type == 'virtual' then
    return self.source:equals(other.source)
  end

  return self.source:equals(other)
end

return VirtualSource
