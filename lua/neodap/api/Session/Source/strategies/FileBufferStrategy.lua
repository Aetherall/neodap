local Class = require('neodap.tools.class')
local BufferStrategy = require('neodap.api.Session.Source.strategies.BufferStrategy')
local Logger = require('neodap.tools.logger')

---@class FileBufferStrategy: BufferStrategy
local FileBufferStrategy = Class(BufferStrategy)

---Create a file buffer strategy instance
---@param session api.Session
---@param source dap.Source
---@return FileBufferStrategy
function FileBufferStrategy.create(session, source)
  return FileBufferStrategy:new({
    session = session,
    source = source
  })
end

---Get or create buffer using Neovim's file buffer management
---@param identifier SourceIdentifier
---@param contentStrategy ContentStrategy
---@return integer? bufnr
function FileBufferStrategy:getBuffer(identifier, contentStrategy)
  local log = Logger.get()
  
  if not identifier:isFile() then
    log:error("FileBufferStrategy: Cannot handle non-file identifier")
    return nil
  end
  
  if not self.source.path or self.source.path == '' then
    log:warn("FileBufferStrategy: No path available for buffer creation")
    return nil
  end
  
  local path = vim.fn.fnamemodify(self.source.path, ':p')
  local uri = vim.uri_from_fname(path)
  local bufnr = vim.uri_to_bufnr(uri)
  
  if bufnr == -1 then
    log:debug("FileBufferStrategy: No existing buffer, creating new buffer for:", path)
    
    -- Check if file exists before creating buffer
    if vim.fn.filereadable(path) == 0 then
      log:warn("FileBufferStrategy: File not readable, cannot create buffer:", path)
      return nil
    end
    
    -- Create buffer for the file
    bufnr = vim.fn.bufnr(path, true)
    
    if bufnr == -1 then
      log:error("FileBufferStrategy: Failed to create buffer for:", path)
      return nil
    end
    
    log:debug("FileBufferStrategy: Created buffer", bufnr, "for file:", path)
  else
    log:debug("FileBufferStrategy: Using existing buffer", bufnr, "for file:", path)
  end
  
  return bufnr
end

---File buffer management is available if we have a path
---@return boolean
function FileBufferStrategy:canManageBuffer()
  return self.source.path and self.source.path ~= ''
end

return FileBufferStrategy