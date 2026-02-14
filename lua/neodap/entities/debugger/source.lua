-- Source management methods for Debugger (neograph-native)
--
-- Performance note: Sources are indexed by key in the graph schema.
-- The `by_key` index on Debugger.sources enables O(1) lookup.

local uri = require("neodap.uri")

---Find a source by a single indexed field (O(1) lookup)
---@param self neodap.entities.Debugger
---@param field string Index field name ("key" or "path")
---@param value string Value to match
---@return neodap.entities.Source?
local function find_source_by(self, field, value)
  for source in self.sources:filter({ filters = {{ field = field, op = "eq", value = value }} }):iter() do
    return source
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
    uri = uri.source(loc.path),
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
  -- Use indexed lookups (O(1)) instead of linear scan
  return find_source_by(self, "path", loc.path) or find_source_by(self, "key", loc.path) or create(self, loc)
end

return function(Debugger)
  function Debugger:findSourceByKey(key) return find_source_by(self, "key", key) end
  function Debugger:findSourceByPath(path) return find_source_by(self, "path", path) end
  Debugger.getOrCreateSource = get_or_create
end
