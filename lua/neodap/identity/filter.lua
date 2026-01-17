-- Filter matching for identity wrappers

local ops = {
  eq = function(a, b) return a == b end,
  neq = function(a, b) return a ~= b end,
  gt = function(a, b) return a > b end,
  gte = function(a, b) return a >= b end,
  lt = function(a, b) return a < b end,
  lte = function(a, b) return a <= b end,
}

local function get_field_value(entity, field)
  local prop = entity[field]
  if prop and type(prop.get) == "function" then return prop:get() end
  return prop
end

local function matches(entity, filter)
  local val = get_field_value(entity, filter.field)
  local op = ops[filter.op]
  return op and op(val, filter.value) or false
end

local function matches_all(entity, filters)
  for _, f in ipairs(filters) do
    if not matches(entity, f) then return false end
  end
  return true
end

local function apply_filters(entities, filters)
  if not filters or #filters == 0 then return entities end
  local result = {}
  for _, entity in ipairs(entities) do
    if matches_all(entity, filters) then table.insert(result, entity) end
  end
  return result
end

return {
  matches = matches,
  matches_all = matches_all,
  apply_filters = apply_filters,
}
