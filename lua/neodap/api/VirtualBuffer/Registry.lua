local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')
local BufferCollection = require('neodap.api.VirtualBuffer.BufferCollection')

---@class VirtualBufferRegistry
---@field private buffers api.BufferCollection -- Enhanced collection with indexing
---@field private manager VirtualBufferManager -- Instance-specific manager
local VirtualBufferRegistry = Class()

-- Singleton instance
VirtualBufferRegistry._instance = nil

---Get the singleton registry instance
---@return VirtualBufferRegistry
function VirtualBufferRegistry.get()
  if not VirtualBufferRegistry._instance then
    local VirtualBufferManager = require('neodap.api.VirtualBuffer.Manager')
    VirtualBufferRegistry._instance = VirtualBufferRegistry:new({
      buffers = BufferCollection.init(),
      manager = VirtualBufferManager.create()
    })
  end
  return VirtualBufferRegistry._instance
end

---Create a new registry instance
---@return VirtualBufferRegistry
function VirtualBufferRegistry.create()
  local VirtualBufferManager = require('neodap.api.VirtualBuffer.Manager')
  local instance = VirtualBufferRegistry:new({
    buffers = BufferCollection.init(),
    manager = VirtualBufferManager.create()
  })
  return instance
end

---Set the singleton instance (for API lifecycle management)
---@param instance VirtualBufferRegistry
function VirtualBufferRegistry.setSingleton(instance)
  VirtualBufferRegistry._instance = instance
end

---Register a new virtual buffer
---@param uri string
---@param metadata VirtualBufferMetadata
function VirtualBufferRegistry:registerBuffer(uri, metadata)
  local log = Logger.get("API:VirtualBuffer")
  log:debug("VirtualBufferRegistry: Registering buffer", uri, "with stability hash", metadata.stability_hash)

  self.buffers:add(metadata)
end

---Get buffer metadata by URI
---@param uri string
---@return VirtualBufferMetadata?
function VirtualBufferRegistry:getBufferByUri(uri)
  return self.buffers:findBy("uri", uri)
end

---Get buffer metadata by stability hash
---@param stability_hash string
---@return VirtualBufferMetadata?
function VirtualBufferRegistry:getBufferByStabilityHash(stability_hash)
  return self.buffers:findBy("stability_hash", stability_hash)
end

---Get all buffers referenced by a session - O(n) fallback since sessions are dynamic
---@param session_id integer
---@return VirtualBufferMetadata[]
function VirtualBufferRegistry:getBuffersBySession(session_id)
  return self.buffers:filter(function(metadata)
    return metadata.referencing_sessions[session_id] == true
  end):toArray()
end

---Add a session reference to a buffer
---@param uri string
---@param session_id integer
function VirtualBufferRegistry:addSessionReference(uri, session_id)
  local log = Logger.get("API:VirtualBuffer")
  local metadata = self.buffers:getByUri(uri)
  if metadata then
    log:debug("VirtualBufferRegistry: Adding session reference", session_id, "to buffer", uri)
    metadata.referencing_sessions[session_id] = true
    metadata:updateAccess()
    -- Rebuild indexes to reflect the session reference change
    self.buffers:refreshIndexes()
  else
    log:warn("VirtualBufferRegistry: Attempted to add session reference to non-existent buffer", uri)
  end
end

---Remove a session reference from a buffer
---@param uri string
---@param session_id integer
function VirtualBufferRegistry:removeSessionReference(uri, session_id)
  local log = Logger.get("API:VirtualBuffer")
  local metadata = self.buffers:getByUri(uri)
  if metadata then
    log:debug("VirtualBufferRegistry: Removing session reference", session_id, "from buffer", uri)
    metadata.referencing_sessions[session_id] = nil
    -- Rebuild indexes to reflect the session reference change
    self.buffers:refreshIndexes()

    -- Schedule cleanup if no sessions reference this buffer
    if not metadata:hasReferences() then
      log:debug("VirtualBufferRegistry: Buffer", uri, "has no more references, scheduling cleanup")
      -- Use instance manager with registry reference
      self.manager:scheduleCleanup(metadata, self)
    end
  else
    log:debug("VirtualBufferRegistry: Attempted to remove session reference from non-existent buffer", uri)
  end
end

---Remove a buffer from the registry (used during cleanup)
---@param uri string
function VirtualBufferRegistry:removeBuffer(uri)
  local log = Logger.get("API:VirtualBuffer")
  if self.buffers:removeByUri(uri) then
    log:debug("VirtualBufferRegistry: Removing buffer from registry", uri)
  end
end

---Get all registered buffer URIs
---@return string[]
function VirtualBufferRegistry:getAllUris()
  return self.buffers:getAllUris()
end

---Get registry statistics - O(1) lookup using pre-computed indexes
---@return { total: integer, referenced: integer, unreferenced: integer, invalid: integer }
function VirtualBufferRegistry:getStats()
  return self.buffers:getStats()
end

---Destroy the registry and clean up all buffers
function VirtualBufferRegistry:destroy()
  local log = Logger.get("API:VirtualBuffer")
  log:debug("VirtualBufferRegistry: Destroying registry and cleaning up all buffers")

  -- Clean up manager first (cancels scheduled cleanups)
  if self.manager and self.manager.destroy then
    self.manager:destroy()
  end

  -- Force delete all buffers
  self.buffers:destroyAllBuffers()
  self.manager = nil
end

---Clear all buffers (for testing or reset)
function VirtualBufferRegistry:clear()
  local log = Logger.get("API:VirtualBuffer")
  log:debug("VirtualBufferRegistry: Clearing all buffers")

  self.buffers:destroyAllBuffers()
end

---Debug: List all buffers
function VirtualBufferRegistry:debugList()
  local log = Logger.get("API:VirtualBuffer")
  log:debug("VirtualBufferRegistry: Current buffers:")

  for metadata in self.buffers:each() do
    log:debug("  ", metadata:toString())
  end
end

return VirtualBufferRegistry
