local Test = require("spec.helpers.testing")
local prepare = require("spec.helpers.prepare")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")

Test.Describe("LaunchJsonSupport Plugin", function()
  local api, start

  Test.BeforeEach(function()
    api, start = prepare.prepare()
  end)

  Test.It("detects_single_folder_workspace", function()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    -- Mock single folder workspace
    local workspace_info = plugin:detectWorkspace("/home/user/project")
    
    Test.assert.are.equal("single", workspace_info.type)
    Test.assert.are.equal("/home/user/project", workspace_info.rootPath)
    Test.assert.are.equal(1, #workspace_info.folders)
    Test.assert.are.equal("project", workspace_info.folders[1].name)
  end)

  Test.It("parses_multi_root_workspace_file", function()
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
    
    Test.assert.are.equal("multi-root", workspace_info.type)
    Test.assert.are.equal(2, #workspace_info.folders)
    Test.assert.are.equal("Frontend", workspace_info.folders[1].name)
    Test.assert.are.equal("Backend", workspace_info.folders[2].name)
    
    -- Cleanup
    vim.fn.delete(temp_dir, "rf")
  end)

  Test.It("substitutes_variables_in_single_folder_workspace", function()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    local config = {
      program = "${workspaceFolder}/src/index.js",
      cwd = "${workspaceFolder}",
      args = ["${fileBasename}"]
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
    
    Test.assert.are.equal("/home/user/project/src/index.js", substituted.program)
    Test.assert.are.equal("/home/user/project", substituted.cwd)
  end)

  Test.It("substitutes_scoped_variables_in_multi_root_workspace", function()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    local config = {
      program = "${workspaceFolder:Frontend}/src/index.js",
      cwd = "${workspaceFolder:Backend}",
      args = ["${workspaceFolder}"]
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
    
    Test.assert.are.equal("/home/user/workspace/frontend/src/index.js", substituted.program)
    Test.assert.are.equal("/home/user/workspace/backend", substituted.cwd)
    Test.assert.are.equal("/home/user/workspace", substituted.args[1])
  end)

  Test.It("creates_namespaced_configuration_names", function()
    local plugin = api:loadPlugin(LaunchJsonSupport)
    
    local folder = {
      name = "Frontend",
      path = "./frontend",
      absolutePath = "/home/user/workspace/frontend"
    }
    
    local regular_name = plugin:namespaceConfigName("Debug Server", folder)
    Test.assert.are.equal("Debug Server [Frontend]", regular_name)
    
    local compound_name = plugin:namespaceConfigName("Full Stack", folder, true)
    Test.assert.are.equal("Full Stack [Frontend] (compound)", compound_name)
    
    local workspace_name = plugin:namespaceConfigName("Global Config", nil, false, "workspace")
    Test.assert.are.equal("Global Config [workspace]", workspace_name)
  end)

  Test.It("loads_configurations_from_multiple_folders", function()
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
    
    Test.assert.is_not.Nil(configs["Frontend Dev [Frontend]"])
    Test.assert.is_not.Nil(configs["Backend API [Backend]"])
    Test.assert.are.equal("Frontend Dev", configs["Frontend Dev [Frontend]"].originalName)
    Test.assert.are.equal("Backend API", configs["Backend API [Backend]"].originalName)
    
    -- Cleanup
    vim.fn.delete(temp_dir, "rf")
  end)

  Test.It("resolves_cross_folder_configuration_references", function()
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
    Test.assert.are.equal("Frontend Dev [Frontend]", resolved)
    
    -- Test original name match
    local resolved2 = plugin:resolveConfigurationReference("Backend API", compound_config, all_configs)
    Test.assert.are.equal("Backend API [Backend]", resolved2)
    
    -- Test no match
    local resolved3 = plugin:resolveConfigurationReference("NonExistent", compound_config, all_configs)
    Test.assert.is.Nil(resolved3)
  end)

  Test.It("handles_json5_comments_in_configuration_files", function()
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
    
    Test.assert.is_not.Nil(configs["Test Config [Test]"])
    Test.assert.are.equal("Test Config", configs["Test Config [Test]"].originalName)
    
    -- Cleanup
    vim.fn.delete(temp_dir, "rf")
  end)

  Test.It("provides_available_configurations_list", function()
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
    
    Test.assert.are.equal(3, #available)
    Test.assert.is_true(vim.tbl_contains(available, "Frontend Dev [Frontend]"))
    Test.assert.is_true(vim.tbl_contains(available, "Backend API [Backend]"))
    Test.assert.is_true(vim.tbl_contains(available, "Full Stack [workspace] (compound)"))
  end)

  Test.AfterEach(function()
    prepare.cleanup_all()
  end)
end)