local Class         = require('neodap.tools.class')
local VirtualSource = require('neodap.api.Source.VirtualSource')
local FileSource    = require('neodap.api.Source.FileSource')


---@class api.SourceProps
---@field thread api.Thread
---@field ref dap.Source

---@class api.Source: api.SourceProps
---@field new Constructor<api.SourceProps>
local Source = Class()


---@param thread api.Thread
---@param source dap.Source
function Source.instanciate(thread, source)
  local instance = Source:new({
    thread = thread,
    ref = source,
  })
  return instance
end

---@param checksums dap.Checksum[]
function Source:matchesChecksums(checksums)
  if not self.ref.checksums then
    return false
  end

  if not checksums or #checksums == 0 then
    error("No checksums provided to match against source")
  end

  if #checksums ~= #self.ref.checksums then
    return false
  end

  -- Check if all checksums match
  for _, ref_checksum in ipairs(self.ref.checksums) do
    local found = false
    for _, checksum in ipairs(checksums) do
      if ref_checksum.algorithm == checksum.algorithm and ref_checksum.checksum == checksum.checksum then
        found = true
        break
      end
    end
    if not found then
      return false
    end
  end

  return true
end

function Source:asVirtual()
  if not self.ref.sourceReference or self.ref.sourceReference == 0 then
    return nil
  end

  local response = self.thread.session.ref.calls:source({
    sourceReference = self.ref.sourceReference,
    threadId = self.thread.id,
  }):wait()

  if not response or not response.content then
    return nil
  end

  return VirtualSource.instanciate(self.thread, self)
end

function Source:asFile()
  if not self.ref.path then
    return nil
  end

  return FileSource.instanciate(self.thread, self)
end

---@param other api.Source
function Source:is(other)
  if not other or not other.ref then
    error("Other source must be a valid Source instance")
  end

  if self.ref.sourceReference and other.ref.sourceReference then
    return self.ref.sourceReference == other.ref.sourceReference
  end

  if self.ref.path and other.ref.path then
    return self.ref.path == other.ref.path
  end

  return false
end

---@param other api.Source
function Source:equals(other)
  if not self:is(other) then
    return false
  end

  if not self.ref.checksums and not other.ref.checksums then
    return true
  end

  if not self.ref.checksums or not other.ref.checksums then
    return false
  end

  if not other:matchesChecksums(self.ref.checksums) then
    return false
  end

  return true
end

return Source
