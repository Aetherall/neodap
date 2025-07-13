local Class = require('neodap.tools.class')
local VirtualBufferRegistry = require('neodap.api.VirtualBuffer.Registry')
local Logger = require('neodap.tools.logger')
local nio = require('nio')

---@class VirtualBufferManager
local VirtualBufferManager = Class()

-- Cleanup configuration
local CLEANUP_GRACE_PERIOD = 30 -- seconds
local cleanup_scheduled = {}

---Create a new virtual source buffer
---@param uri string
---@param content string
---@param filetype? string
---@return integer bufnr
function VirtualBufferManager.createBuffer(uri, content, filetype)
  local log = Logger.get()
  log:debug("VirtualBufferManager: Creating buffer for", uri)
  
  -- Create new scratch buffer
  local bufnr = vim.api.nvim_create_buf(false, true) -- nofile, scratch
  
  -- Configure buffer
  vim.api.nvim_buf_set_name(bufnr, uri)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(bufnr, 'buflisted', true)
  
  -- Set filetype if provided
  if filetype then
    log:debug("VirtualBufferManager: Setting filetype to", filetype)
    vim.api.nvim_buf_set_option(bufnr, 'filetype', filetype)
  end
  
  -- Load content
  local lines = vim.split(content, '\n', { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  
  -- Set up buffer-local autocmd for tracking
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = bufnr,
    callback = function()
      log:debug("VirtualBufferManager: Buffer", bufnr, "wiped out, removing from registry")
      -- Remove from registry if buffer is wiped out
      local registry = VirtualBufferRegistry.get()
      registry:removeBuffer(uri)
    end
  })
  
  log:info("VirtualBufferManager: Created virtual buffer", bufnr, "for", uri)
  return bufnr
end

---Schedule cleanup for a buffer with no references
---@param metadata VirtualBufferMetadata
function VirtualBufferManager.scheduleCleanup(metadata)
  local log = Logger.get()
  
  if cleanup_scheduled[metadata.uri] then
    log:debug("VirtualBufferManager: Cleanup already scheduled for", metadata.uri)
    return -- Already scheduled
  end
  
  log:debug("VirtualBufferManager: Scheduling cleanup for", metadata.uri, "in", CLEANUP_GRACE_PERIOD, "seconds")
  cleanup_scheduled[metadata.uri] = true
  
  nio.run(function()
    nio.sleep(CLEANUP_GRACE_PERIOD * 1000) -- Convert to milliseconds
    
    -- Check if buffer should still be cleaned up
    local registry = VirtualBufferRegistry.get()
    local current = registry:getBufferByUri(metadata.uri)
    
    if current and not current:hasReferences() then
      log:debug("VirtualBufferManager: Executing cleanup for", metadata.uri)
      -- Still no references, proceed with cleanup
      if current:isValid() then
        vim.schedule(function()
          log:info("VirtualBufferManager: Deleting unreferenced virtual buffer", current.bufnr)
          vim.api.nvim_buf_delete(current.bufnr, { force = true })
        end)
      end
      registry:removeBuffer(metadata.uri)
    else
      log:debug("VirtualBufferManager: Cleanup cancelled for", metadata.uri, "(buffer has references or was removed)")
    end
    
    cleanup_scheduled[metadata.uri] = nil
  end)
end

---Cancel scheduled cleanup for a buffer (when it gets new references)
---@param uri string
function VirtualBufferManager.cancelCleanup(uri)
  if cleanup_scheduled[uri] then
    local log = Logger.get()
    log:debug("VirtualBufferManager: Cancelling cleanup for", uri)
    cleanup_scheduled[uri] = nil
  end
end

---Manual cleanup of all unreferenced buffers
---@return integer cleaned_count
function VirtualBufferManager.cleanupUnreferenced()
  local log = Logger.get()
  local registry = VirtualBufferRegistry.get()
  local cleaned = 0
  
  log:info("VirtualBufferManager: Starting manual cleanup of unreferenced buffers")
  
  for uri, metadata in pairs(registry.buffers) do
    if not metadata:hasReferences() and metadata:isValid() then
      log:debug("VirtualBufferManager: Cleaning up unreferenced buffer", uri)
      vim.api.nvim_buf_delete(metadata.bufnr, { force = true })
      registry:removeBuffer(uri)
      cleaned = cleaned + 1
    end
  end
  
  log:info("VirtualBufferManager: Manual cleanup completed, removed", cleaned, "buffers")
  vim.notify(string.format("Cleaned up %d unreferenced virtual buffers", cleaned))
  return cleaned
end

---Force cleanup of all virtual buffers (for testing/reset)
function VirtualBufferManager.cleanupAll()
  local log = Logger.get()
  log:warn("VirtualBufferManager: Force cleanup of all virtual buffers")
  
  local registry = VirtualBufferRegistry.get()
  registry:clear()
  
  -- Clear cleanup schedule
  cleanup_scheduled = {}
end

---Get statistics about virtual buffers
---@return { total: integer, referenced: integer, unreferenced: integer, invalid: integer, scheduled_cleanup: integer }
function VirtualBufferManager.getStats()
  local registry = VirtualBufferRegistry.get()
  local stats = registry:getStats()
  
  -- Add cleanup scheduling info
  local scheduled_cleanup = 0
  for _ in pairs(cleanup_scheduled) do
    scheduled_cleanup = scheduled_cleanup + 1
  end
  
  stats.scheduled_cleanup = scheduled_cleanup
  return stats
end

---Detect appropriate filetype for virtual source content
---@param name string
---@param origin? string
---@param content? string
---@return string?
function VirtualBufferManager.detectFiletype(name, origin, content)
  -- Try to detect from name extension
  local extension = name:match("%.([^%.]+)$")
  if extension then
    local filetype = vim.filetype.match({ filename = "dummy." .. extension })
    if filetype then
      return filetype
    end
  end
  
  -- Heuristics based on origin/name patterns
  if name:match("%.js$") or name:match("webpack://") then
    return "javascript"
  elseif name:match("%.ts$") then
    return "typescript"
  elseif name:match("%.jsx$") then
    return "javascriptreact"
  elseif name:match("%.tsx$") then
    return "typescriptreact"
  elseif origin and origin:match("eval") then
    return "javascript" -- Common case for eval code
  end
  
  -- Content-based detection as fallback
  if content then
    local first_lines = table.concat(vim.split(content, '\n', { plain = true }), '\n', 1, 10)
    if first_lines:match("import%s+") or first_lines:match("export%s+") then
      return "javascript"
    end
  end
  
  return nil -- Let Neovim decide
end

return VirtualBufferManager