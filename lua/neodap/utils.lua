-- Shared utilities for neodap
local M = {}

---Normalize vim.NIL sentinel to nil
---@param value any
---@return any
function M.normalize(value)
  if value == vim.NIL then return nil end
  return value
end

---Resolve a property from a view item
---Checks item table first, then falls back to entity node proxy.
---@param item table View item (has .node and optionally .id)
---@param prop string Property name
---@param default any Default value if not found
---@param graph table? Optional graph for fallback lookup by item.id
---@return any
function M.get_prop(item, prop, default, graph)
  if item[prop] ~= nil then return item[prop] end
  local node = item.node or (graph and graph:get(item.id))
  if not node then return default end
  if prop == "type" then return node._type or default end
  local val = node[prop]
  if val == nil then return default end
  if type(val) == "table" and type(val.get) == "function" then
    local signal_val = val:get()
    if signal_val ~= nil then return signal_val end
    return default
  end
  return val
end

return M
