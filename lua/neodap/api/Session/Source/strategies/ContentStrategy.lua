local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')

---@class ContentStrategyProps
---@field source dap.Source
---@field session api.Session

---@class ContentStrategy: ContentStrategyProps
---@field new Constructor<ContentStrategyProps>
local ContentStrategy = Class()

---Create a content strategy instance
---@param session api.Session
---@param source dap.Source
---@return ContentStrategy
function ContentStrategy.create(session, source)
  return ContentStrategy:new({
    session = session,
    source = source
  })
end

---Retrieve content for the source
---@return string? content
function ContentStrategy:getContent()
  error("ContentStrategy:getContent() must be implemented by subclass")
end

---Check if content is available
---@return boolean
function ContentStrategy:hasContent()
  error("ContentStrategy:hasContent() must be implemented by subclass")
end

---Get content hash for validation
---@return string
function ContentStrategy:getContentHash()
  local content = self:getContent()
  return content and vim.fn.sha256(content) or ""
end

return ContentStrategy