local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")

Test.Describe("LaunchJsonSupport Plugin", function()

  Test.It("launch_json_configurations_loaded_successfully", function()
    -- Change to single-node-project fixture directory
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.api.nvim_set_current_dir(fixture_path)
    
    -- Prepare neodap instance
    local api, start = prepare.prepare()
    
    -- Load the LaunchJsonSupport plugin
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    -- Test basic plugin functionality
    assert(plugin ~= nil, "Plugin should load")
    assert(type(plugin.detectWorkspace) == "function", "Plugin should have detectWorkspace method")
    
    -- Test workspace detection
    local workspace = plugin:detectWorkspace()
    assert(workspace ~= nil, "Should detect workspace")
    assert(workspace.type == "single", "Should detect single workspace")
    
    -- Test configuration loading
    local configs = plugin:loadAllConfigurations()
    assert(type(configs) == "table", "Should return configurations table")
    
    print("✓ Plugin loaded successfully")
    print("✓ Workspace detected:", workspace.type)
    print("✓ Configuration count:", vim.tbl_count(configs))
    
    -- List configurations found
    for name, config in pairs(configs) do
      print("✓ Found configuration:", name, "->", config.originalName)
    end
  end)

end)