-- Breakpoint finding methods for Debugger (neograph-native)
--
-- Performance note: All functions first resolve the Source by path using
-- the `by_path` index (O(1)), then iterate only that source's breakpoints
-- instead of scanning all breakpoints globally.

---Iterate breakpoints for a specific source path
---@param self neodap.entities.Debugger
---@param path string Buffer URI
---@return fun(): neodap.entities.Breakpoint? iterator
local function iter_source_breakpoints(self, path)
  local source = self:findSourceByPath(path) or self:findSourceByKey(path)
  if source then
    return source.breakpoints:iter()
  end
  -- No source found — return empty iterator
  return function() return nil end
end

---Iterate over breakpoints at a location (matches by path)
---@param self neodap.entities.Debugger
---@param loc neodap.Location Location with path
---@return fun(): neodap.entities.Breakpoint? iterator
local function iter_at(self, loc)
  return iter_source_breakpoints(self, loc.path)
end

return function(Debugger)
  Debugger.breakpointsAt = iter_at
end
