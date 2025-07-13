local Class = require("neodap.tools.class")
local nio = require("nio")
local NvimAsync = require("neodap.tools.async")
-- local uv = nio.uv


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
---@field parent? Hookable
---@field children { [Hookable]: boolean }
---@field destroyed boolean

---@class Hookable: HookableProps
---@field new Constructor<HookableProps>
local Hookable = Class()


---@param parent? Hookable Optional parent Hookable for hierarchical cleanup
function Hookable.create(parent)
  local instance = Hookable:new({
    listeners = {},
    parent = parent,
    children = {},
    destroyed = false,
  })

  -- Register with parent if provided
  if parent and not parent.destroyed then
    parent.children[instance] = true
  end

  print("HOOKABLE_CREATE: Created hookable instance", tostring(instance), "destroyed:", instance.destroyed)
  return instance
end

---@return { wait: fun() }
function Hookable:emit(key, event)
  -- print("Emitting event: " .. key)
  
  -- Don't emit events on destroyed hookables
  if self.destroyed then
    local done = nio.control.future()
    done.set(true)
    return done
  end

  local listeners = self.listeners[key]
  if listeners then
    for priority, group in pairs(listeners) do
      for name, hook in pairs(group) do
          -- Use NvimAsync by default for all new handlers
        -- NvimAsync.run(hook.handler, event)
        if hook.once then
          group[name] = nil
        end
        -- Use simplified NvimAsync that preserves NIO context
        print("HOOKABLE_EMIT: Scheduling handler for", key, "hookable", tostring(self), "destroyed:", self.destroyed)
        vim.schedule(function ()
          print("HOOKABLE_EXECUTE: About to run handler for", key, "hookable", tostring(self), "destroyed:", self.destroyed)
        
        NvimAsync.run(hook.handler, event, {
          isPreempted = function() 
            local is_destroyed = self.destroyed
            print("HOOKABLE_PREEMPT_CHECK: isPreempted() called for hookable", tostring(self), "destroyed:", is_destroyed)
            return is_destroyed
          end
        })
      end)
      end
    end
  end
  
  -- Return a pre-resolved future for compatibility
  local done = nio.control.future()
  done.set(true)
  return done
end

function Hookable:on(key, handler, opts)
  -- print("+++++ Registering hook for event: " .. key .. " with handler: " .. (opts or { name = "anonymous"}).name)
  
  -- Prevent registration on destroyed hookables
  if self.destroyed then
    return function() end -- Return no-op cleanup function
  end
  
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

function Hookable:clearAll()
  self.listeners = {}
end

--- Destroys this Hookable and all its children, cleaning up all handlers
--- This method ensures complete cleanup of the handler hierarchy
function Hookable:destroy()
  if self.destroyed then
    return -- Already destroyed, avoid double cleanup
  end
  
  print("HOOKABLE_DESTROY: Destroying hookable instance", tostring(self))
  -- Mark as destroyed early to prevent new registrations
  self.destroyed = true
  print("HOOKABLE_DESTROY: Set destroyed=true for", tostring(self))
  
  -- Clean up all children first (depth-first cleanup)
  for child in pairs(self.children) do
    if not child.destroyed then
      child:destroy()
    end
  end
  
  -- Clear all our own listeners
  self:clearAll()
  
  -- Remove from parent's children list
  if self.parent and not self.parent.destroyed then
    self.parent.children[self] = nil
  end
  
  -- Clear references to prevent memory leaks
  self.children = {}
  self.parent = nil
end

return Hookable
