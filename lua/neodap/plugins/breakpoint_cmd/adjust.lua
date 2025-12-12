-- Position adjustment for breakpoint locations
-- Line (column nil) → adjust to valid column
-- Point (column set) → return as-is

local Location = require("neodap.location")

local function find_closest(locations, line)
  if #locations == 0 then return nil end
  local closest = locations[1]
  for _, loc in ipairs(locations) do
    if loc.line == line then return loc end
  end
  return closest
end

-- Adjust location to valid breakpoint position
-- Called from async context, uses a.fn() wrapped methods
local function adjust(debugger, loc)
  if loc:is_point() or not debugger:supportsBreakpointLocations() then
    return loc -- Keep as-is: Point stays Point, Line stays Line
  end

  local ok, locations = pcall(function()
    return debugger:breakpointLocations({ path = loc.path }, loc.line, {})
  end)

  if not ok or not locations or #locations == 0 then
    return Location.new(loc.path, loc.line, 1)
  end

  local closest = find_closest(locations, loc.line)
  return Location.new(loc.path, closest.line, closest.column)
end

return { adjust = adjust }
