local Class = require('neodap.tools.class')

---@class api.NewBreakpointCollectionProps
---@field breakpoints api.NewFileSourceBreakpoint[]

---@class api.NewBreakpointCollection: api.NewBreakpointCollectionProps
---@field new Constructor<api.NewBreakpointCollectionProps>
local BreakpointCollection = Class()

---@return api.NewBreakpointCollection
function BreakpointCollection.create()
  return BreakpointCollection:new({
    breakpoints = {},
  })
end

---@param breakpoint api.NewFileSourceBreakpoint
function BreakpointCollection:add(breakpoint)
  table.insert(self.breakpoints, breakpoint)
end

---@param breakpoint api.NewFileSourceBreakpoint
function BreakpointCollection:remove(breakpoint)
  for i, b in ipairs(self.breakpoints) do
    if b == breakpoint then
      table.remove(self.breakpoints, i)
      return
    end
  end
end

---@return api.NewFileSourceBreakpoint?
function BreakpointCollection:first()
  return self.breakpoints[1]
end

---@param id string
---@return api.NewFileSourceBreakpoint?
function BreakpointCollection:get(id)
  for _, breakpoint in ipairs(self.breakpoints) do
    if breakpoint.id == id then
      return breakpoint
    end
  end
  return nil
end

---@param predicate fun(breakpoint: api.NewFileSourceBreakpoint): boolean
---@return api.NewBreakpointCollection
function BreakpointCollection:filter(predicate)
  local filtered = BreakpointCollection.create()
  for _, breakpoint in ipairs(self.breakpoints) do
    if predicate(breakpoint) then
      filtered:add(breakpoint)
    end
  end
  return filtered
end

---@param location api.NewSourceFileLocation
---@return api.NewBreakpointCollection
function BreakpointCollection:atLocation(location)
  return self:filter(function(breakpoint)
    return breakpoint.location:matches(location)
  end)
end

---@param sourceId string
---@return api.NewBreakpointCollection
function BreakpointCollection:atSourceId(sourceId)
  return self:filter(function(breakpoint)
    return breakpoint.location:isAtSourceId(sourceId)
  end)
end

---@param path string
---@return api.NewBreakpointCollection
function BreakpointCollection:atPath(path)
  return self:filter(function(breakpoint)
    return breakpoint.location.path == path
  end)
end

---@param dapBreakpoint dap.Breakpoint
---@return api.NewBreakpointCollection
function BreakpointCollection:match(dapBreakpoint)
  return self:filter(function(breakpoint)
    return breakpoint:matches(dapBreakpoint)
  end)
end

---@return fun(): api.NewFileSourceBreakpoint?
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

---@return api.NewFileSourceBreakpoint[]
function BreakpointCollection:toArray()
  return vim.tbl_map(function(b) return b end, self.breakpoints or {})
end

---@return integer
function BreakpointCollection:count()
  return #self.breakpoints
end

---@return boolean
function BreakpointCollection:isEmpty()
  return #self.breakpoints == 0
end

return BreakpointCollection