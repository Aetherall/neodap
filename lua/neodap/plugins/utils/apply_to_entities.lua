---Apply a method to all entities matching a type
---@param entities table[] Array of entities
---@param type_name string Entity type to match (e.g. "Thread", "Session")
---@param method_name string Method to call on each matching entity
---@param ... any Additional arguments to pass to the method
---@return number count Number of entities the method was applied to
return function(entities, type_name, method_name, ...)
  local count = 0
  for _, entity in ipairs(entities) do
    if entity:type() == type_name and entity[method_name] then
      entity[method_name](entity, ...)
      count = count + 1
    end
  end
  return count
end
