local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')

---@class BasePluginProps
---@field api Api
---@field logger Logger

---@class BasePlugin: BasePluginProps
---@field new Constructor<BasePluginProps>
---@field name string
---@field description string
local BasePlugin = Class()

-- Default name and description (should be overridden by subclasses)
BasePlugin.name = "BasePlugin"
BasePlugin.description = "Base class for neodap plugins"

---Creates a plugin instance using the standard pattern
---@param api Api
---@param plugin_class table The plugin class that extends BasePlugin
---@param custom_props? table Additional properties to include in initialization
---@return BasePlugin
function BasePlugin.createPlugin(api, plugin_class, custom_props)
  local logger = Logger.get("Plugin:" .. plugin_class.name)
  
  -- Merge standard props with custom props
  local props = vim.tbl_extend('force', {
    api = api,
    logger = logger,
  }, custom_props or {})
  
  local instance = plugin_class:new(props)
  
  -- Call standard lifecycle methods if they exist
  if instance.listen and type(instance.listen) == 'function' then
    instance:listen()
  end
  
  if instance.setupCommands and type(instance.setupCommands) == 'function' then
    instance:setupCommands()
  end
  
  if instance.setupAutocommands and type(instance.setupAutocommands) == 'function' then
    instance:setupAutocommands()
  end
  
  return instance
end

---Standard plugin factory method that subclasses can use
---@param api Api
---@return BasePlugin
function BasePlugin.plugin(api)
  return BasePlugin.createPlugin(api, BasePlugin)
end

---Default empty implementation for reactive listeners
---Subclasses should override this method
function BasePlugin:listen()
  -- Override in subclasses to set up event listeners
end

---Default empty implementation for command setup
---Subclasses should override this method  
function BasePlugin:setupCommands()
  -- Override in subclasses to register commands
end

---Register multiple commands using a simplified syntax
---@param command_specs table[] Array of {name, handler, opts} tuples
function BasePlugin:registerCommands(command_specs)
  for _, spec in ipairs(command_specs) do
    local name, handler, opts = spec[1], spec[2], spec[3] or {}
    vim.api.nvim_create_user_command(name, handler, opts)
  end
end

---Register a single command with method binding
---@param name string Command name
---@param method string Method name to call on self
---@param opts? table Command options
function BasePlugin:registerCommand(name, method, opts)
  vim.api.nvim_create_user_command(name, function(args)
    self[method](self, args)
  end, opts or {})
end

---Default empty implementation for autocommand setup
---Subclasses should override this method
function BasePlugin:setupAutocommands()
  -- Override in subclasses to set up autocommands
end

---Create a subclass that extends BasePlugin
---@return table
function BasePlugin:extend()
  return Class(self)
end

return BasePlugin