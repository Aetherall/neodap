---@alias Constructor<U> fun(self: self, opts: (U | fun(self: self): U)): self

function Class(parent)
  local class = {}

  -- process the parent
  if parent then
    -- Use metatable delegation instead of shallow copying
    -- This allows dynamic method addition to parent classes
    setmetatable(class, { __index = parent })
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
    return instance
  end

  return class;
end

return Class