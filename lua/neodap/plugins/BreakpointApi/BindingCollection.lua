local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')

---@class api.BindingCollectionProps
---@field bindings api.Binding[]

---@class api.BindingCollection: api.BindingCollectionProps
---@field new Constructor<api.BindingCollectionProps>
local BindingCollection = Class()

---@return api.BindingCollection
function BindingCollection.create()
  return BindingCollection:new({
    bindings = {},
  })
end

---@param binding api.Binding
function BindingCollection:add(binding)
  table.insert(self.bindings, binding)
end

---@param binding api.Binding
function BindingCollection:remove(binding)
  for i, b in ipairs(self.bindings) do
    if b == binding then
      table.remove(self.bindings, i)
      return
    end
  end
end

---@return api.Binding?
function BindingCollection:first()
  return self.bindings[1]
end

---@param predicate fun(binding: api.Binding): boolean
---@return api.BindingCollection
function BindingCollection:filter(predicate)
  local filtered = BindingCollection.create()
  for _, binding in ipairs(self.bindings) do
    if predicate(binding) then
      filtered:add(binding)
    end
  end
  return filtered
end

---@param session api.Session
---@return api.BindingCollection
function BindingCollection:forSession(session)
  return self:filter(function(binding)
    return binding.session.id == session.id
  end)
end

---@param source api.Source
---@return api.BindingCollection
function BindingCollection:forSource(source)
  return self:filter(function(binding)
    return binding.source.id:equals(source.id)
  end)
end

---@param breakpoint api.Breakpoint
---@return api.BindingCollection
function BindingCollection:forBreakpoint(breakpoint)
  return self:filter(function(binding)
    return binding.breakpointId == breakpoint.id
  end)
end

---@param ids integer[]
---@return api.BindingCollection
function BindingCollection:forIds(ids)
  return self:filter(function(binding)
    return vim.tbl_contains(ids, binding.id)
  end)
end

---@return fun(): api.Binding?
function BindingCollection:each()
  local index = 0
  return function()
    index = index + 1
    if index > #self.bindings then
      return nil
    end
    return self.bindings[index]
  end
end

---@return api.Binding[]
function BindingCollection:toArray()
  return vim.tbl_map(function(b) return b end, self.bindings or {})
end

---@return integer
function BindingCollection:count()
  return #self.bindings
end

---@return boolean
function BindingCollection:isEmpty()
  return #self.bindings == 0
end

-- DAP synchronization methods

---@return dap.SourceBreakpoint[]
function BindingCollection:toDapSourceBreakpoints()
  local dapBreakpoints = {}
  for _, binding in ipairs(self.bindings) do
    local dapBreakpoint = binding:toDapSourceBreakpoint()
    table.insert(dapBreakpoints, dapBreakpoint)
  end
  return dapBreakpoints
end

---Group bindings by session
---@return fun(): api.Session?, api.BindingCollection?
function BindingCollection:bySession()
  local groups = {}
  for _, binding in ipairs(self.bindings) do
    local sessionId = binding.session.id
    if not groups[sessionId] then
      groups[sessionId] = { 
        session = binding.session, 
        collection = BindingCollection.create() 
      }
    end
    groups[sessionId].collection:add(binding)
  end

  local keys = vim.tbl_keys(groups)
  local index = 0
  return function()
    index = index + 1
    if index > #keys then
      return nil, nil
    end
    local group = groups[keys[index]]
    return group.session, group.collection
  end
end

---Group bindings by source
---@return fun(): api.FileSource?, api.BindingCollection?
function BindingCollection:bySource()
  local groups = {}
  for _, binding in ipairs(self.bindings) do
    local sourceId = binding.source.id:toString()
    if not groups[sourceId] then
      groups[sourceId] = { 
        source = binding.source, 
        collection = BindingCollection.create() 
      }
    end
    groups[sourceId].collection:add(binding)
  end

  local keys = vim.tbl_keys(groups)
  local index = 0
  return function()
    index = index + 1
    if index > #keys then
      return nil, nil
    end
    local group = groups[keys[index]]
    return group.source, group.collection
  end
end

return BindingCollection