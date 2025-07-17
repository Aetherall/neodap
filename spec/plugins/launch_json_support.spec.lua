local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")

Test.Describe("LaunchJsonSupport Plugin", function()

  Test.It("detects_single_folder_workspace", function()
    local api, start = prepare.prepare()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    -- Mock single folder workspace
    local workspace_info = plugin:detectWorkspace("/home/user/project")
    
    assert(workspace_info.type == "single")
    assert(workspace_info.rootPath == "/home/user/project")
    assert(#workspace_info.folders == 1)
    assert(workspace_info.folders[1].name == "project")
  end)

  Test.It("parses_multi_root_workspace_file", function()
    local api, start = prepare.prepare()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    -- Create a temporary workspace file
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    
    local workspace_content = {
      '{"folders": [',
      '  {"name": "Frontend", "path": "./frontend"},',
      '  {"name": "Backend", "path": "./backend"}',
      ']}'
    }
    
    local workspace_file = temp_dir .. "/test.code-workspace"
    vim.fn.writefile(workspace_content, workspace_file)
    
    local workspace_info = plugin:parseMultiRootWorkspace(workspace_file)
    
    assert(workspace_info.type == "multi-root")
    assert(#workspace_info.folders == 2)
    assert(workspace_info.folders[1].name == "Frontend")
    assert(workspace_info.folders[2].name == "Backend")
    
    -- Cleanup
    vim.fn.delete(temp_dir, "rf")
  end)

  Test.It("substitutes_variables_in_single_folder_workspace", function()
    local api, start = prepare.prepare()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    local config = {
      program = "${workspaceFolder}/src/index.js",
      cwd = "${workspaceFolder}",
      args = {"${fileBasename}"}
    }
    
    local context = {
      workspaceInfo = {
        type = "single",
        rootPath = "/home/user/project",
        folders = {{
          name = "project",
          path = ".",
          absolutePath = "/home/user/project"
        }}
      }
    }
    
    local substituted = plugin:substituteVariables(config, context)
    
    assert(substituted.program == "/home/user/project/src/index.js")
    assert(substituted.cwd == "/home/user/project")
  end)

  Test.It("substitutes_scoped_variables_in_multi_root_workspace", function()
    local api, start = prepare.prepare()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    local config = {
      program = "${workspaceFolder:Frontend}/src/index.js",
      cwd = "${workspaceFolder:Backend}",
      args = {"${workspaceFolder}"}
    }
    
    local context = {
      workspaceInfo = {
        type = "multi-root",
        rootPath = "/home/user/workspace",
        folders = {
          {
            name = "Frontend",
            path = "./frontend",
            absolutePath = "/home/user/workspace/frontend"
          },
          {
            name = "Backend",
            path = "./backend",
            absolutePath = "/home/user/workspace/backend"
          }
        }
      }
    }
    
    local substituted = plugin:substituteVariables(config, context)
    
    assert(substituted.program == "/home/user/workspace/frontend/src/index.js")
    assert(substituted.cwd == "/home/user/workspace/backend")
    assert(substituted.args[1] == "/home/user/workspace")
  end)

  Test.It("creates_namespaced_configuration_names", function()
    local api, start = prepare.prepare()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    local folder = {
      name = "Frontend",
      path = "./frontend",
      absolutePath = "/home/user/workspace/frontend"
    }
    
    local regular_name = plugin:namespaceConfigName("Debug Server", folder)
    assert(regular_name == "Debug Server [Frontend]")
    
    local compound_name = plugin:namespaceConfigName("Full Stack", folder, true)
    assert(compound_name == "Full Stack [Frontend] (compound)")
    
    local workspace_name = plugin:namespaceConfigName("Global Config", nil, false, "workspace")
    assert(workspace_name == "Global Config [workspace]")
  end)

  Test.It("loads_configurations_from_multiple_folders", function()
    local api, start = prepare.prepare()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    -- Create temporary workspace structure
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir .. "/frontend/.vscode", "p")
    vim.fn.mkdir(temp_dir .. "/backend/.vscode", "p")
    
    -- Frontend launch.json
    local frontend_config = {
      '{"version": "0.2.0", "configurations": [',
      '  {"name": "Frontend Dev", "type": "pwa-node", "request": "launch"}',
      ']}'
    }
    vim.fn.writefile(frontend_config, temp_dir .. "/frontend/.vscode/launch.json")
    
    -- Backend launch.json
    local backend_config = {
      '{"version": "0.2.0", "configurations": [',
      '  {"name": "Backend API", "type": "pwa-node", "request": "launch"}',
      ']}'
    }
    vim.fn.writefile(backend_config, temp_dir .. "/backend/.vscode/launch.json")
    
    -- Workspace info
    local workspace_info = {
      type = "multi-root",
      rootPath = temp_dir,
      folders = {
        {
          name = "Frontend",
          path = "./frontend",
          absolutePath = temp_dir .. "/frontend"
        },
        {
          name = "Backend",
          path = "./backend",
          absolutePath = temp_dir .. "/backend"
        }
      }
    }
    
    local configs = plugin:loadAllConfigurations(workspace_info)
    
    assert(configs["Frontend Dev [Frontend]"] ~= nil)
    assert(configs["Backend API [Backend]"] ~= nil)
    assert(configs["Frontend Dev [Frontend]"].originalName == "Frontend Dev")
    assert(configs["Backend API [Backend]"].originalName == "Backend API")
    
    -- Cleanup
    vim.fn.delete(temp_dir, "rf")
  end)

  Test.It("resolves_cross_folder_configuration_references", function()
    local api, start = prepare.prepare()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    local all_configs = {
      ["Frontend Dev [Frontend]"] = {
        name = "Frontend Dev [Frontend]",
        originalName = "Frontend Dev",
        folder = { name = "Frontend" },
        source = "folder"
      },
      ["Backend API [Backend]"] = {
        name = "Backend API [Backend]",
        originalName = "Backend API",
        folder = { name = "Backend" },
        source = "folder"
      }
    }
    
    local compound_config = {
      folder = { name = "Frontend" },
      source = "folder"
    }
    
    -- Test exact match
    local resolved = plugin:resolveConfigurationReference("Frontend Dev [Frontend]", compound_config, all_configs)
    assert(resolved == "Frontend Dev [Frontend]")
    
    -- Test original name match
    local resolved2 = plugin:resolveConfigurationReference("Backend API", compound_config, all_configs)
    assert(resolved2 == "Backend API [Backend]")
    
    -- Test no match
    local resolved3 = plugin:resolveConfigurationReference("NonExistent", compound_config, all_configs)
    assert(resolved3 == nil)
  end)

  Test.It("handles_json5_comments_in_configuration_files", function()
    local api, start = prepare.prepare()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    -- Create temporary file with JSON5 comments
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir .. "/.vscode", "p")
    
    local config_with_comments = {
      '{',
      '  "version": "0.2.0", // JSON5 comment',
      '  "configurations": [',
      '    {',
      '      "name": "Test Config", // Another comment',
      '      "type": "pwa-node",',
      '      "request": "launch"',
      '      /* Block comment */',
      '    }',
      '  ]',
      '}'
    }
    
    vim.fn.writefile(config_with_comments, temp_dir .. "/.vscode/launch.json")
    
    local folder = {
      name = "Test",
      path = ".",
      absolutePath = temp_dir
    }
    
    local configs = plugin:loadFolderConfigurations(folder)
    
    assert(configs["Test Config [Test]"] ~= nil)
    assert(configs["Test Config [Test]"].originalName == "Test Config")
    
    -- Cleanup
    vim.fn.delete(temp_dir, "rf")
  end)

  Test.It("provides_available_configurations_list", function()
    local api, start = prepare.prepare()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    -- Mock loaded configurations
    plugin.cached_configurations = {
      ["Frontend Dev [Frontend]"] = {
        name = "Frontend Dev [Frontend]",
        originalName = "Frontend Dev"
      },
      ["Backend API [Backend]"] = {
        name = "Backend API [Backend]",
        originalName = "Backend API"
      },
      ["Full Stack [workspace] (compound)"] = {
        name = "Full Stack [workspace] (compound)",
        originalName = "Full Stack"
      }
    }
    
    local available = plugin:getAvailableConfigurations()
    
    assert(#available == 3)
    assert(vim.tbl_contains(available, "Frontend Dev [Frontend]"))
    assert(vim.tbl_contains(available, "Backend API [Backend]"))
    assert(vim.tbl_contains(available, "Full Stack [workspace] (compound)"))
  end)

end)