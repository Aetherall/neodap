local Class = require("neodap.tools.class")
local Logger = require("neodap.tools.logger")
local Location = require("neodap.api.Location")


---@class neodap.ToggleBreakpointProps
---@field api Api
---@field breakpointApi BreakpointApiPlugin
---@field logger Logger

---@class neodap.ToggleBreakpoint: neodap.ToggleBreakpointProps
---@field new Constructor<neodap.ToggleBreakpointProps>
local ToggleBreakpoint = Class()

ToggleBreakpoint.name = "ToggleBreakpoint"
ToggleBreakpoint.description = "Plugin for smart breakpoint toggling with location adjustment"

function ToggleBreakpoint.plugin(api)
  local logger = Logger.get()
  local breakpointApi = api:getPluginInstance(require("neodap.plugins.BreakpointApi"))
  return ToggleBreakpoint:new({
    api = api,
    breakpointApi = breakpointApi,
    logger = logger
  })
end



---Apply smart placement to a location based on available sessions and breakpoint locations
---@param location api.SourceFileLocation
---@return api.SourceFileLocation|nil adjusted The adjusted location, or nil if no valid placement possible
function ToggleBreakpoint:adjustLocation(location)
  local log = Logger.get()
  
  -- First, check if we already have a breakpoint at this exact location
  local existingAtExact = self.breakpointApi.getBreakpoints():atLocation(location):first()
  if existingAtExact then
    log:debug("Smart placement: breakpoint already exists at exact location:", location.key)
    return location
  end
  
  -- Check if any session can provide valid breakpoint locations
  local adjustedLocation = nil
  
  for session in self.api:eachSession() do
    local source = session:getFileSourceAt(location)
    if source then
      log:debug("Smart placement: found source for location, querying breakpoint locations...")
      
      -- Try to get specific breakpoint locations from DAP adapter
      local closestLocation = session:findClosestBreakpointLocation(source, location.line, location.column)
      if closestLocation then
        -- Create adjusted location based on DAP adapter's response
        local adjustedKey = location.path .. ":" .. closestLocation.line .. ":" .. closestLocation.column
        adjustedLocation = Location.SourceFile:new({
          path = location.path,
          line = closestLocation.line,
          column = closestLocation.column,
          key = adjustedKey
        })
        
        log:debug("Smart placement: adapter provided valid location at", closestLocation.line, closestLocation.column)
        break
      else
        log:debug("Smart placement: adapter returned no specific breakpoint locations")
        -- This is common - many adapters support breakpointLocations but don't provide
        -- granular column-level information. The adapter will handle placement during setBreakpoints.
      end
    end
  end
  
  -- If no session provided specific valid locations, use intelligent fallback
  if not adjustedLocation then
    if location.column ~= 0 then
      local fallbackKey = location.path .. ":" .. location.line .. ":0"
      adjustedLocation = Location.SourceFile:new({
        path = location.path,
        line = location.line,
        column = 0,
        key = fallbackKey
      })
      
      local hasActiveSessions = false
      for _ in self.api:eachSession() do
        hasActiveSessions = true
        break
      end
      
      if hasActiveSessions then
        log:debug("Smart placement: adapter doesn't provide granular locations, using line start (will be adjusted by adapter during sync)")
      else
        log:debug("Smart placement: no active session, fallback to line start (column 0)")
      end
    else
      adjustedLocation = location
      log:debug("Smart placement: already at line start, no adjustment needed")
    end
  end
  
  -- Check if the adjusted location would conflict with an existing breakpoint
  local existingAtAdjusted = self.breakpointApi.getBreakpoints():atLocation(adjustedLocation):first()
  if existingAtAdjusted and adjustedLocation.key ~= location.key then
    log:debug("Smart placement: adjusted location conflicts with existing breakpoint:", adjustedLocation.key)
    -- Return nil to indicate we shouldn't create a duplicate
    return nil
  end
  
  return adjustedLocation
end

---Check if a new breakpoint would create a duplicate binding at the same DAP location
---@param location api.SourceFileLocation
---@return boolean wouldDuplicate True if this would create a duplicate binding
function ToggleBreakpoint:wouldCreateDuplicateBinding(location)
  local log = Logger.get()
  
  -- For each active session, check if this location would bind to the same place as an existing breakpoint
  for session in self.api:eachSession() do
    local source = session:getFileSourceAt(location)
    if source then
      -- Get the closest valid breakpoint location that DAP would actually use
      local actualLocation = session:findClosestBreakpointLocation(source, location.line, location.column)
      if actualLocation then
        -- Check if any existing bindings are already at this actual location
        local existingBindings = self.breakpointApi.getBindings():forSession(session):forSource(source)
        for binding in existingBindings:each() do
          if binding.actualLine == actualLocation.line and binding.actualColumn == actualLocation.column then
            log:debug("Would create duplicate: binding already exists at DAP location", 
                     actualLocation.line, actualLocation.column, "for breakpoint", binding.breakpointId)
            return true
          end
        end
      end
    end
  end
  
  return false
end

---Toggle a breakpoint at the given location
---@param location api.SourceFileLocation
---@return api.FileSourceBreakpoint?
function ToggleBreakpoint:toggle(location)
  local log = Logger.get()
  log:debug("ToggleBreakpoint:toggle called for:", location.key)

  -- First, check for exact match at the requested location
  local existing = self.breakpointApi.getBreakpoints():atLocation(location):first()
  if existing then
    log:debug("Found exact match, removing breakpoint:", existing.id)
    self.breakpointApi.removeBreakpoint(existing)
    return nil
  end
  
  -- Apply smart placement to see where we would actually create the breakpoint
  local smartLocation = self:adjustLocation(location)
  if not smartLocation then
    log:debug("Toggle: smart placement returned nil, indicating duplicate would be created")
    -- This means there's already a breakpoint that would conflict
    -- Find any existing breakpoint on this line and remove it
    local breakpoints = self.breakpointApi.getBreakpoints()
    for breakpoint in breakpoints:each() do
      if breakpoint.location.path == location.path and breakpoint.location.line == location.line then
        log:debug("Toggle: removing existing breakpoint at same line:", breakpoint.id)
        self.breakpointApi.removeBreakpoint(breakpoint)
        return nil
      end
    end
    return nil
  end
  
  -- Check if there's already a breakpoint at the smart-adjusted location
  local existingAtSmart = self.breakpointApi.getBreakpoints():atLocation(smartLocation):first()
  if existingAtSmart then
    log:debug("Toggle: found existing breakpoint at smart location, removing:", existingAtSmart.id)
    self.breakpointApi.removeBreakpoint(existingAtSmart)
    return nil
  end
  
  -- Create new breakpoint at the smart location
  log:debug("Toggle: creating new breakpoint at smart location:", smartLocation.key)
  return self.breakpointApi.setBreakpoint(smartLocation)
end

---Clear a breakpoint at the given location (considering smart placement)
---@param location api.SourceFileLocation
---@return boolean cleared True if a breakpoint was cleared
function ToggleBreakpoint:clear(location)
  local log = Logger.get()
  log:debug("ToggleBreakpoint:clear called for:", location.key)
  
  -- First check exact location
  local existing = self.breakpointApi.getBreakpoints():atLocation(location):first()
  if existing then
    self.breakpointApi.removeBreakpoint(existing)
    return true
  end
  
  -- Check adjusted location
  local adjustedLocation = self:adjustLocation(location)
  if adjustedLocation and adjustedLocation.key ~= location.key then
    existing = self.breakpointApi.getBreakpoints():atLocation(adjustedLocation):first()
    if existing then
      self.breakpointApi.removeBreakpoint(existing)
      return true
    end
  end
  
  return false
end

---Clear all breakpoints
function ToggleBreakpoint:clearAll()
  local log = Logger.get()
  log:info("ToggleBreakpoint:clearAll called")

  -- Get all breakpoints and remove them
  local count = 0
  for breakpoint in self.breakpointApi.getBreakpoints():each() do
    self.breakpointApi.removeBreakpoint(breakpoint)
    count = count + 1
  end
  
  log:info("Cleared", count, "breakpoints")
end

return ToggleBreakpoint