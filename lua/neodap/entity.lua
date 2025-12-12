-- Entity classes for neograph-native
--
-- Simple pattern:
-- 1. Entity classes are Lua metatables with methods
-- 2. Each class has a .new(graph, props) constructor
-- 3. Constructor sets metatable, inserts, attaches graph
-- 4. Methods use signals (neograph handles reactivity)

local M = {}

---Create an entity class with constructor
---@param type_name string
---@return table class
function M.class(type_name)
  local class = {}
  class.__index = class
  class._type_name = type_name

  ---Create a new entity
  ---@param graph table The neograph instance
  ---@param props? table Initial properties
  ---@return table node The created entity
  function class.new(graph, props)
    props = props or {}
    setmetatable(props, class)
    local node = graph:insert(type_name, props)
    node._graph = graph
    return node
  end

  -- Default __tostring
  function class:__tostring()
    return string.format("%s#%d", type_name, self._id or 0)
  end

  -- Default __eq compares by _id
  function class:__eq(other)
    return self._id == other._id
  end

  return class
end

---Add common methods to an entity class
---@param class table
function M.add_common_methods(class)
  function class:id()
    return self._id
  end

  function class:type()
    return self._type
  end

  function class:graph()
    return self._graph
  end

  function class:isDeleted()
    return self._graph:get(self._id) == nil
  end

  function class:update(props)
    self._graph:update(self._id, props)
  end

  function class:delete()
    self._graph:delete(self._id)
  end
end

return M
