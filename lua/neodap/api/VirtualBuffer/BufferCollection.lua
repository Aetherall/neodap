local Class = require('neodap.tools.class')
local Collection = require("neodap.tools.Collection")

---@class api.BufferCollection: Collection<VirtualBufferMetadata, 'uri' | 'stability_hash' | 'validity' | 'reference_status'>
local BufferCollection = Class(Collection)

---@return api.BufferCollection
function BufferCollection.init()
  local instance = BufferCollection:new({})
  instance:_initialize({
    items = {},
    indexes = {
      uri = {
        indexer = function(metadata) return metadata.uri end,
        unique = true
      },
      stability_hash = {
        indexer = function(metadata) return metadata.stability_hash end,
        unique = true
      },
      validity = {
        indexer = function(metadata) return metadata:isValid() and "valid" or "invalid" end,
        unique = false
      },
      reference_status = {
        indexer = function(metadata) return metadata:hasReferences() and "referenced" or "unreferenced" end,
        unique = false
      }
    }
  })
  return instance
end

---Get buffer metadata by URI - O(1) lookup
---@param uri string
---@return VirtualBufferMetadata?
function BufferCollection:getByUri(uri)
  return self:findBy("uri", uri)
end

---Get buffer metadata by stability hash - O(1) lookup
---@param stability_hash string
---@return VirtualBufferMetadata?
function BufferCollection:getByStabilityHash(stability_hash)
  return self:findBy("stability_hash", stability_hash)
end

---Get all buffers referenced by a session - O(n) fallback since sessions are dynamic
---@param session_id integer
---@return VirtualBufferMetadata[]
function BufferCollection:getBySession(session_id)
  return self:filter(function(metadata)
    return metadata.referencing_sessions[session_id] == true
  end):toArray()
end

---Get all buffer URIs
---@return string[]
function BufferCollection:getAllUris()
  return self:map(function(metadata) return metadata.uri end):toArray()
end

---Get collection statistics using O(1) indexed lookups
---@return { total: integer, referenced: integer, unreferenced: integer, invalid: integer }
function BufferCollection:getStats()
  -- Use O(1) indexed lookups instead of O(n) filtering
  local total = self:count()
  local invalid = self:whereBy("validity", "invalid"):count()
  local valid = self:whereBy("validity", "valid")
  local referenced = valid:whereBy("reference_status", "referenced"):count()
  local unreferenced = valid:whereBy("reference_status", "unreferenced"):count()

  return {
    total = total,
    invalid = invalid,
    referenced = referenced,
    unreferenced = unreferenced
  }
end

---Remove buffer by URI - O(1) lookup + removal
---@param uri string
---@return boolean true if buffer was found and removed
function BufferCollection:removeByUri(uri)
  local metadata = self:findBy("uri", uri)
  if metadata then
    self:remove(metadata)
    return true
  end
  return false
end

---Update indexes after session reference changes
---This is needed because session references are dynamic and affect validity/reference_status
function BufferCollection:refreshIndexes()
  -- Rebuild all indexes to reflect changes in session references
  for name in pairs(self._indexers) do
    self:_buildIndex(name)
  end
end

---Force delete all valid buffers and clear collection
function BufferCollection:destroyAllBuffers()
  for metadata in self:each() do
    if metadata:isValid() then
      vim.api.nvim_buf_delete(metadata.bufnr, { force = true })
    end
  end
  self:clear()
end

return BufferCollection
