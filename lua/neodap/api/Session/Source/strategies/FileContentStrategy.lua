local Class = require('neodap.tools.class')
local ContentStrategy = require('neodap.api.Session.Source.strategies.ContentStrategy')
local Logger = require('neodap.tools.logger')

---@class FileContentStrategy: ContentStrategy
local FileContentStrategy = Class(ContentStrategy)

---Create a file content strategy instance
---@param session api.Session
---@param source dap.Source
---@return FileContentStrategy
function FileContentStrategy.create(session, source)
  return FileContentStrategy:new({
    session = session,
    source = source
  })
end

---Retrieve content from file path
---@return string? content
function FileContentStrategy:getContent()
  local log = Logger.get()
  
  if not self.source.path or self.source.path == '' then
    log:warn("FileContentStrategy: No path available for content retrieval")
    return nil
  end
  
  local path = vim.fn.fnamemodify(self.source.path, ':p')
  
  -- Check if file exists
  if vim.fn.filereadable(path) == 0 then
    log:warn("FileContentStrategy: File not readable:", path)
    return nil
  end
  
  -- Read file content
  local ok, content = pcall(function()
    local lines = vim.fn.readfile(path)
    return table.concat(lines, '\n')
  end)
  
  if not ok then
    log:error("FileContentStrategy: Failed to read file:", path, content)
    return nil
  end
  
  log:debug("FileContentStrategy: Successfully read file content:", path)
  return content
end

---Check if file content is available
---@return boolean
function FileContentStrategy:hasContent()
  if not self.source.path or self.source.path == '' then
    return false
  end
  
  local path = vim.fn.fnamemodify(self.source.path, ':p')
  return vim.fn.filereadable(path) == 1
end

return FileContentStrategy