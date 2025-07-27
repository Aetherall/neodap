local Class = require('neodap.tools.class')
local Collection = require("neodap.tools.Collection")


---@class api.Frames: Collection<api.Frame>
local Frames = Class(Collection)

---@return api.Frames
function Frames.create()
  local instance = Frames:new({})
  instance:_initialize({
    items = {},
    indexes = {
      id = {
        indexer = function(frame)
          return frame.id
        end,
        unique = true
      },
      position = {
        indexer = function(_frame, position)
          return position
        end,
        unique = true
      },
      sourceId = {
        indexer = function(frame)
          return frame._source and frame._source.id:toString() or nil
        end,
        unique = false
      },
    }
  })
  return instance
end

return Frames
