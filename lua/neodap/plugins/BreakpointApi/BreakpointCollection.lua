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

---@param breakpoint api.FileSourceBreakpoint
function BreakpointCollection:remove(breakpoint)
  for i, b in ipairs(self.breakpoints) do
    if b == breakpoint then
      table.remove(self.breakpoints, i)
      return
    end
  end
end

---@return api.FileSourceBreakpoint?
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

---@param predicate fun(breakpoint: api.FileSourceBreakpoint): boolean
---@return api.BreakpointCollection
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
    -- First check exact match with original location
    if breakpoint.location:matches(location) then
      return true
    end
    
    -- Also check if any binding's actual location matches the requested location
    -- This handles the case where user tries to toggle a breakpoint that was moved by DAP
    local bindings = breakpoint:getBindings()
    for binding in bindings:each() do
      local actualLocation = binding:getActualLocation()
      if actualLocation:matches(location) then
        return true
      end
      
      -- Check if the requested location is between the original and actual positions
      -- This allows clicking anywhere between the requested and adjusted positions
      local originalLocation = binding:getRequestedLocation()
      if self:_isLocationBetween(location, originalLocation, actualLocation) then
        return true
      end
    end
    
    return false
  end)
end

---@param location api.SourceFileLocation
---@param start api.SourceFileLocation
---@param finish api.SourceFileLocation
---@return boolean
function BreakpointCollection:_isLocationBetween(location, start, finish)
  -- Only consider positions in the same file
  if location.path ~= start.path then
    return false
  end
  
  local targetLine = location.line
  local targetCol = location.column or 0
  local startLine = start.line
  local startCol = start.column or 0
  local finishLine = finish.line
  local finishCol = finish.column or 0
  
  -- Ensure start position is before finish position (swap if needed)
  local minLine, minCol, maxLine, maxCol
  if startLine < finishLine or (startLine == finishLine and startCol <= finishCol) then
    minLine, minCol = startLine, startCol
    maxLine, maxCol = finishLine, finishCol
  else
    minLine, minCol = finishLine, finishCol
    maxLine, maxCol = startLine, startCol
  end
  
  -- Check if target position is between start and finish (inclusive)
  if targetLine < minLine or targetLine > maxLine then
    return false
  end
  
  -- If on the minimum line, check column constraint
  if targetLine == minLine and targetCol < minCol then
    return false
  end
  
  -- If on the maximum line, check column constraint
  if targetLine == maxLine and targetCol > maxCol then
    return false
  end
  
  -- Position is within range
  return true
end

---@param sourceId string
---@return api.BreakpointCollection
function BreakpointCollection:atSourceId(sourceId)
  return self:filter(function(breakpoint)
    return breakpoint.location:isAtSourceId(sourceId)
  end)
end

---@param path string
---@return api.BreakpointCollection
function BreakpointCollection:atPath(path)
  return self:filter(function(breakpoint)
    return breakpoint.location.path == path
  end)
end

---@param dapBreakpoint dap.Breakpoint
---@return api.BreakpointCollection
function BreakpointCollection:match(dapBreakpoint)
  return self:filter(function(breakpoint)
    return breakpoint:matches(dapBreakpoint)
  end)
end

---@return fun(): api.FileSourceBreakpoint?
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

---@return api.FileSourceBreakpoint[]
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