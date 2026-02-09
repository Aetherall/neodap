# Overseer Templates Design

## Overview

This document describes how neodap launch configurations integrate with Overseer's `:OverseerRun` command. Users can pick debug configurations from Overseer's template picker, providing a unified task launching experience.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    :OverseerRun                         │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │ shell tasks │  │ vscode tasks│  │ neodap configs  │ │
│  └─────────────┘  └─────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────┘
                                              │
                                              ▼
                              ┌───────────────────────────┐
                              │    neodap strategy        │
                              │                           │
                              │  Bridges Overseer task    │
                              │  to neodap launch flow    │
                              └───────────────────────────┘
                                              │
                                              ▼
                              ┌───────────────────────────┐
                              │  neodap.launch(config)    │
                              │                           │
                              │  Creates adapter/session  │
                              │  via normal flow          │
                              └───────────────────────────┘
                                              │
                                              ▼
                              ┌───────────────────────────┐
                              │  dap-process + dap-session│
                              │                           │
                              │  Visible in :Overseer     │
                              └───────────────────────────┘
```

## Components

### Template Provider

A template provider dynamically generates Overseer templates from neodap's launch configurations. Templates are generated lazily when `:OverseerRun` is invoked, ensuring changes to `launch.json` are picked up without restart.

```lua
-- overseer/template/neodap.lua
return {
  generator = function(opts, cb)
    local configs = neodap.get_configurations()
    local templates = {}

    for _, config in ipairs(configs) do
      table.insert(templates, {
        name = "Debug: " .. config.name,
        strategy = { "neodap", config = config },
        -- No cmd - neodap strategy handles execution
      })
    end

    cb(templates)
  end,
}
```

### neodap Strategy

A custom Overseer strategy that bridges to neodap's launch machinery. The strategy itself is thin - it receives the launch config and delegates to neodap.

```lua
-- overseer/strategy/neodap.lua
function M.new(opts)
  local strategy = {
    config = opts.config,
  }

  function strategy:start(task)
    -- Resolve variables (${file}, ${workspaceFolder}, etc.)
    local resolved = neodap.resolve_config(self.config)

    -- Launch via neodap (creates dap-process + dap-session tasks)
    neodap.launch(resolved, {
      on_session = function(session)
        -- Link this task to the session
        -- Task lifecycle follows session lifecycle
      end,
    })
  end

  function strategy:stop()
    -- Terminate the debug session
  end

  return strategy
end
```

### Task Hierarchy

When a neodap strategy task starts, it triggers the normal neodap launch flow, which creates dap-process and dap-session tasks. The hierarchy:

```
Debug: jsfile              [neodap strategy - parent/orchestrator]
├── js-debug               [dap-process - adapter]
├── bootstrap              [dap-session - bootstrap session]
└── demo.js                [dap-session - debuggee session]
```

The parent task's lifecycle is tied to its children:
- Status: RUNNING while any child is running
- Status: SUCCESS when all children complete successfully
- Status: FAILURE if any child fails

## Compound Configurations

Compound configurations (launching multiple debug configs together) are handled by Overseer's native compound task support, not by neodap.

### launch.json compound

```json
{
  "compounds": [
    {
      "name": "Server + Client",
      "configurations": ["Launch Server", "Launch Client"],
      "stopAll": true
    }
  ]
}
```

### Translated to Overseer

The template provider translates compounds into Overseer compound templates:

```lua
{
  name = "Debug: Server + Client",
  strategy = "orchestrator",
  tasks = {
    { "Debug: Launch Server", strategy = { "neodap", config = server_config } },
    { "Debug: Launch Client", strategy = { "neodap", config = client_config } },
  },
  -- stopAll: true maps to Overseer's on_complete = "dispose_all"
}
```

### Full Task Tree

```
Debug: Server + Client     [orchestrator - compound]
├── Debug: Launch Server   [neodap strategy]
│   ├── js-debug           [dap-process]
│   └── server.js          [dap-session]
└── Debug: Launch Client   [neodap strategy]
    ├── js-debug           [dap-process] (or shared)
    └── client.js          [dap-session]
```

## Benefits

1. **Unified UX**: All tasks (shell, build, debug) accessible from `:OverseerRun`
2. **Leverage Overseer**: Compound orchestration, task dependencies, lifecycle management
3. **neodap stays focused**: Core handles single sessions; Overseer handles orchestration
4. **Mixing task types**: Compounds can include both debug and non-debug tasks
5. **Custom compounds**: Users can define compounds in Overseer config, not just `launch.json`

## Variable Resolution

Launch configs use VS Code-style variables (`${file}`, `${workspaceFolder}`, etc.). These are resolved when the neodap strategy starts, not when templates are generated. This ensures the current context (active file, cursor position) is captured at launch time.

```lua
function strategy:start(task)
  -- Resolve NOW, using current editor state
  local resolved = neodap.resolve_config(self.config)
  neodap.launch(resolved)
end
```

## preLaunchTask / postDebugTask

Launch configs can specify `preLaunchTask` and `postDebugTask`. The neodap strategy orchestrates these:

```
preLaunchTask: build       [shell task - runs first]
        │
        ▼
Debug: jsfile              [neodap strategy - runs after preLaunchTask]
├── js-debug               [dap-process]
└── demo.js                [dap-session]
        │
        ▼ (on session terminate)
postDebugTask: cleanup     [shell task - runs last]
```

This is already supported by neodap's overseer plugin. The neodap strategy would integrate with it:

```lua
function strategy:start(task)
  local config = self.config

  -- Run preLaunchTask if specified
  if config.preLaunchTask then
    overseer.run_task(config.preLaunchTask, {
      on_complete = function()
        self:launch_debug(config)
      end,
    })
  else
    self:launch_debug(config)
  end
end

function strategy:launch_debug(config)
  neodap.launch(config, {
    on_terminate = function()
      if config.postDebugTask then
        overseer.run_task(config.postDebugTask)
      end
    end,
  })
end
```

## Flow Example

### User picks "Debug: jsfile" from :OverseerRun

1. Template provider returns template with `strategy = { "neodap", config = jsfile_config }`
2. Overseer creates task with neodap strategy
3. Strategy's `start()` is called
4. Strategy resolves variables (`${file}` → `/path/to/demo.js`)
5. Strategy calls `neodap.launch(resolved_config)`
6. neodap spawns js-debug adapter (creates dap-process task)
7. neodap creates debug session (creates dap-session task)
8. Parent neodap strategy task tracks child lifecycle
9. All three tasks visible in `:Overseer`

### User terminates debugging

1. User runs `:Dap terminate` or stops the parent task
2. dap-session task terminates
3. dap-process task terminates (adapter exits)
4. Parent neodap strategy task completes
5. postDebugTask runs if configured
