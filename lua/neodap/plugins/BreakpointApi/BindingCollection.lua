local Collection = require('neodap.tools.Collection')
local Logger = require('neodap.tools.logger')
local Class = require('neodap.tools.class')

---@class api.BindingCollection: Collection<api.Binding>
local BindingCollection = Class(Collection)

---@return api.BindingCollection
function BindingCollection.create()
  -- Use the inherited create pattern from Class(Collection)
  local instance = BindingCollection:new({})
  instance:_initialize({
    items = {},
    indexes = {
      id = {
        indexer = function(binding) 
          return binding.id 
        end,
        unique = true
      },
      session_key = {
        indexer = function(binding) 
          return binding.session.id 
        end,
        unique = false
      },
      source_key = {
        indexer = function(binding) 
          return binding.source.id:toString() 
        end,
        unique = false
      },
      breakpoint_key = {
        indexer = function(binding) 
          return binding.breakpointId 
        end,
        unique = false
      }
    }
  })
  
  return instance
end


-- Convenience accessor for backward compatibility
---@return api.Binding[]
function BindingCollection:bindings()
  return self.items
end

-- Override createEmpty to return BindingCollection instead of Collection
---@return api.BindingCollection
function BindingCollection:createEmpty()
  return BindingCollection.create()
end

---@param session api.Session
---@return api.BindingCollection
function BindingCollection:forSession(session)
  return self:whereBy("session_key", session.id)
end

---@param source api.Source
---@return api.BindingCollection
function BindingCollection:forSource(source)
  return self:whereBy("source_key", source.id:toString())
end

---@param breakpoint api.Breakpoint
---@return api.BindingCollection
function BindingCollection:forBreakpoint(breakpoint)
  return self:whereBy("breakpoint_key", breakpoint.id)
end

---@param ids integer[]
---@return api.BindingCollection
function BindingCollection:forIds(ids)
  return self:getByAny("id", ids)
end

-- DAP synchronization methods

---@return dap.SourceBreakpoint[]
function BindingCollection:toDapSourceBreakpoints()
  local dapBreakpoints = {}
  for _, binding in ipairs(self.items) do
    local dapBreakpoint = binding:toDapSourceBreakpoint()
    table.insert(dapBreakpoints, dapBreakpoint)
  end
  return dapBreakpoints
end

---Group bindings by session
---@return fun(): api.Session?, api.BindingCollection?
function BindingCollection:bySession()
  return self:groupBy(function(binding)
    return binding.session.id
  end)
end

---Group bindings by source  
---@return fun(): api.FileSource?, api.BindingCollection?
function BindingCollection:bySource()
  return self:groupBy(function(binding)
    return binding.source.id:toString()
  end)
end

return BindingCollection