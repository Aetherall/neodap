# LaunchJsonSupport Plugin

A comprehensive VS Code launch.json configuration plugin for neodap with advanced multi-root workspace support.

## Features

### 🚀 Core Functionality
- **VS Code Compatibility**: Full support for VS Code launch.json configuration format
- **Multi-root Workspaces**: Advanced support for .code-workspace files with multiple folders
- **Variable Substitution**: Enhanced variable resolution with workspace scoping
- **Cross-folder Compounds**: Superior compound configuration support across workspace folders
- **JSON5 Support**: Handles comments in configuration files

### 🎯 Advanced Variable Substitution

#### Standard Variables
- `${workspaceFolder}` - Current workspace folder
- `${file}` - Current file path
- `${fileBasename}` - Current file basename
- `${fileDirname}` - Current file directory
- `${cwd}` - Current working directory

#### Multi-root Workspace Variables
- `${workspaceFolder:FolderName}` - Specific workspace folder by name
- `${workspaceFolderBasename}` - Workspace folder basename

#### Context-aware Resolution
- In single-folder workspaces: `${workspaceFolder}` resolves to the workspace root
- In multi-root workspaces: `${workspaceFolder}` resolves based on configuration context
- Explicit scoping: `${workspaceFolder:Frontend}` always resolves to the "Frontend" folder

### 🔧 Configuration Discovery

#### Single-folder Workspaces
```
project/
├── .vscode/
│   └── launch.json
└── src/
    └── index.js
```

#### Multi-root Workspaces
```
workspace/
├── example.code-workspace
├── frontend/
│   ├── .vscode/
│   │   └── launch.json
│   └── src/
├── backend/
│   ├── .vscode/
│   │   └── launch.json
│   └── src/
└── shared/
    └── .vscode/
        └── launch.json
```

### 📁 Configuration Namespacing

To avoid naming conflicts in multi-root workspaces, configurations are automatically namespaced:

- `Debug Server` (from Frontend folder) → `Debug Server [Frontend]`
- `API Server` (from Backend folder) → `API Server [Backend]`
- `Full Stack` (from workspace) → `Full Stack [workspace] (compound)`

## Usage

### Plugin Installation

```lua
-- Load the plugin
local launch_json = api:loadPlugin(require("neodap.plugins.LaunchJsonSupport"))
```

### Commands

#### `:NeodapLaunchJson [config_name]`
Start a debugging session from launch.json configuration.

```vim
" Show configuration picker
:NeodapLaunchJson

" Start specific configuration
:NeodapLaunchJson "Debug Server [Frontend]"

" Start compound configuration
:NeodapLaunchJson "Full Stack [workspace] (compound)"
```

#### `:NeodapWorkspaceInfo`
Display detailed workspace and configuration information.

#### `:NeodapReloadConfigs`
Reload all launch.json configurations from the workspace.

### API Methods

#### Configuration Loading
```lua
-- Detect workspace type and structure
local workspace_info = launch_json:detectWorkspace()

-- Load all configurations from workspace
local configs = launch_json:loadAllConfigurations(workspace_info)

-- Get available configuration names
local available = launch_json:getAvailableConfigurations()
```

#### Session Creation
```lua
-- Create session from configuration
local session = launch_json:createSessionFromConfig("Debug Server [Frontend]", manager)

-- Create multiple sessions from compound
local sessions = launch_json:createCompoundSessions("Full Stack [workspace] (compound)", manager)
```

#### Variable Substitution
```lua
local config = {
  program = "${workspaceFolder:Frontend}/src/index.js",
  cwd = "${workspaceFolder:Backend}"
}

local context = {
  workspaceInfo = workspace_info,
  folder = frontend_folder,
  vars = { custom_var = "value" }
}

local substituted = launch_json:substituteVariables(config, context)
```

## Configuration Examples

### Single-folder Workspace

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Server",
      "type": "pwa-node",
      "request": "launch",
      "program": "${workspaceFolder}/src/server.js",
      "cwd": "${workspaceFolder}",
      "env": {
        "NODE_ENV": "development"
      }
    }
  ]
}
```

### Multi-root Workspace

#### .code-workspace file:
```json
{
  "folders": [
    { "name": "Frontend", "path": "./frontend" },
    { "name": "Backend", "path": "./backend" }
  ],
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "name": "Full Stack Debug",
        "type": "compound",
        "configurations": [
          "Frontend Dev Server",
          "Backend API"
        ]
      }
    ]
  }
}
```

#### Frontend launch.json:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Frontend Dev Server",
      "type": "pwa-node",
      "request": "launch",
      "program": "${workspaceFolder}/src/index.js",
      "cwd": "${workspaceFolder}",
      "env": {
        "NODE_ENV": "development",
        "PORT": "3000"
      }
    }
  ]
}
```

#### Backend launch.json:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Backend API",
      "type": "pwa-node",
      "request": "launch",
      "program": "${workspaceFolder}/src/server.js",
      "cwd": "${workspaceFolder}",
      "env": {
        "NODE_ENV": "development",
        "DATABASE_URL": "postgres://localhost:5432/devdb"
      }
    }
  ]
}
```

## Advanced Features

### Cross-folder Compound Configurations

The plugin supports compound configurations that reference configurations from different workspace folders:

```json
{
  "name": "Full Stack with Tests",
  "type": "compound",
  "configurations": [
    "Frontend Dev Server",    // From Frontend folder
    "Backend API",           // From Backend folder
    "Test Runner"            // From Shared folder
  ]
}
```

### Intelligent Reference Resolution

When resolving configuration references in compounds, the plugin:

1. First tries exact namespaced name match
2. Then searches by original name across all folders
3. Prioritizes same-folder configurations when multiple matches exist
4. Falls back to first match for workspace-level compounds

### Enhanced Error Handling

- Graceful handling of malformed JSON files
- Clear error messages for missing configurations
- Validation of cross-folder references
- Fallback behavior for unsupported adapter types

## Supported Adapter Types

- `pwa-node` - Node.js debugging with js-debug
- `node` - Node.js debugging with node-debug2
- `python` - Python debugging with debugpy-adapter
- `chrome` - Chrome debugging with vscode-chrome-debug

## Benefits over VS Code

1. **Better Compound Support**: Superior cross-folder compound configuration handling
2. **Enhanced Variable Resolution**: More intelligent workspace folder resolution
3. **Comprehensive Namespacing**: Avoids configuration naming conflicts
4. **Robust Error Handling**: Better error messages and fallback behavior
5. **Extensible Architecture**: Easy to add new adapter types and features

## Architecture

The plugin follows neodap's established patterns:

- **API Manager Pattern**: Clean public API with internal implementation
- **Class-based Design**: Proper state management and lifecycle
- **Comprehensive Logging**: Detailed logging for debugging and monitoring
- **Type Safety**: Full type annotations for better development experience
- **Caching**: Efficient caching of parsed configurations
- **Plugin Dependencies**: Proper integration with neodap's plugin system