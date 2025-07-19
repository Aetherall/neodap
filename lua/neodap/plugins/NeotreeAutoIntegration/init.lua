local Class = require("neodap.tools.class")
local Logger = require("neodap.tools.logger")

---@class NeotreeAutoIntegrationProps
---@field api Api

---@class NeotreeAutoIntegration: NeotreeAutoIntegrationProps
---@field new Constructor<NeotreeAutoIntegrationProps>
local NeotreeAutoIntegration = Class()

NeotreeAutoIntegration.name = "NeotreeAutoIntegration"
NeotreeAutoIntegration.description = "Automatic hybrid Neo-tree source registration for neodap plugins"

function NeotreeAutoIntegration.plugin(api)
  local logger = Logger.get("Plugin:NeotreeAutoIntegration")
  
  local instance = NeotreeAutoIntegration:new({
    api = api,
    logger = logger
  })
  
  instance:init()
  return instance
end

function NeotreeAutoIntegration:init()
  self.registered_sources = {}
  self.logger:info("NeotreeAutoIntegration initialized")
end

-- Register a source with hybrid auto-configuration
function NeotreeAutoIntegration:registerSource(source_module, options)
  options = options or {}
  
  local source_name = source_module.name
  if not source_name then
    self.logger:error("Source module must have a 'name' property")
    return false
  end
  
  if self.registered_sources[source_name] then
    self.logger:debug("Source already registered:", source_name)
    return true
  end
  
  self.logger:info("Registering Neo-tree source:", source_name)
  
  vim.schedule(function()
    local success = self:performHybridRegistration(source_module, options)
    if success then
      self.registered_sources[source_name] = {
        module = source_module,
        options = options,
        registered_at = os.time()
      }
      self.logger:info("Successfully registered source:", source_name)
    else
      self.logger:error("Failed to register source:", source_name)
    end
  end)
  
  return true
end

-- Core hybrid configuration logic (not registration - source must already be requireable)
function NeotreeAutoIntegration:performHybridRegistration(source_module, options)
  local neotree_ok, neotree = pcall(require, "neo-tree")
  if not neotree_ok then
    self.logger:debug("Neo-tree not available, skipping integration")
    return false
  end
  
  -- Check if user has already configured this source
  local config = {}
  if neotree.get_config then
    config = neotree.get_config() or {}
  end
  
  local sources = config.sources or {}
  local source_name = source_module.name
  
  -- Better detection: check for source-specific config, not just sources list
  local user_has_configured_us = config[source_name] ~= nil
  local user_has_listed_us = vim.tbl_contains(sources, source_name)
  
  -- Verify the source module is actually requireable
  local source_ok, source = pcall(require, source_name)
  if not source_ok then
    self.logger:error("Source module not requireable:", source_name)
    return false
  end
  
  self.logger:debug("Source module is requireable, proceeding with configuration")
  
  if user_has_configured_us or user_has_listed_us then
    -- User has configured us, respect their setup
    self.logger:info("User has configured source, respecting existing setup:", source_name)
    return true
  end
  
  -- Check for opt-out
  if vim.g.neodap_disable_neotree_autoconfig then
    self.logger:info("Auto-configuration disabled by user setting")
    return true
  end
  
  -- User hasn't configured us, apply sensible defaults
  self.logger:info("Applying auto-configuration for:", source_name)
  
  local default_config = self:buildDefaultConfig(source_module, options)
  local new_sources = vim.list_extend(vim.deepcopy(sources), {source_name})
  
  local enhanced_config = vim.tbl_extend("force", config, {
    sources = new_sources,
    [source_name] = default_config
  })
  
  local setup_ok, setup_err = pcall(neotree.setup, enhanced_config)
  if not setup_ok then
    self.logger:error("Failed to setup Neo-tree:", setup_err)
    return false
  end
  
  -- Provide user feedback
  local feedback_msg = string.format(
    "🌳 Auto-configured Neo-tree source '%s'. Use ':Neotree float %s' to open.",
    source_module.display_name or source_name,
    source_name
  )
  
  if options.silent ~= true then
    vim.notify(feedback_msg, vim.log.levels.INFO)
  end
  
  self.logger:info("Auto-configuration completed:", source_name)
  return true
end

-- Build default configuration for a source
function NeotreeAutoIntegration:buildDefaultConfig(source_module, options)
  local defaults = {
    window = {
      position = "float",
      mappings = {
        ["<cr>"] = "toggle_node",
        ["<space>"] = "toggle_node", 
        ["o"] = "toggle_node",
        ["q"] = "close_window",
        ["<esc>"] = "close_window",
      },
    },
    popup = {
      size = { height = "60%", width = "50%" },
      position = "50%", -- center
    },
  }
  
  -- Merge with user-provided options
  if options.default_config then
    defaults = vim.tbl_deep_extend("force", defaults, options.default_config)
  end
  
  return defaults
end

-- Get registration status for a source
function NeotreeAutoIntegration:getSourceStatus(source_name)
  return self.registered_sources[source_name]
end

-- List all registered sources
function NeotreeAutoIntegration:listRegisteredSources()
  local sources = {}
  for name, info in pairs(self.registered_sources) do
    table.insert(sources, {
      name = name,
      display_name = info.module.display_name,
      registered_at = info.registered_at
    })
  end
  return sources
end

-- Cleanup on destruction
function NeotreeAutoIntegration:destroy()
  self.logger:info("Cleaning up NeotreeAutoIntegration")
  
  -- Clear registered sources (can't actually unregister from Neo-tree)
  self.registered_sources = {}
  
  self.logger:info("NeotreeAutoIntegration destroyed")
end

return NeotreeAutoIntegration