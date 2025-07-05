local Class = require('neodap.tools.class')

---@class api.BreakpointCollectionProps
---@field breakpoints api.FileSourceBreakpoint[]

---@class api.BreakpointCollection: api.BreakpointCollectionProps
---@field new Constructor<api.BreakpointCollectionProps>
local BreakpointCollection = Class()


---@return api.BreakpointCollection
function BreakpointCollection.create()
  return BreakpointCollection:new({
    breakpoints = {},
  })
end


---@param breakpoint api.FileSourceBreakpoint
function BreakpointCollection:add(breakpoint)
  table.insert(self.breakpoints, breakpoint)
end

function BreakpointCollection:remove(breakpoint)
  for i, b in ipairs(self.breakpoints) do
    if b == breakpoint then
      table.remove(self.breakpoints, i)
      return
    end
  end
end

function BreakpointCollection:first()
  return self.breakpoints[1]
end

---@param id string
---@return api.FileSourceBreakpoint?
function BreakpointCollection:get(id)
  for _, breakpoint in ipairs(self.breakpoints) do
    if breakpoint.id == id then
      return breakpoint
    end
  end
  return nil
end

---@generic T
---@param by fun(breakpoint: api.FileSourceBreakpoint): T
---@param keyer fun(t: T): any
---@return fun(): T, api.BreakpointCollection
function BreakpointCollection:groupBy(by, keyer)
  local groups = {}
  for _, breakpoint in ipairs(self.breakpoints) do
    local value = by(breakpoint)
    local key = keyer(value)
    if not groups[key] then
      groups[key] = { collection = BreakpointCollection.create(), value = value }
    end
    groups[key].collection:add(breakpoint)
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

---@param predicate fun(breakpoint: api.FileSourceBreakpoint): any?
function BreakpointCollection:filter(predicate)
  local filtered = BreakpointCollection.create()
  for _, breakpoint in ipairs(self.breakpoints) do
    if predicate(breakpoint) then
      filtered:add(breakpoint)
    end
  end
  return filtered
end


---@param location api.SourceFileLocation
---@return api.BreakpointCollection
function BreakpointCollection:atLocation(location)
  return self:filter(function(breakpoint)
    return breakpoint.location and breakpoint.location:matches(location)
  end)
end

---@param location api.SourceFileLocation
---@param bindings_collection api.BindingCollection
---@return api.FileSourceBreakpoint?
function BreakpointCollection:findByAnyLocation(location, bindings_collection)
  for _, breakpoint in ipairs(self.breakpoints) do
    -- Check requested location
    if breakpoint.location:matches(location) then
      return breakpoint
    end
    
    -- Check actual binding locations if bindings_collection provided
    if bindings_collection then
      for binding in bindings_collection:forBreakpoint(breakpoint):each() do
        if binding.verified and 
           binding.actualLine == location.line and 
           (binding.actualColumn or 0) == (location.column or 0) then
          return breakpoint
        end
      end
    end
  end
  return nil
end

function BreakpointCollection:atSourceId(sourceId)
  return self:filter(function(breakpoint)
    return breakpoint.location:isAtSourceId(sourceId)
  end)
end

---@param dapBreakpoint dap.Breakpoint
function BreakpointCollection:match(dapBreakpoint)
  return self:filter(function(breakpoint)
    return breakpoint:matches(dapBreakpoint)
  end)
end

function BreakpointCollection:each()
  local index = 0
  return function()
    index = index + 1
    if index > #self.breakpoints then
      return nil
    end
    return self.breakpoints[index]
  end
end

return BreakpointCollection