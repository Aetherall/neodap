local Class = require('neodap.tools.class')
local VirtualBufferMetadata = require('neodap.api.VirtualBuffer.Metadata')
local Logger = require('neodap.tools.logger')

---@class VirtualBufferRegistry
---@field private buffers table<string, VirtualBufferMetadata> -- URI -> metadata
---@field private stability_index table<string, string> -- stability_hash -> URI
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
      buffers = {},
      stability_index = {},
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
    buffers = {},
    stability_index = {},
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
  local log = Logger.get()
  log:debug("VirtualBufferRegistry: Registering buffer", uri, "with stability hash", metadata.stability_hash)
  
  self.buffers[uri] = metadata
  self.stability_index[metadata.stability_hash] = uri
end

---Get buffer metadata by URI
---@param uri string
---@return VirtualBufferMetadata?
function VirtualBufferRegistry:getBufferByUri(uri)
  return self.buffers[uri]
end

---Get buffer metadata by stability hash
---@param stability_hash string
---@return VirtualBufferMetadata?
function VirtualBufferRegistry:getBufferByStabilityHash(stability_hash)
  local uri = self.stability_index[stability_hash]
  return uri and self.buffers[uri] or nil
end

---Add a session reference to a buffer
---@param uri string
---@param session_id integer
function VirtualBufferRegistry:addSessionReference(uri, session_id)
  local log = Logger.get()
  local metadata = self.buffers[uri]
  if metadata then
    log:debug("VirtualBufferRegistry: Adding session reference", session_id, "to buffer", uri)
    metadata.referencing_sessions[session_id] = true
    metadata:updateAccess()
  else
    log:warn("VirtualBufferRegistry: Attempted to add session reference to non-existent buffer", uri)
  end
end

---Remove a session reference from a buffer
---@param uri string
---@param session_id integer
function VirtualBufferRegistry:removeSessionReference(uri, session_id)
  local log = Logger.get()
  local metadata = self.buffers[uri]
  if metadata then
    log:debug("VirtualBufferRegistry: Removing session reference", session_id, "from buffer", uri)
    metadata.referencing_sessions[session_id] = nil
    
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
  local log = Logger.get()
  local metadata = self.buffers[uri]
  if metadata then
    log:debug("VirtualBufferRegistry: Removing buffer from registry", uri)
    -- Remove from both indices
    self.buffers[uri] = nil
    self.stability_index[metadata.stability_hash] = nil
  end
end

---Get all registered buffer URIs
---@return string[]
function VirtualBufferRegistry:getAllUris()
  local uris = {}
  for uri, _ in pairs(self.buffers) do
    table.insert(uris, uri)
  end
  return uris
end

---Get registry statistics
---@return { total: integer, referenced: integer, unreferenced: integer, invalid: integer }
function VirtualBufferRegistry:getStats()
  local total = 0
  local referenced = 0
  local unreferenced = 0
  local invalid = 0
  
  for _, metadata in pairs(self.buffers) do
    total = total + 1
    if not metadata:isValid() then
      invalid = invalid + 1
    elseif metadata:hasReferences() then
      referenced = referenced + 1
    else
      unreferenced = unreferenced + 1
    end
  end
  
  return {
    total = total,
    referenced = referenced,
    unreferenced = unreferenced,
    invalid = invalid
  }
end

---Destroy the registry and clean up all buffers
function VirtualBufferRegistry:destroy()
  local log = Logger.get()
  log:debug("VirtualBufferRegistry: Destroying registry and cleaning up all buffers")
  
  -- Clean up manager first (cancels scheduled cleanups)
  if self.manager and self.manager.destroy then
    self.manager:destroy()
  end
  
  -- Force delete all buffers
  for uri, metadata in pairs(self.buffers) do
    if metadata:isValid() then
      vim.api.nvim_buf_delete(metadata.bufnr, { force = true })
    end
  end
  
  self.buffers = {}
  self.stability_index = {}
  self.manager = nil
end

---Clear all buffers (for testing or reset)
function VirtualBufferRegistry:clear()
  local log = Logger.get()
  log:debug("VirtualBufferRegistry: Clearing all buffers")
  
  for uri, metadata in pairs(self.buffers) do
    if metadata:isValid() then
      vim.api.nvim_buf_delete(metadata.bufnr, { force = true })
    end
  end
  
  self.buffers = {}
  self.stability_index = {}
end

---Debug: List all buffers
function VirtualBufferRegistry:debugList()
  local log = Logger.get()
  log:debug("VirtualBufferRegistry: Current buffers:")
  
  for uri, metadata in pairs(self.buffers) do
    log:debug("  ", metadata:toString())
  end
end

return VirtualBufferRegistry