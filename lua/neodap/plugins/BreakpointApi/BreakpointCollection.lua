local Collection = require('neodap.tools.Collection')
local Location = require("neodap.api.Location")
local Class = require('neodap.tools.class')

---@class api.BreakpointCollection: Collection<api.Breakpoint>
local BreakpointCollection = Class(Collection)

---@return api.BreakpointCollection
function BreakpointCollection.create()
  -- Use the inherited create pattern from Class(Collection)
  local instance = BreakpointCollection:new({})
  instance:_initialize({
    items = {},
    indexes = {
      id = {
        indexer = function(breakpoint)
          return breakpoint.id
        end,
        unique = true
      },
      location_key = {
        indexer = function(breakpoint)
          return breakpoint.location.key
        end,
        unique = true
      },
      source_key = {
        indexer = function(breakpoint)
          return breakpoint.location.sourceId:toString()
        end,
        unique = false
      }
    }
  })
  
  return instance
end


-- Override createEmpty to return BreakpointCollection instead of Collection
---@return api.BreakpointCollection
function BreakpointCollection:createEmpty()
  return BreakpointCollection.create()
end

-- Convenience accessor for backward compatibility
---@return api.Breakpoint[]
function BreakpointCollection:breakpoints()
  return self.items
end

---@param id string
---@return api.Breakpoint?
function BreakpointCollection:get(id)
  return self:getBy("id", id)
end

---@param location api.Location|string
---@return api.BreakpointCollection
function BreakpointCollection:atLocation(location)
  -- Handle case where location might be a string (backward compatibility)
  local locationKey
  if type(location) == "string" then
    locationKey = location
  elseif location and location.key then
    locationKey = location.key
  else
    error("Invalid location parameter: expected Location object or string, got " .. type(location))
  end
  
  -- First try O(1) exact location lookup
  local exactMatch = self:getAllBy("location_key", locationKey)
  if not exactMatch:isEmpty() then
    return exactMatch
  end
  
  -- Fallback to O(n) search for DAP position adjustments and binding checks
  return self:filter(function(breakpoint)
    -- Check if any binding's actual location matches the requested location
    -- This handles the case where user tries to toggle a breakpoint that was moved by DAP
    local bindings = breakpoint:getBindings()
    for binding in bindings:each() do
      local actualLocation = binding:getActualLocation()
      if actualLocation:equals(location) then
        return true
      end

      -- Check if the requested location is between the original and actual positions
      -- This allows clicking anywhere between the requested and adjusted positions
      local originalLocation = binding:getRequestedLocation()
      if BreakpointCollection._isLocationBetween(location, originalLocation, actualLocation) then
        return true
      end
    end

    return false
  end)
end

---@param location api.Location
---@param start api.Location
---@param finish api.Location
---@return boolean
function BreakpointCollection._isLocationBetween(location, start, finish)
  -- Only consider positions in the same source
  local target_id = location.sourceId
  local start_id = start.sourceId

  if not target_id:equals(start_id) then
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

---Filter breakpoints by source identifier (preferred method) - O(1) lookup
---@param source_identifier SourceIdentifier
---@return api.BreakpointCollection
function BreakpointCollection:atSource(source_identifier)
  return self:whereBy("source_key", source_identifier:toString())
end

return BreakpointCollection
