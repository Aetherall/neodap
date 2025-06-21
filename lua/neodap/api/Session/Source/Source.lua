local FileSource = require('neodap.api.Session.Source.FileSource')
local VirtualSource = require('neodap.api.Session.Source.VirtualSource')
local GenericSource = require('neodap.api.Session.Source.GenericSource')

local SourceFactory = {}

---@alias api.Source api.FileSource | api.VirtualSource


---@param session api.Session
---@param source dap.Source
---@return api.Source
function SourceFactory.instanciate(session, source)
  local instance

  -- Create appropriate source type
  if source.sourceReference and source.sourceReference > 0 then
    instance = VirtualSource.instanciate(session, source)
  elseif source.path and source.path ~= '' then
    instance = FileSource.instanciate(session, source)
  else
    instance = GenericSource.instanciate(session, source)
  end

  return instance
end

return SourceFactory
