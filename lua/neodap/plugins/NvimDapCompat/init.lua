local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Session = require("neodap.session.session")
local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")

---@class NvimDapCompatPlugin
---@field importAdapters fun(): table
---@field importConfigurations fun(): table
---@field createSessionFromNvimDapConfig fun(config: table, manager: Manager): Session
---@field transformAdapter fun(nvim_dap_adapter: any): any
---@field transformConfiguration fun(config: table): table
---@field generateMigrationReport fun(): string
---@field migrateFromNvimDap fun(): table

---@class NvimDapCompatProps
---@field api Api
---@field logger Logger
---@field imported_adapters table?
---@field imported_configs table?
---@field dap_available boolean

---@class NvimDapCompat: NvimDapCompatProps
---@field new Constructor<NvimDapCompatProps>
local NvimDapCompat = Class()

NvimDapCompat.name = "NvimDapCompat"
NvimDapCompat.description = "nvim-dap compatibility layer for seamless migration"

function NvimDapCompat.plugin(api)
  local logger = Logger.get("Plugin:NvimDapCompat")
  
  local instance = NvimDapCompat:new({
    api = api,
    logger = logger,
    imported_adapters = nil,
    imported_configs = nil,
    dap_available = false,
  })
  
  -- Check if nvim-dap is available
  instance.dap_available = instance:isNvimDapAvailable()
  
  instance:registerCommands()
  return instance
end

---Check if nvim-dap is available
---@return boolean
function NvimDapCompat:isNvimDapAvailable()
  local ok, _ = pcall(require, "dap")
  return ok
end

---Get nvim-dap module safely
---@return table?
function NvimDapCompat:getNvimDap()
  if not self.dap_available then
    return nil
  end
  
  local ok, dap = pcall(require, "dap")
  if not ok then
    return nil
  end
  
  return dap
end

---Transform nvim-dap adapter to neodap adapter
---@param nvim_dap_adapter any
---@param adapter_name string
---@return any
function NvimDapCompat:transformAdapter(nvim_dap_adapter, adapter_name)
  if type(nvim_dap_adapter) == "table" then
    if nvim_dap_adapter.type == "executable" then
      return ExecutableTCPAdapter.create({
        executable = {
          cmd = nvim_dap_adapter.command,
          cwd = nvim_dap_adapter.cwd or vim.fn.getcwd(),
        },
        connection = { host = "::1" }
      })
    elseif nvim_dap_adapter.type == "server" then
      -- Handle server-based adapters
      local executable = nvim_dap_adapter.executable
      if executable then
        return ExecutableTCPAdapter.create({
          executable = {
            cmd = executable.command,
            cwd = executable.cwd or vim.fn.getcwd(),
          },
          connection = {
            host = nvim_dap_adapter.host or "127.0.0.1",
            port = nvim_dap_adapter.port,
          }
        })
      else
        self.logger:warn("Server adapter without executable not fully supported:", adapter_name)
        return nil
      end
    else
      self.logger:warn("Unknown nvim-dap adapter type:", nvim_dap_adapter.type, "for adapter:", adapter_name)
      return nil
    end
  elseif type(nvim_dap_adapter) == "function" then
    -- Handle function-based adapters with a wrapper
    local function_adapter = {
      start = function(opts)
        local send_fn, close_fn
        local callback_called = false
        
        -- Create a callback that will be called by the nvim-dap adapter
        nvim_dap_adapter(function(adapter_info)
          if callback_called then
            return
          end
          callback_called = true
          
          -- Transform the adapter info to neodap format
          local transformed = self:transformAdapter(adapter_info, adapter_name .. "_resolved")
          if transformed then
            send_fn, close_fn = transformed:start(opts)
          else
            self.logger:error("Failed to transform function adapter result for:", adapter_name)
          end
        end, {})
        
        -- Return functions that delegate to the resolved adapter
        return function(message)
          if send_fn then
            send_fn(message)
          end
        end, function()
          if close_fn then
            close_fn()
          end
        end
      end
    }
    
    return function_adapter
  end
  
  self.logger:warn("Unsupported nvim-dap adapter type:", type(nvim_dap_adapter), "for adapter:", adapter_name)
  return nil
end

---Import nvim-dap adapters
---@return table
function NvimDapCompat:importAdapters()
  if not self.dap_available then
    self.logger:error("nvim-dap is not available")
    return {}
  end
  
  if self.imported_adapters then
    return self.imported_adapters
  end
  
  local dap = self:getNvimDap()
  if not dap then
    return {}
  end
  
  local adapters = {}
  local success_count = 0
  local total_count = 0
  
  for name, adapter_config in pairs(dap.adapters or {}) do
    total_count = total_count + 1
    local transformed = self:transformAdapter(adapter_config, name)
    if transformed then
      adapters[name] = transformed
      success_count = success_count + 1
      self.logger:info("Imported nvim-dap adapter:", name)
    else
      self.logger:warn("Failed to import nvim-dap adapter:", name)
    end
  end
  
  self.imported_adapters = adapters
  self.logger:info("Imported", success_count, "out of", total_count, "nvim-dap adapters")
  
  return adapters
end

---Transform nvim-dap configuration to neodap format
---@param config table
---@return table
function NvimDapCompat:transformConfiguration(config)
  local transformed = vim.deepcopy(config)
  
  -- nvim-dap and neodap use similar configuration formats
  -- Main differences are in adapter references
  
  -- Remove nvim-dap specific fields that neodap doesn't need
  -- Keep the type field for now as it's used for adapter lookup
  
  return transformed
end

---Import nvim-dap configurations
---@return table
function NvimDapCompat:importConfigurations()
  if not self.dap_available then
    self.logger:error("nvim-dap is not available")
    return {}
  end
  
  if self.imported_configs then
    return self.imported_configs
  end
  
  local dap = self:getNvimDap()
  if not dap then
    return {}
  end
  
  local configs = {}
  local total_configs = 0
  
  for filetype, ft_configs in pairs(dap.configurations or {}) do
    configs[filetype] = {}
    for _, config in ipairs(ft_configs) do
      local transformed = self:transformConfiguration(config)
      table.insert(configs[filetype], transformed)
      total_configs = total_configs + 1
    end
    self.logger:info("Imported", #ft_configs, "configurations for", filetype)
  end
  
  self.imported_configs = configs
  self.logger:info("Imported", total_configs, "total configurations")
  
  return configs
end

---Create session from nvim-dap configuration
---@param config table
---@param manager Manager
---@return Session
function NvimDapCompat:createSessionFromNvimDapConfig(config, manager)
  local adapters = self:importAdapters()
  local adapter = adapters[config.type]
  
  if not adapter then
    error("No adapter found for type: " .. tostring(config.type))
  end
  
  self.logger:info("Creating session from nvim-dap config:", config.name or "unnamed")
  
  local session = Session.create({
    manager = manager,
    adapter = adapter,
  })
  
  -- Transform configuration and start session
  local transformed_config = self:transformConfiguration(config)
  -- Remove type field from the actual session config
  transformed_config.type = nil
  
  session:start({
    configuration = transformed_config,
    request = config.request or "launch",
  })
  
  return session
end

---Generate migration report
---@return string
function NvimDapCompat:generateMigrationReport()
  if not self.dap_available then
    return "nvim-dap is not available - no migration needed"
  end
  
  local dap = self:getNvimDap()
  if not dap then
    return "Failed to load nvim-dap module"
  end
  
  local report = {}
  
  table.insert(report, "=== nvim-dap Migration Report ===\n")
  
  -- Adapter analysis
  local adapter_count = 0
  local supported_adapters = 0
  local adapter_details = {}
  
  for name, adapter_config in pairs(dap.adapters or {}) do
    adapter_count = adapter_count + 1
    local supported = self:transformAdapter(adapter_config, name) ~= nil
    if supported then
      supported_adapters = supported_adapters + 1
    end
    
    local adapter_type = type(adapter_config)
    if adapter_type == "table" then
      adapter_type = adapter_config.type or "unknown"
    end
    
    table.insert(adapter_details, string.format("  %s (%s): %s", name, adapter_type,
      supported and "✓ Supported" or "✗ Needs manual migration"))
  end
  
  table.insert(report, "Adapters:")
  for _, detail in ipairs(adapter_details) do
    table.insert(report, detail)
  end
  
  table.insert(report, string.format("\nAdapter Summary: %d total, %d supported (%.1f%%)", 
    adapter_count, supported_adapters, adapter_count > 0 and (supported_adapters / adapter_count * 100) or 0))
  
  -- Configuration analysis
  local config_count = 0
  local config_details = {}
  
  for filetype, ft_configs in pairs(dap.configurations or {}) do
    config_count = config_count + #ft_configs
    table.insert(config_details, string.format("  %s: %d configurations", filetype, #ft_configs))
  end
  
  table.insert(report, "\nConfigurations:")
  for _, detail in ipairs(config_details) do
    table.insert(report, detail)
  end
  
  table.insert(report, string.format("\nConfiguration Summary: %d total configurations", config_count))
  
  -- Migration recommendations
  table.insert(report, "\n=== Migration Steps ===")
  table.insert(report, "1. Run :NeodapImportNvimDap to import compatible configurations")
  table.insert(report, "2. Test imported configurations with :NeodapRunNvimDapConfig")
  table.insert(report, "3. Manually migrate unsupported adapters")
  table.insert(report, "4. Update your configuration to use neodap directly")
  
  if supported_adapters < adapter_count then
    table.insert(report, "\n=== Manual Migration Required ===")
    for name, adapter_config in pairs(dap.adapters or {}) do
      local supported = self:transformAdapter(adapter_config, name) ~= nil
      if not supported then
        table.insert(report, string.format("  - %s: %s", name, type(adapter_config)))
      end
    end
  end
  
  return table.concat(report, "\n")
end

---Migrate from nvim-dap setup
---@return table
function NvimDapCompat:migrateFromNvimDap()
  local adapters = self:importAdapters()
  local configs = self:importConfigurations()
  
  local migration_result = {
    adapters = adapters,
    configurations = configs,
    adapter_count = vim.tbl_count(adapters),
    config_count = 0,
    filetypes = vim.tbl_keys(configs)
  }
  
  for _, ft_configs in pairs(configs) do
    migration_result.config_count = migration_result.config_count + #ft_configs
  end
  
  return migration_result
end

---Get all imported configurations as a flat list
---@return table
function NvimDapCompat:getAllImportedConfigurations()
  local configs = self:importConfigurations()
  local all_configs = {}
  
  for filetype, ft_configs in pairs(configs) do
    for _, config in ipairs(ft_configs) do
      table.insert(all_configs, {
        name = config.name or ("Unnamed " .. filetype),
        filetype = filetype,
        config = config,
      })
    end
  end
  
  return all_configs
end

---Register user commands
function NvimDapCompat:registerCommands()
  -- Import nvim-dap configurations
  vim.api.nvim_create_user_command("NeodapImportNvimDap", function()
    if not self.dap_available then
      vim.notify("nvim-dap is not available", vim.log.levels.ERROR)
      return
    end
    
    local migration_result = self:migrateFromNvimDap()
    
    vim.notify(string.format("Imported %d adapters and %d configurations from nvim-dap", 
      migration_result.adapter_count, migration_result.config_count), vim.log.levels.INFO)
  end, { desc = "Import nvim-dap configurations" })
  
  -- Migration report
  vim.api.nvim_create_user_command("NeodapMigrationReport", function()
    local report = self:generateMigrationReport()
    vim.api.nvim_echo({{report, "Normal"}}, true, {})
  end, { desc = "Generate nvim-dap migration report" })
  
  -- Run imported configuration
  vim.api.nvim_create_user_command("NeodapRunNvimDapConfig", function(opts)
    if not self.dap_available then
      vim.notify("nvim-dap is not available", vim.log.levels.ERROR)
      return
    end
    
    local config_name = opts.args
    
    if config_name == "" then
      -- Show picker
      local all_configs = self:getAllImportedConfigurations()
      
      if #all_configs == 0 then
        vim.notify("No nvim-dap configurations found. Run :NeodapImportNvimDap first.", vim.log.levels.WARN)
        return
      end
      
      vim.ui.select(all_configs, {
        prompt = "Select nvim-dap configuration:",
        format_item = function(item)
          return string.format("%s (%s)", item.name, item.filetype)
        end,
      }, function(choice)
        if choice then
          self:createSessionFromNvimDapConfig(choice.config, self.api.manager)
        end
      end)
    else
      -- Find configuration by name
      local all_configs = self:getAllImportedConfigurations()
      local found_config = nil
      
      for _, config_item in ipairs(all_configs) do
        if config_item.name == config_name then
          found_config = config_item
          break
        end
      end
      
      if found_config then
        self:createSessionFromNvimDapConfig(found_config.config, self.api.manager)
      else
        vim.notify("Configuration not found: " .. config_name, vim.log.levels.ERROR)
      end
    end
  end, { 
    nargs = "?",
    complete = function()
      local all_configs = self:getAllImportedConfigurations()
      local names = {}
      for _, config_item in ipairs(all_configs) do
        table.insert(names, config_item.name)
      end
      return names
    end,
    desc = "Run imported nvim-dap configuration"
  })
  
  -- Clear imported configurations
  vim.api.nvim_create_user_command("NeodapClearImported", function()
    self.imported_adapters = nil
    self.imported_configs = nil
    vim.notify("Cleared imported nvim-dap configurations", vim.log.levels.INFO)
  end, { desc = "Clear cached imported nvim-dap configurations" })
end

return NvimDapCompat