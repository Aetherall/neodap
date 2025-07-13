-- Public API for virtual buffer management
local VirtualBuffer = {}

VirtualBuffer.Registry = require('neodap.api.VirtualBuffer.Registry')
VirtualBuffer.Manager = require('neodap.api.VirtualBuffer.Manager')
VirtualBuffer.Metadata = require('neodap.api.VirtualBuffer.Metadata')

-- Convenience functions for common operations

---Get statistics about virtual buffers
---@return { total: integer, referenced: integer, unreferenced: integer, invalid: integer, scheduled_cleanup: integer }
function VirtualBuffer.getStats()
  return VirtualBuffer.Manager.getStats()
end

---Clean up unreferenced virtual buffers
---@return integer cleaned_count
function VirtualBuffer.cleanupUnreferenced()
  return VirtualBuffer.Manager.cleanupUnreferenced()
end

---Force cleanup of all virtual buffers (for testing/reset)
function VirtualBuffer.cleanupAll()
  return VirtualBuffer.Manager.cleanupAll()
end

---Get the singleton registry instance
---@return VirtualBufferRegistry
function VirtualBuffer.getRegistry()
  return VirtualBuffer.Registry.get()
end

---Debug: List all virtual buffers
function VirtualBuffer.debugList()
  local registry = VirtualBuffer.getRegistry()
  registry:debugList()
end

return VirtualBuffer