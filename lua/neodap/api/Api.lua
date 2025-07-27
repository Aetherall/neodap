local Class = require("neodap.tools.class")
local Collection = require("neodap.tools.Collection")
local Session = require("neodap.api.Session.Session")
local Hookable = require("neodap.transport.hookable")
local VirtualBuffer = require('neodap.api.VirtualBuffer')

---@class ApiProps
---@field sessions Collection Session collection with id indexing
---@field listeners { [string]: fun(session: api.Session) }
---@field manager Manager
---@field hookable Hookable
---@field _plugin_cache { [string]: any }
---@field _virtual_buffer_registry VirtualBufferRegistry

---@class Api: ApiProps
---@field new Constructor<ApiProps>
local Api = Class()

---@return Api
function Api.register(manager)
  local registry = VirtualBuffer.createRegistry()
  
  local instance = Api:new({
    sessions = Collection.create({
      indexes = {
        id = {
          indexer = function(session) return session.id end,
          unique = true
        },
        status = {
          indexer = function(session) return session.status or "unknown" end,
          unique = false
        }
      }
    }),
    manager = manager,
    listeners = {},
    hookable = Hookable.create(), -- Top-level hookable for the entire API
    _plugin_cache = {},
    _virtual_buffer_registry = registry, -- Instance-scoped registry
  })

  -- Set this registry as the global singleton for SourceIdentifier access
  VirtualBuffer.Registry.setSingleton(registry)

  manager:onSession(function(session)
    local wrapped_session = Session.wrap(session, manager, instance.hookable, instance)
    instance.sessions:add(wrapped_session)
    for _, listener in pairs(instance.listeners) do
      listener(wrapped_session)
    end
  end, { name = "api" })

  return instance
end

---@param listener fun(session: api.Session)
function Api:onSession(listener, opts)
  opts = opts or {}
  local id = opts.name or math.random(1, 1000000) .. "_session_listener"

  self.listeners[id] = listener

  for session in self.sessions:each() do
    -- print("Calling existing session listener for session: " .. session.id)
    listener(session)
  end

  return function()
    self.listeners[id] = nil
  end
end

--- Iterable over all sessions
--- @return fun(): api.Session
function Api:eachSession()
  return self.sessions:each()
end

--- Get or create a plugin instance, ensuring single instance per API
---@generic T
---@param plugin_module { name: string, plugin: fun(api: Api): T }
---@return T
function Api:getPluginInstance(plugin_module)
  local name = plugin_module.name
  if not self._plugin_cache[name] then
    self._plugin_cache[name] = plugin_module.plugin(self)
  end
  return self._plugin_cache[name]
end

--- Load a plugin (supports both new module format and legacy function format)
---@param plugin_module { name: string, plugin: fun(api: Api): any } | fun(api: Api): any
---@return any plugin_instance
function Api:loadPlugin(plugin_module)
  if type(plugin_module) == "table" and plugin_module.plugin then
    -- New module format
    local instance = self:getPluginInstance(plugin_module)
    
    -- Apply base class extensions if defined
    if plugin_module.extends then
      for class_name, methods in pairs(plugin_module.extends) do
        local success, base_class = pcall(require, "neodap.api.Session." .. class_name)
        if not success then
          success, base_class = pcall(require, "neodap.api." .. class_name)
        end
        
        if success and base_class then
          for method_name, method_impl in pairs(methods) do
            base_class[method_name] = method_impl
          end
        end
      end
    end
    
    return instance
  else
    -- Legacy: direct function call
    return plugin_module(self)
  end
end

--- Destroy the API and clean up all plugins
function Api:destroy()
  local Logger = require("neodap.tools.logger")
  local log = Logger.get("API")
  
  log:info("API: Destroying API instance and cleaning up plugins")
  
  -- Call destroy() on all cached plugin instances
  for plugin_name, plugin_instance in pairs(self._plugin_cache) do
    if type(plugin_instance) == "table" and plugin_instance.destroy then
      log:debug("API: Calling destroy() on plugin:", plugin_name)
      pcall(plugin_instance.destroy)
    else
      log:debug("API: Plugin", plugin_name, "has no destroy method")
    end
  end
  
  -- Clear plugin cache after cleanup
  self._plugin_cache = {}
  
  -- Destroy virtual buffer registry
  if self._virtual_buffer_registry and self._virtual_buffer_registry.destroy then
    log:debug("API: Destroying virtual buffer registry")
    self._virtual_buffer_registry:destroy()
  end
  
  -- Clear the singleton reference to prevent dangling references
  local VirtualBuffer = require('neodap.api.VirtualBuffer')
  VirtualBuffer.Registry.setSingleton(nil)
  
  -- Destroy the hookable system last
  self.hookable:destroy()
  
  log:info("API: API instance destroyed successfully")
end

return Api
