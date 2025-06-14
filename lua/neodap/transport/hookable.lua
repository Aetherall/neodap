local Class = require("neodap.tools.class")
local nio = require("nio")


---@class HookOptions
---@field name? string
---@field priority? number
---@field once? boolean

---@class HookProps<T>: { handler: string }
---@field name string
---@field key string
---@field priority number
---@field once boolean

---@class Hook: HookProps
---@field new Constructor<{}>
local Hook = Class()


---@class HookableProps<T>
---@field listeners { [string]?: { [number]?: { [string]?: Hook } } }

---@class Hookable: HookableProps
---@field new Constructor<HookableProps>
local Hookable = Class()


function Hookable.create()
  local instance = Hookable:new({
    listeners = {},
  })

  return instance
end

function Hookable:emit(key, event)
  local listeners = self.listeners[key]
  if listeners then
    for priority, group in pairs(listeners) do
      for name, hook in pairs(group) do
        nio.run(function()
          hook.handler(event)
        end)

        if hook.once then
          group[name] = nil
        end
      end
    end
  end
end

function Hookable:on(key, handler, opts)
  opts = opts or {}
  local name = opts.name or math.random(1, 1000000) .. "_" .. key
  local priority = opts.priority or 10
  local once = opts.once or false

  if not self.listeners[key] then
    self.listeners[key] = {}
  end

  if not self.listeners[key][priority] then
    self.listeners[key][priority] = {}
  end

  if self.listeners[key][priority][name] then
    error("Hook with name '" .. name .. "' already exists for event '" .. key .. "'")
  end

  self.listeners[key][priority][name] = Hook:new({
    name = name,
    event = key,
    handler = handler,
    priority = priority,
    once = once,
  })

  return function()
    self:off(key, name)
  end
end

function Hookable:off(key, name)
  if not self.listeners[key] then
    return
  end

  for priority, group in pairs(self.listeners[key]) do
    if group[name] then
      group[name] = nil
      if next(group) == nil then
        self.listeners[key][priority] = nil
      end
    end
  end

  if next(self.listeners[key]) == nil then
    self.listeners[key] = nil
  end
end

return Hookable
