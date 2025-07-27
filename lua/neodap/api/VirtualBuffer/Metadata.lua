local Class = require('neodap.tools.class')

---@class VirtualBufferMetadataProps
---@field uri string -- neodap-virtual://hash/name
---@field bufnr integer -- Neovim buffer number
---@field content_hash string -- SHA256 of content for validation
---@field stability_hash string -- Cross-session identifier
---@field referencing_sessions table<integer, boolean> -- Session IDs using this buffer
---@field last_accessed number -- Timestamp for cleanup decisions
---@field source_info table -- Original DAP source info for debugging

---@class VirtualBufferMetadata: VirtualBufferMetadataProps
---@field new Constructor<VirtualBufferMetadataProps>
local VirtualBufferMetadata = Class()

---@param opts { uri: string, bufnr: integer, content_hash: string, stability_hash: string, referencing_sessions?: table<integer, boolean>, source_info?: table }
---@return VirtualBufferMetadata
function VirtualBufferMetadata.create(opts)
  return VirtualBufferMetadata:new({
    uri = opts.uri,
    bufnr = opts.bufnr,
    content_hash = opts.content_hash,
    stability_hash = opts.stability_hash,
    referencing_sessions = opts.referencing_sessions or {},
    last_accessed = os.time(),
    source_info = opts.source_info or {}
  })
end

---Check if the buffer is still valid in Neovim
---@return boolean
function VirtualBufferMetadata:isValid()
  return self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr)
end

---Check if any sessions are referencing this buffer
---@return boolean
function VirtualBufferMetadata:hasReferences()
  return next(self.referencing_sessions) ~= nil
end

---Get the number of sessions referencing this buffer
---@return integer
function VirtualBufferMetadata:getSessionCount()
  local count = 0
  for _ in pairs(self.referencing_sessions) do
    count = count + 1
  end
  return count
end

---Update the last accessed timestamp
function VirtualBufferMetadata:updateAccess()
  self.last_accessed = os.time()
end

---Get a debug string representation
---@return string
function VirtualBufferMetadata:toString()
  return string.format("VirtualBuffer(%s, bufnr=%d, sessions=%d)",
    self.stability_hash,
    self.bufnr,
    self:getSessionCount()
  )
end

return VirtualBufferMetadata
