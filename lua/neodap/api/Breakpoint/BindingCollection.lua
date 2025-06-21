local Class = require('neodap.tools.class')

---@class api.BindingCollectionProps
---@field bindings api.FileSourceBinding[]

---@class api.BindingCollection: api.BindingCollectionProps
---@field new Constructor<api.BindingCollectionProps>
local BindingCollection = Class()


---@return api.BindingCollection
function BindingCollection.create()
  return BindingCollection:new({
    bindings = {},
  })
end


---@param binding api.FileSourceBinding
function BindingCollection:add(binding)
  table.insert(self.bindings, binding)
end

function BindingCollection:remove(binding)
  for i, b in ipairs(self.bindings) do
    if b == binding then
      table.remove(self.bindings, i)
      return
    end
  end
end


function BindingCollection:first()
  return self.bindings[1]
end

---@generic T
---@param by fun(binding: api.FileSourceBinding): T
---@param keyer fun(t: T): any
---@return fun(): T, api.BindingCollection
function BindingCollection:groupBy(by, keyer)
  local groups = {}
  for _, binding in ipairs(self.bindings) do
    local value = by(binding)
    local key = keyer(value)
    if not groups[key] then
      groups[key] = { collection = BindingCollection.create(), value = value }
    end
    groups[key].collection:add(binding)
  end

  local keys = vim.tbl_keys(groups)
  local index = 0
  return function()
    index = index + 1
    if index > #keys then
      return nil, nil
    end

    local group = groups[keys[index]]
    return group.value, group.collection
  end
end

function BindingCollection:filter(predicate)
  local filtered = BindingCollection.create()
  for _, binding in ipairs(self.bindings) do
    if predicate(binding) then
      filtered:add(binding)
    end
  end
  return filtered
end


---@return fun(): api.Session, api.BindingCollection
function BindingCollection:bySession()
  return self:groupBy(
    function(binding) return binding.session end,
    function(session) return session.ref.id end
  )
end

---@return fun(): api.Source, api.BindingCollection
function BindingCollection:bySource()
  return self:groupBy(
    function(binding) return binding.source end,
    function(source) return source.id end
  )
end


function BindingCollection:forSource(source)
  return self:filter(function(binding)
    return binding.source.id == source.id
  end)
end

---@param session api.Session
---@return api.BindingCollection
function BindingCollection:forSession(session)
  return self:filter(function(binding)
    return binding.session.id == session.id
  end)
end

---@param ids integer[]
function BindingCollection:forIds(ids)
  return self:filter(function(binding)
    return vim.tbl_contains(ids, binding.id)
  end)
end


---@param breakpoint api.FileSourceBreakpoint
---@return api.BindingCollection
function BindingCollection:forBreakpoint(breakpoint)
  return self:filter(function(binding)
    return binding.breakpointId == breakpoint.id
  end)
end

---@return api.FileSourceBinding[]
function BindingCollection:toArray()
  return vim.tbl_map(function(b) return b end, self.bindings or {})
end


---@return dap.SourceBreakpoint[]
function BindingCollection:toDapSourceBreakpoints()
  local dapBreakpoints = {}
  for _, binding in ipairs(self.bindings) do
    local dapBreakpoint = binding:toDapSourceBreakpoint()
    table.insert(dapBreakpoints, dapBreakpoint)
  end
  return dapBreakpoints
end

function BindingCollection:push()
  for session, bindings in self:bySession() do
    for source, bindings in bindings:bySource() do
      
      local array = bindings:toArray()

      local dapBreakpoints = vim.tbl_map(function(binding) return binding:toDapSourceBreakpoint() end, array)

      local result = session.ref.calls:setBreakpoints({
        source = source.ref,
        breakpoints = dapBreakpoints
      }):wait()

      for i, breakpoint in ipairs(result.breakpoints) do
        local binding = array[i]
        if binding then
          binding:update(breakpoint)
        end
      end
    end
  end
end




---@param dapBinding dap.Breakpoint
function BindingCollection:match(dapBinding)
  return self:filter(function(binding)
    return binding:matches(dapBinding)
  end)
end


---@return fun(): api.FileSourceBinding
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

return BindingCollection