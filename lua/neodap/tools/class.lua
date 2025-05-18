---@alias Constructor<U> fun(self: self, opts: (U | fun(self: self): U)): self

function Class(parent)
  local class = {}

  -- process the parent
  if parent then
    -- create a shallow copy of the parent class
    for i, v in pairs(parent) do
      class[i] = v
    end

    class.__parent = parent
  end

  -- the class will be the metatable for all its instances
  -- and they will look up their methods in it
  class.__index = class

  function class:new(opts)
    local instance = {}
    if type(opts) == "function" then
      -- if opts is a function, we call it with self as the context
      -- and it should return a table with the instance properties
      local result = opts(instance)
      
      --- merge result into instance
      for k, v in pairs(result) do
        instance[k] = v
      end
      
    else
      -- otherwise, we assume opts is a table with properties
      instance = opts or {}
    end
    setmetatable(instance, self)
    self.__index = self
    return instance
  end

  return class;
end

return Class