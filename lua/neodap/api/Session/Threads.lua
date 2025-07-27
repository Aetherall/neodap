local Class = require('neodap.tools.class')
local Collection = require("neodap.tools.Collection")


---@class api.Threads: Collection<api.Thread>
local Threads = Class(Collection)

---@return api.Threads
function Threads.create()
  local instance = Threads:new({})
  instance:_initialize({
    items = {},
    indexes = {
      id = {
        indexer = function(thread)
          return thread.id
        end,
        unique = true
      },
      status = {
        indexer = function(thread)
          return thread.stopped and "stopped" or "running"
        end,
        unique = false
      }
    }
  })
  return instance
end

function Threads:eachStopped()
  return self:whereBy("status", "stopped"):each()
end

function Threads:eachRunning()
  return self:whereBy("status", "running"):each()
end

return Threads
