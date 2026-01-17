-- Shared quickfix utilities for entity display
-- Used by command_router, list_cmd, and other plugins that populate quickfix

local format = require("neodap.plugins.utils.format")

local M = {}

---Convert an entity to a quickfix entry
---@param entity any Entity to convert
---@return table entry Quickfix entry
function M.entry(entity)
  local entry = {
    -- Store both URI and internal ID to avoid needing a second query
    -- URI is for display/debugging, ID is for efficient db:get() lookup
    user_data = {
      uri = entity.uri:get(),
      id = entity:id(),
      entity_type = entity:type(),
    },
    text = format.entity(entity),
  }

  -- Use :location() method if available (Breakpoint, Frame, Source, Output)
  if type(entity.location) == "function" then
    local loc = entity:location()
    if loc then
      entry.filename = loc.path
      entry.lnum = loc.line or 1
      entry.col = loc.column or 1
    end
  end

  return entry
end

---Convert array of entities to quickfix entries
---@param entities any[] Array of entities
---@return table[] entries Array of quickfix entries
function M.entries(entities)
  local items = {}
  for _, entity in ipairs(entities) do
    table.insert(items, M.entry(entity))
  end
  return items
end

return M
