-- Breakpoint finding methods for Debugger (neograph-native)

---Check if breakpoint matches a path (buffer URI)
---@param bp neodap.entities.Breakpoint
---@param path string Buffer URI to match
---@return boolean
local function matches_path(bp, path)
  local loc = bp:location()
  return loc and loc.path == path
end

---Find breakpoint at exact line (also checks binding actualLine)
---@param self neodap.entities.Debugger
---@param loc neodap.Location Location with path and line
---@return neodap.entities.Breakpoint?
local function find_at_line(self, loc)
  for bp in self.breakpoints:iter() do
    if matches_path(bp, loc.path) then
      if bp.line:get() == loc.line then return bp end
      for binding in bp.bindings:iter() do
        if binding.actualLine:get() == loc.line then return bp end
      end
    end
  end
end

---Find breakpoint at exact point (also checks binding actual location)
---@param self neodap.entities.Debugger
---@param loc neodap.Location Location with path, line, and column
---@return neodap.entities.Breakpoint?
local function find_at_point(self, loc)
  -- First pass: match on breakpoint properties
  -- A line-only breakpoint (column=nil) matches any column on that line
  for bp in self.breakpoints:iter() do
    if matches_path(bp, loc.path) and bp.line:get() == loc.line then
      local bp_col = bp.column:get()
      if bp_col == nil or bp_col == loc.column then
        return bp
      end
    end
  end
  -- Second pass: match on binding actual locations
  for bp in self.breakpoints:iter() do
    if matches_path(bp, loc.path) then
      for binding in bp.bindings:iter() do
        local actual_line = binding.actualLine:get() or bp.line:get()
        local actual_col = binding.actualColumn:get() or bp.column:get() or 1
        if actual_line == loc.line and actual_col == loc.column then return bp end
      end
    end
  end
end

---Find breakpoint at location (dispatches based on location type)
---@param self neodap.entities.Debugger
---@param loc neodap.Location Location to find breakpoint at
---@return neodap.entities.Breakpoint?
local function find(self, loc)
  if loc:is_point() then return find_at_point(self, loc) end
  return find_at_line(self, loc)
end

---Iterate over breakpoints at a location (matches by path)
---@param self neodap.entities.Debugger
---@param loc neodap.Location Location with path
---@return fun(): neodap.entities.Breakpoint? iterator
local function iter_at(self, loc)
  local bp_iter = self.breakpoints:iter()
  return function()
    for bp in bp_iter do
      if matches_path(bp, loc.path) then
        return bp
      end
    end
    return nil
  end
end

return function(Debugger)
  Debugger.findBreakpoint = find
  Debugger.breakpointsAt = iter_at
end
