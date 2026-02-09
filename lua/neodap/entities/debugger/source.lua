-- Source management methods for Debugger (neograph-native)
--
-- Performance note: Sources are indexed by key in the graph schema.
-- The `by_key` index on Debugger.sources enables O(1) lookup.

local uri_module = require("neodap.uri")

---Find source by location (matches by buffer URI)
---@param self neodap.entities.Debugger
---@param loc neodap.Location Location with path (buffer URI)
---@return neodap.entities.Source?
local function find(self, loc)
  for source in self.sources:iter() do
    if source:bufferUri() == loc.path then return source end
  end
end

---Find source by key (stable identifier, same as path)
---O(1) lookup using graph index
---@param self neodap.entities.Debugger
---@param key string Source key (path or name)
---@return neodap.entities.Source?
local function find_by_key(self, key)
  -- Use graph's by_key index for O(1) lookup
  for source in self.sources:filter({ filters = {{ field = "key", op = "eq", value = key }} }):iter() do
    return source  -- Return first match
  end
end

---Find source by path
---@param self neodap.entities.Debugger
---@param path string Source path
---@return neodap.entities.Source?
local function find_by_path(self, path)
  -- Use graph's by_path index for O(1) lookup
  for source in self.sources:filter({ filters = {{ field = "path", op = "eq", value = path }} }):iter() do
    return source  -- Return first match
  end
end

---Create a new source from location
---@param self neodap.entities.Debugger
---@param loc neodap.Location Location with path
---@return neodap.entities.Source
local function create(self, loc)
  -- Require inside function to avoid circular dependency
  local Source = require("neodap.entities").Source
  local source = Source.new(self._graph, {
    uri = uri_module.source(loc.path),
    key = loc.path,
    path = loc.path,
    name = vim.fn.fnamemodify(loc.path, ":t"),
  })
  self.sources:link(source)
  return source
end

---Find or create source for location
---@param self neodap.entities.Debugger
---@param loc neodap.Location Location with path
---@return neodap.entities.Source?
local function get_or_create(self, loc)
  if not loc or not loc.path then return nil end
  return find(self, loc) or create(self, loc)
end

return function(Debugger)
  Debugger.findSource = find
  Debugger.findSourceByKey = find_by_key
  Debugger.findSourceByPath = find_by_path
  Debugger.createSource = create
  Debugger.getOrCreateSource = get_or_create
end
