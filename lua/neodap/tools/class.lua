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
  
  -- Auto-wrapping for uppercase methods on instances
  class.__newindex = function(self, key, value)
    -- Check if this is a function with uppercase first letter
    if type(value) == "function" and type(key) == "string" then
      local first_char = key:sub(1, 1)
      if first_char == first_char:upper() and first_char ~= first_char:lower() then
        -- This is an uppercase method - auto-wrap with NvimAsync.defer
        local NvimAsync = require("neodap.tools.async")
        local wrapped_func = NvimAsync.defer(function(...)
          return value(...)
        end)
        rawset(self, key, wrapped_func)
        return
      end
    end
    -- Regular assignment for non-uppercase methods
    rawset(self, key, value)
  end

  -- Auto-wrapping for uppercase methods on the class itself
  local class_newindex = function(self, key, value)
    -- Check if this is a function with uppercase first letter
    if type(value) == "function" and type(key) == "string" then
      local first_char = key:sub(1, 1)
      if first_char == first_char:upper() and first_char ~= first_char:lower() then
        -- This is an uppercase method - auto-wrap with NvimAsync.defer
        local NvimAsync = require("neodap.tools.async")
        local wrapped_func = NvimAsync.defer(function(...)
          return value(...)
        end)
        rawset(self, key, wrapped_func)
        return
      end
    end
    -- Regular assignment for non-uppercase methods
    rawset(self, key, value)
  end

  -- Set metamethod on the class itself to intercept method definitions
  setmetatable(class, { __newindex = class_newindex })

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