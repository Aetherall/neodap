local UnifiedSource = require('neodap.api.Session.Source.UnifiedSource')

local SourceFactory = {}

---@alias api.Source api.UnifiedSource

---@param session api.Session
---@param source dap.Source
---@return api.Source
function SourceFactory.instanciate(session, source)
  return UnifiedSource.instanciate(session, source)
end

return SourceFactory
