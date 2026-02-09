# Overseer Task Hierarchy Design

## Overview

When launching debug configurations from `:OverseerRun`, tasks should form a visual hierarchy in Overseer's task list. This document describes how `parent_id` is threaded through to achieve proper grouping.

## Task Hierarchy

```
neodap strategy task         <- created by template
└── dap-process task         <- adapter process
    └── dap-session task(s)  <- debug sessions
```

## Implementation

### Parameter Threading

The `parent_task_id` parameter flows through the system:

```
neodap strategy
    │
    │ debug({ config, parent_task_id: task.id })
    ▼
core debug()
    │
    │ backend.spawn({ ..., parent_task_id })
    │ backend.connect({ ..., parent_task_id })
    ▼
overseer backend
    │
    │ overseer.new_task({ parent_id: opts.parent_task_id })
    ▼
Overseer task list (visual grouping)
```

### Components

**neodap strategy** (`lua/overseer/strategy/neodap.lua`):
- Passes `parent_task_id = self.task.id` to `debug()`

**Core debug()** (`lua/neodap/plugins/dap/init.lua`):
- Accepts `parent_task_id` in opts
- Passes through to backend `spawn()` and `connect()` calls
- Does not interpret the value (backend-agnostic)

**Overseer backend** (`lua/neodap/backends/overseer.lua`):
- `spawn()` creates dap-process task with `parent_id = opts.parent_task_id`
- `spawn()` returns task ID for use as parent of sessions
- `connect()` creates dap-session task with `parent_id` from spawn

**Builtin backend** (`lua/neodap/backends/builtin.lua`):
- Ignores `parent_task_id` (no Overseer integration)

### Spawn Returns Task ID

For proper hierarchy, `spawn()` must return the dap-process task ID so `connect()` can use it:

```lua
-- backends/overseer.lua
function M.spawn(opts)
  local task = overseer.new_task({
    name = task_name,
    parent_id = opts.parent_task_id,
    ...
  })
  task:start()

  return {
    handle = handle,
    task_id = task.id,  -- returned for connect() to use
  }
end

function M.connect(opts)
  local task = overseer.new_task({
    name = task_name,
    parent_id = opts.parent_task_id,  -- dap-process task ID
    ...
  })
  ...
end
```

### Core Threading

The core passes the adapter's task ID to session creation:

```lua
-- In debug(), after spawning adapter:
local spawn_result = backend.spawn({ ..., parent_task_id = opts.parent_task_id })
local adapter_task_id = spawn_result.task_id

-- When creating sessions:
backend.connect({ ..., parent_task_id = adapter_task_id })
```

## Lifecycle

- `parent_id` provides **visual grouping only** in Overseer
- Lifecycle management (completion) is handled separately:
  - dap-session tasks complete when sessions terminate
  - dap-process task completes when adapter exits
  - neodap strategy task watches session state, completes when terminated

## Direct Launch via :DapLaunch

When launching via `:DapLaunch`:
- If using overseer backend: Creates Overseer task with neodap strategy (same as OverseerRun)
- If using builtin backend: No Overseer task created (direct debug launch)
