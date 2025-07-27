local Class = require('neodap.tools.class')
local Collection = require("neodap.tools.Collection")


---@class api.Sources: Collection<api.Source, 'id' | 'name'>
local Sources = Class(Collection)

---@return api.Sources
function Sources.init()
  local instance = Sources:new({})
  instance:_initialize({
    items = {},
    indexes = {
      id = {
        indexer = function(source)
          return source.id:toString()
        end,
        unique = true
      },
      name = {
        indexer = function(source)
          return source.name
        end,
        unique = false
      }
    }
  })
  return instance
end

return Sources
