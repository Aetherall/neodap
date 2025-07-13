local FileSource = require('neodap.api.Session.Source.FileSource')
local VirtualSource = require('neodap.api.Session.Source.VirtualSource')
local GenericSource = require('neodap.api.Session.Source.GenericSource')
local UnifiedSource = require('neodap.api.Session.Source.UnifiedSource')

local SourceFactory = {}

---@alias api.Source api.FileSource | api.VirtualSource | api.UnifiedSource


---@param session api.Session
---@param source dap.Source
---@return api.Source
function SourceFactory.instanciate(session, source)
  -- Use UnifiedSource for new implementation
  -- Keep legacy sources for backward compatibility during transition
  
  -- For now, always use UnifiedSource
  return UnifiedSource.instanciate(session, source)
  
  -- Legacy logic (commented out for now):
  -- local instance
  -- if source.sourceReference and source.sourceReference > 0 then
  --   instance = VirtualSource.instanciate(session, source)
  -- elseif source.path and source.path ~= '' then
  --   instance = FileSource.instanciate(session, source)
  -- else
  --   instance = GenericSource.instanciate(session, source)
  -- end
  -- return instance
end

return SourceFactory
