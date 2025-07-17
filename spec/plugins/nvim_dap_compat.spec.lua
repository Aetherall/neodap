local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare")

Test.Describe("NvimDapCompat Plugin", function()

  Test.It("migration_report_shows_compatibility", function()
    local api, start = prepare.prepare()
    -- Load basic nvim-dap configuration fixture
    local config_path = vim.fn.fnamemodify("spec/fixtures/nvim-dap-configs/basic-setup.lua", ":p")
    local dap_config = dofile(config_path)
    package.loaded["dap"] = dap_config
    
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Generate migration report
    Test.RunCommand("NeodapMigrationReport")
    
    -- Should show compatibility report
    Test.TerminalSnapshot("migration_report_displayed")
    
    -- Should contain expected information from fixture
    local messages = Test.CaptureMessages()
    assert(string.match(messages, "=== nvim-dap Migration Report ==="))
    assert(string.match(messages, "Adapter node (executable): ✓ Supported"))
    assert(string.match(messages, "Adapter python (server): ✓ Supported"))
    assert(string.match(messages, "javascript: 2 configurations"))
    assert(string.match(messages, "python: 1 configurations"))
  end)

  Test.It("imports_basic_nvim_dap_setup", function()
    local api, start = prepare.prepare()
    -- Load basic nvim-dap configuration fixture
    local config_path = vim.fn.fnamemodify("spec/fixtures/nvim-dap-configs/basic-setup.lua", ":p")
    local dap_config = dofile(config_path)
    package.loaded["dap"] = dap_config
    
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Import configurations
    Test.RunCommand("NeodapImportNvimDap")
    
    -- Should show import success
    Test.TerminalSnapshot("basic_nvim_dap_import_success")
    
    -- Should display import summary
    local messages = Test.CaptureMessages()
    assert(string.match(messages, "Imported 2 adapters and 3 configurations"))
  end)

  Test.It("imports_complex_nvim_dap_setup", function()
    local api, start = prepare.prepare()
    -- Load complex nvim-dap configuration fixture
    local config_path = vim.fn.fnamemodify("spec/fixtures/nvim-dap-configs/complex-setup.lua", ":p")
    local dap_config = dofile(config_path)
    package.loaded["dap"] = dap_config
    
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Import configurations
    Test.RunCommand("NeodapImportNvimDap")
    
    -- Should show import success
    Test.TerminalSnapshot("complex_nvim_dap_import_success")
    
    -- Should handle multiple languages and adapters
    local messages = Test.CaptureMessages()
    assert(string.match(messages, "Imported 3 adapters and 5 configurations"))
  end)

  Test.It("handles_function_based_adapters", function()
    local api, start = prepare.prepare()
    -- Load function-adapters fixture
    local config_path = vim.fn.fnamemodify("spec/fixtures/nvim-dap-configs/function-adapters.lua", ":p")
    local dap_config = dofile(config_path)
    package.loaded["dap"] = dap_config
    
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Test function adapter import
    Test.RunCommand("NeodapImportNvimDap")
    Test.RunCommand("NeodapMigrationReport")
    
    -- Should handle function adapters from fixture
    Test.TerminalSnapshot("function_adapter_handled")
    
    local messages = Test.CaptureMessages()
    assert(string.match(messages, "Adapter custom (function): ✓ Supported"))
    assert(string.match(messages, "Adapter conditional (function): ✓ Supported"))
  end)

  Test.It("runs_imported_configuration", function()
    local api, start = prepare.prepare()
    -- Load basic nvim-dap configuration
    local config_path = vim.fn.fnamemodify("spec/fixtures/nvim-dap-configs/basic-setup.lua", ":p")
    local dap_config = dofile(config_path)
    package.loaded["dap"] = dap_config
    
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Import configurations
    nvim_dap_compat:migrateFromNvimDap()
    
    -- Run imported configuration
    Test.RunCommand("NeodapRunNvimDapConfig")
    
    -- Should show configuration picker
    Test.TerminalSnapshot("nvim_dap_config_picker")
    
    -- Should list available configurations
    local messages = Test.CaptureMessages()
    assert(string.match(messages, "Select nvim-dap configuration"))
    assert(string.match(messages, "Launch Node (javascript)"))
    assert(string.match(messages, "Launch Python (python)"))
  end)

  Test.It("transforms_executable_adapter_correctly", function()
    local api, start = prepare.prepare()
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Test executable adapter transformation
    local nvim_dap_adapter = {
      type = "executable",
      command = "js-debug",
      cwd = "/test/path"
    }
    
    local transformed = nvim_dap_compat:transformAdapter(nvim_dap_adapter, "test_node")
    
    -- Should create ExecutableTCPAdapter
    assert(transformed ~= nil)
    assert(type(transformed.start) == "function")
  end)

  Test.It("transforms_server_adapter_correctly", function()
    local api, start = prepare.prepare()
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Test server adapter transformation
    local nvim_dap_adapter = {
      type = "server",
      port = 5678,
      executable = {
        command = "python",
        args = {"-m", "debugpy.adapter"}
      }
    }
    
    local transformed = nvim_dap_compat:transformAdapter(nvim_dap_adapter, "test_python")
    
    -- Should create ExecutableTCPAdapter
    assert(transformed ~= nil)
    assert(type(transformed.start) == "function")
  end)

  Test.It("transforms_configuration_correctly", function()
    local api, start = prepare.prepare()
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Test configuration transformation
    local nvim_dap_config = {
      name = "Test Config",
      type = "node",
      request = "launch",
      program = "${workspaceFolder}/app.js",
      cwd = "${workspaceFolder}",
      env = {
        NODE_ENV = "development"
      }
    }
    
    local transformed = nvim_dap_compat:transformConfiguration(nvim_dap_config)
    
    -- Should preserve most fields
    assert(transformed.name == "Test Config")
    assert(transformed.type == "node")
    assert(transformed.request == "launch")
    assert(transformed.program == "${workspaceFolder}/app.js")
    assert(transformed.cwd == "${workspaceFolder}")
    assert(transformed.env.NODE_ENV == "development")
  end)

  Test.It("handles_missing_nvim_dap_gracefully", function()
    local api, start = prepare.prepare()
    -- Ensure nvim-dap is not available
    package.loaded["dap"] = nil
    
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Should handle missing nvim-dap
    assert(nvim_dap_compat.dap_available == false)
    
    -- Commands should show appropriate messages
    Test.RunCommand("NeodapImportNvimDap")
    Test.TerminalSnapshot("nvim_dap_not_available")
    
    local messages = Test.CaptureMessages()
    assert(string.match(messages, "nvim-dap is not available"))
  end)

  Test.It("clears_imported_configurations", function()
    local api, start = prepare.prepare()
    -- Load basic nvim-dap configuration
    local config_path = vim.fn.fnamemodify("spec/fixtures/nvim-dap-configs/basic-setup.lua", ":p")
    local dap_config = dofile(config_path)
    package.loaded["dap"] = dap_config
    
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Import configurations
    nvim_dap_compat:migrateFromNvimDap()
    
    -- Verify configurations are cached
    assert(nvim_dap_compat.imported_configs ~= nil)
    assert(nvim_dap_compat.imported_adapters ~= nil)
    
    -- Clear configurations
    Test.RunCommand("NeodapClearImported")
    
    -- Should clear cache
    assert(nvim_dap_compat.imported_configs == nil)
    assert(nvim_dap_compat.imported_adapters == nil)
    
    -- Should show clear message
    Test.TerminalSnapshot("imported_configs_cleared")
    
    local messages = Test.CaptureMessages()
    assert(string.match(messages, "Cleared imported nvim-dap configurations"))
  end)

  Test.It("migration_workflow_complete", function()
    local api, start = prepare.prepare()
    -- Load complete nvim-dap setup
    local config_path = vim.fn.fnamemodify("spec/fixtures/nvim-dap-configs/basic-setup.lua", ":p")
    local dap_config = dofile(config_path)
    package.loaded["dap"] = dap_config
    
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Complete migration workflow
    Test.CommandSequence({
      "NeodapMigrationReport",
      {"wait", "report_displayed"},
      "NeodapImportNvimDap",
      {"wait", "import_completed"},
      "NeodapRunNvimDapConfig Launch Node",
      {"wait", "session_started"},
      {"cursor", {3, 0}},
      "NeodapBreakpointToggle",
      {"wait", "thread_stopped"},
      "NeodapStop"
    })
    
    -- Should complete full migration and debug workflow
    Test.TerminalSnapshot("migration_workflow_complete")
  end)

  Test.It("generates_comprehensive_migration_report", function()
    local api, start = prepare.prepare()
    -- Load complex nvim-dap configuration
    local config_path = vim.fn.fnamemodify("spec/fixtures/nvim-dap-configs/complex-setup.lua", ":p")
    local dap_config = dofile(config_path)
    package.loaded["dap"] = dap_config
    
    -- Load the plugin
    local nvim_dap_compat = api:loadPlugin(require("neodap.plugins.NvimDapCompat"))
    
    -- Generate detailed report
    local report = nvim_dap_compat:generateMigrationReport()
    
    -- Should contain comprehensive information
    assert(string.match(report, "=== nvim-dap Migration Report ==="))
    assert(string.match(report, "Adapter Summary:"))
    assert(string.match(report, "Configuration Summary:"))
    assert(string.match(report, "=== Migration Steps ==="))
    assert(string.match(report, "Run :NeodapImportNvimDap"))
    assert(string.match(report, "Test imported configurations"))
    assert(string.match(report, "Manually migrate unsupported adapters"))
  end)


end)