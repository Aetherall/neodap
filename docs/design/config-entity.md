# Config Entity Design

## Overview

When a user starts a debug session (single configuration or compound), neodap creates multiple Session entities that form a tree via DAP's parent-child protocol. However, the user loses track of which sessions came from the same configuration - especially when launching the same compound multiple times.

The **Config** entity represents a running instance of a configuration (or compound). It groups sessions and persists across session restarts, providing:
- Clear identity: "Debug Both Apps #1" vs "Debug Both Apps #2"
- Aggregate operations: stop all, restart all, restart single root
- Meaningful relationships: roots (what was started) and targets (what can be debugged)
- Lifecycle spanning multiple session restarts

## Terminology

| Term | Meaning |
|------|---------|
| **configuration** (lowercase) | Static definition in launch.json |
| **compound** | Static definition that references multiple configurations |
| **Config** (capital C, entity) | Running instance of a configuration/compound |
| **root session** | Session created directly from a configuration |
| **target** | Leaf session where debugging happens |

## Mental Model

### Static vs Running

```
launch.json (static)                 neodap entities (running)
────────────────────────────────────────────────────────────────
"configurations": [                  Config #1 "Debug Both Apps"
  { "name": "App A: Debug", ... },   ├── roots: [App A, App B]
  { "name": "App B: Debug", ... }    ├── targets: [server.js, worker.js]
],                                   └── persists across restarts
"compounds": [
  { "name": "Debug Both Apps",       Config #2 "Debug Both Apps"
    "configurations": [...] }        ├── roots: [App A, App B]
]                                    └── separate instance
```

### Session Concepts (User Perspective)

| Concept | Definition | User Meaning |
|---------|------------|--------------|
| **Root sessions** | Sessions created directly from configurations | "What I started" |
| **Targets** | Leaf sessions (no children) | "What I debug" |
| **Intermediate** | Sessions between root and leaf | DAP plumbing, less visible |

### Config as Container

```
Config #1 "Debug Both Apps"
├── roots: [App A root, App B root]     <- configurations that were started
├── targets: [server.js, worker.js]     <- where debugging happens
└── sessions: [all sessions in tree]    <- full graph

Config #2 "Debug Both Apps"
├── roots: [App A root, App B root]
├── targets: [api.js, worker.js]
└── sessions: [...]
```

### Lifecycle: Config Survives Restarts

```
1. User starts "Debug Both Apps"
   
   Config #1 "Debug Both Apps"
   ├── App A root → server.js
   └── App B root → worker.js

2. User restarts App A (session dies, new one created, same Config)
   
   Config #1 "Debug Both Apps"
   ├── App A root (NEW) → server.js (NEW)
   └── App B root → worker.js (same)

3. User starts "Debug Both Apps" again (new Config instance)
   
   Config #1 "Debug Both Apps"     <- still exists
   └── ...
   
   Config #2 "Debug Both Apps"     <- new instance
   ├── App A root → server.js
   └── App B root → worker.js
```

### Relationships

```
                    ┌─────────────────────────┐
                    │        Debugger         │
                    │                         │
                    │  configs ───────────────┼──► [Config #1, Config #2, ...]
                    │  sessions ──────────────┼──► [all sessions, flat]
                    │  rootSessions ──────────┼──► [root sessions only]
                    │  leafSessions ──────────┼──► [leaf sessions only]
                    └─────────────────────────┘
                                │
                                │ configs
                                ▼
                    ┌─────────────────────────┐
                    │      Config #1          │
                    │                         │
                    │  sessions ──────────────┼──► [sessions in this config]
                    │  roots (derived) ───────┼──► [root sessions]
                    │  targets (derived) ─────┼──► [leaf sessions]
                    │  specifications ────────┼──► [stored config data]
                    └─────────────────────────┘
                                │
                                │ sessions
                                ▼
                    ┌─────────────────────────┐
                    │       Session           │
                    │                         │
                    │  config (reference) ────┼──► Config #1
                    │  isConfigRoot ──────────┼──► true/false
                    │  parent ────────────────┼──► parent session (DAP)
                    │  children ──────────────┼──► child sessions (DAP)
                    │  leaf ──────────────────┼──► true if no children
                    └─────────────────────────┘
```

## Schema

### Config Entity

```lua
Config = {
  -- Identity
  uri = { type = "string" },                    -- "config:abc123"
  configId = { type = "string" },               -- unique ID
  
  -- Properties
  name = { type = "string" },                   -- compound name or configuration name
  index = { type = "number" },                  -- for "Config #1", "#2"
  state = { type = "string" },                  -- "active" | "terminated"
  isCompound = { type = "boolean" },            -- true if from compound
  
  -- Stored data (not edges) - for restart capability
  specifications = { type = "table" },          -- original configuration specs
  
  -- Edges
  debuggers = {
    type = "edge",
    target = "Debugger",
    reverse = "configs",
  },
  
  sessions = {
    type = "edge",
    target = "Session",
    reverse = "configs",
    __indexes = {
      { name = "default", fields = {} },
      { name = "by_leaf", fields = { { name = "leaf" } } },
      { name = "by_isConfigRoot", fields = { { name = "isConfigRoot" } } },
      { name = "by_state", fields = { { name = "state" } } },
    },
  },
  
  -- Derived collections (reactive)
  roots = {
    type = "collection",
    edge = "sessions",
    filter = { isConfigRoot = true },
  },
  
  targets = {
    type = "collection",
    edge = "sessions",
    filter = { leaf = true },
  },
  
  activeTargets = {
    type = "collection",
    edge = "sessions",
    filters = {
      { field = "leaf", value = true },
      { field = "state", value = "terminated", op = "ne" },
    },
  },
  
  stoppedTargets = {
    type = "collection",
    edge = "sessions",
    filters = {
      { field = "leaf", value = true },
      { field = "state", value = "stopped" },
    },
  },
  
  -- Rollups
  debugger = { type = "reference", edge = "debuggers" },
  rootCount = { type = "count", edge = "sessions", filter = { isConfigRoot = true } },
  targetCount = { type = "count", edge = "sessions", filter = { leaf = true } },
  activeTargetCount = {
    type = "count",
    edge = "sessions",
    filters = {
      { field = "leaf", value = true },
      { field = "state", value = "terminated", op = "ne" },
    },
  },
  stoppedTargetCount = {
    type = "count",
    edge = "sessions",
    filters = {
      { field = "leaf", value = true },
      { field = "state", value = "stopped" },
    },
  },
  
  -- Convenience references
  firstTarget = {
    type = "reference",
    edge = "sessions",
    filter = { leaf = true },
  },
  firstStoppedTarget = {
    type = "reference",
    edge = "sessions",
    filters = {
      { field = "leaf", value = true },
      { field = "state", value = "stopped" },
    },
  },
}
```

### Session Additions

```lua
Session = {
  -- ... existing fields ...
  
  -- New property: marks sessions created directly from configurations
  isConfigRoot = { type = "boolean", default = false },
  
  -- New edge (reverse of Config.sessions)
  configs = {
    type = "edge",
    target = "Config",
    reverse = "sessions",
  },
  
  -- Rollup for easy access
  config = { type = "reference", edge = "configs" },
}
```

### Debugger Additions

```lua
Debugger = {
  -- ... existing fields ...
  
  -- New edge (reverse of Config.debuggers)
  configs = {
    type = "edge",
    target = "Config",
    reverse = "debuggers",
    __indexes = {
      { name = "default", fields = {} },
      { name = "by_state", fields = { { name = "state" } } },
      { name = "by_index", fields = { { name = "index" } } },
    },
  },
  
  activeConfigs = {
    type = "collection",
    edge = "configs",
    filters = { { field = "state", value = "terminated", op = "ne" } },
  },
  
  configCount = { type = "count", edge = "configs" },
  activeConfigCount = {
    type = "count",
    edge = "configs",
    filters = { { field = "state", value = "terminated", op = "ne" } },
  },
}
```

## URL Queries

```
config:abc123                     # Specific config
config:abc123/roots               # Root sessions of config
config:abc123/targets             # Leaf sessions of config (reactive)
config:abc123/sessions            # All sessions in config tree

/configs                          # All configs
/configs(state=active)            # Active configs
/activeConfigs                    # Same, via derived collection

@config                           # Focused entity's config
@config/targets                   # Targets in focused config
@session/config                   # Config of focused session
```

## Session Membership Propagation

Like `allOutputs`, config membership propagates to descendants:

```lua
-- In dap/init.lua onSessionCreated:

onSessionCreated = function(dap_session)
  local parent_session = session_entities[dap_session.parent]
  
  -- Create session entity...
  local new_session = entities.Session.new(graph, { ... })
  
  -- Config membership
  if parent_session then
    -- Child session: inherit config from parent
    local parent_config = parent_session.config:get()
    if parent_config then
      parent_config.sessions:link(new_session)
      -- isConfigRoot stays false (default)
    end
  elseif opts.config then
    -- Root session: link to provided config, mark as root
    new_session:update({ isConfigRoot = true })
    opts.config.sessions:link(new_session)
  end
  
  -- ... rest of session setup
end
```

## User Experience

### Tree Views

#### Sessions Tree (Current)

```
Sessions
├── App A: Debug (Stop)
│   └── server.js [12345]     <- target
└── App B: Debug (Stop)
    └── worker.js [12346]     <- target
```

#### Sessions Tree (With Config Grouping)

```
Sessions
└── Debug Both Apps #1
    ├── App A: Debug (Stop)
    │   └── server.js [12345]
    └── App B: Debug (Stop)
        └── worker.js [12346]
```

#### Targets Tree (Current)

```
Targets
├── server.js [12345]
└── worker.js [12346]
```

#### Targets Tree (With Config Context)

```
Targets
├── Debug Both Apps #1
│   ├── server.js [12345]
│   └── worker.js [12346]
└── Debug Both Apps #2
    ├── server.js [12347]
    └── worker.js [12348]
```

### Lualine Display

Current:
```
⏸ App A: Debug (Stop) > server.js [12345]  [1/4]
```

With Config:
```
⏸ server.js [Debug Both #1: 1/2]
   │         │            │  └── target index in config
   │         │            └── config index
   │         └── abbreviated config name
   └── target name
```

Alternative formats:
```
⏸ server.js [#1: 1/2 targets]
⏸ server.js (Debug Both Apps #1)
⏸ #1 > server.js [1/2]
```

### Start Flow

#### Single Configuration

```
User: :Dap start "App A: Debug"

1. Create Config { name: "App A: Debug", index: 1, specifications: [spec] }
2. Link Config to Debugger
3. Start configuration → creates root session
4. Link session to Config, set isConfigRoot = true
5. If session spawns children, they inherit Config membership

Result:
  Config #1 "App A: Debug"
  └── roots: [App A session]
  └── targets: [whatever leafs appear]
```

#### Compound Configuration

```
User: :Dap start "Debug Both Apps"

1. Resolve compound → [App A spec, App B spec]
2. Create Config { name: "Debug Both Apps", index: 1, specifications: [...], isCompound: true }
3. Link Config to Debugger
4. For each specification:
   - Start configuration → creates root session
   - Link session to Config, set isConfigRoot = true
5. Child sessions inherit Config membership

Result:
  Config #1 "Debug Both Apps"
  └── roots: [App A root, App B root]
  └── targets: [server.js, worker.js, ...]
```

### Operations

#### Stop Config

```lua
function Config:terminate()
  -- Terminate all root sessions (children die with them)
  for root in self.roots:iter() do
    root:terminate()
  end
end
```

Command: `:Dap stop config` or `<leader>dX`

#### Restart Config

```lua
function Config:restart()
  -- 1. Terminate current sessions
  self:terminate()
  
  -- 2. Wait for termination
  -- 3. Restart with stored specifications (same Config entity)
  for _, spec in ipairs(self.specifications) do
    debugger:debug({ spec = spec, config = self })
  end
end
```

Command: `:Dap restart config` or `<leader>dR`

#### Restart Single Root (Within Config)

```lua
function Session:restartRoot()
  local cfg = self.config:get()
  local root = self:rootAncestor()
  local spec = root.specification  -- stored on root session
  
  -- Terminate this tree
  root:terminate()
  
  -- Restart this root within same Config
  debugger:debug({ spec = spec, config = cfg })
end
```

Command: `:Dap restart` (on focused session) or `<leader>dr`

### Overseer Integration

Current hierarchy:
```
neodap strategy task
└── dap-process task
    └── dap-session task(s)
```

With Config awareness:
```
neodap strategy task (Config "Debug Both Apps #1")
├── dap-process task (App A)
│   └── dap-session task(s)
└── dap-process task (App B)
    └── dap-session task(s)
```

The neodap strategy task **is** the Config representation in Overseer:
- Task name = Config name
- Task completes when Config terminates (all roots terminated)
- Task can be restarted → restarts Config (same Config entity)

```lua
-- In neodap strategy
function NeodapStrategy:on_start()
  -- Create Config entity
  self.config_entity = entities.Config.new(graph, {
    name = self.config.name,
    specifications = self.specifications,
    ...
  })
  
  -- Start configurations with this Config
  for _, spec in ipairs(self.specifications) do
    debugger:debug({ spec = spec, config = self.config_entity })
  end
  
  -- Watch config state
  self.config_entity.state:use(function(state)
    if state == "terminated" then
      self.task:set_status("complete")
    end
  end)
end

function NeodapStrategy:on_reset()
  -- Restart = restart Config (same entity, new sessions)
  self.config_entity:restart()
end
```

### Neotest Integration

Neotest runs tests via DAP. Each test run creates a Config:

```
User: Run test "should handle errors"

1. Neotest creates configuration for test
2. Creates Config { name: "Test: should handle errors", ... }
3. Runs debug session
4. Test completes → Config terminates (but entity persists for restart)
```

For multiple tests:
```
User: Run all tests in file

Option A: One Config per test (current behavior, parallel)
  Config #1 "Test: should handle errors"
  Config #2 "Test: should validate input"
  ...

Option B: One Config for all tests (batch)
  Config #1 "Tests: user.test.ts"
  └── targets: [test1, test2, ...]
```

Neotest output panel could group by Config.

### Picker / Selection

When user needs to pick a target:

```
Select Debug Target:

Debug Both Apps #1 (2 targets, 1 stopped)
├── ⏸ server.js
└── ▶ worker.js

Debug Both Apps #2 (2 targets)
├── ▶ server.js
└── ▶ worker.js

App C: Debug #3 (1 target)
└── ⏸ main.js
```

### Focus Behavior

With Config awareness, focus can be smarter:

1. **Initial focus**: When Config starts, focus first stopped target in that Config
2. **Focus within config**: `<Tab>`/`<S-Tab>` cycles targets within current Config
3. **Focus across configs**: `<C-Tab>` jumps to next Config's first stopped target
4. **Stop event**: Only auto-focus if stopped target is in same Config as current focus

```lua
-- In cursor_focus.lua
local function should_auto_focus(session, debugger)
  local current_config = debugger.ctx:focused_config()
  local session_config = session.config:get()
  
  -- Only auto-focus within same config
  if current_config and session_config then
    return current_config._id == session_config._id
  end
  
  -- No current focus, allow
  return true
end
```

## Index Management

Each Config gets an incrementing index for display:

```lua
-- Per-name indexing: "Debug Both Apps #1", "Debug Both Apps #2", "App A #1"
function get_next_config_index(debugger, name)
  local max_index = 0
  for cfg in debugger.configs:iter() do
    if cfg.name:get() == name then
      max_index = math.max(max_index, cfg.index:get())
    end
  end
  return max_index + 1
end
```

Display format: `{name} #{index}` or `#{index}` for short.

## Lifecycle

### State Transitions

```
Config.state:
  "active"     -- At least one non-terminated session
  "terminated" -- All sessions terminated
```

Note: A terminated Config can become active again via restart.

### State Derivation

State is derived from session states (reactive):

```lua
-- Option A: Computed on access
function Config:isActive()
  return self.activeTargetCount:get() > 0
end

-- Option B: Schema-level derived (if supported)
state = {
  type = "derived",
  compute = function(config)
    for session in config.sessions:iter() do
      if session.state:get() ~= "terminated" then
        return "active"
      end
    end
    return "terminated"
  end
}

-- Option C: Updated via subscription
config.sessions:each(function(session)
  session.state:use(function()
    config:updateState()
  end)
end)
```

### Cleanup

Options:
1. **Keep terminated configs**: For history, restart capability
2. **Auto-cleanup**: Remove after N seconds or when debugger stops
3. **Manual cleanup**: User command to clear history

Recommendation: Keep until debugger stops. Provide `:Dap clear configs` for manual cleanup.

## Commands

| Command | Description |
|---------|-------------|
| `:Dap start {name}` | Start configuration/compound (creates Config) |
| `:Dap stop` | Terminate focused target's root tree |
| `:Dap stop config` | Terminate all sessions in focused Config |
| `:Dap stop all` | Terminate all Configs |
| `:Dap restart` | Restart focused target's root (same Config) |
| `:Dap restart config` | Restart entire Config |
| `:Dap configs` | Picker: select Config to focus |
| `:Dap targets` | Picker: select target (grouped by Config) |

## Components

New components for presentation:

```lua
-- Config name with index
config_name = function(config)
  return string.format("%s #%d", config.name:get(), config.index:get())
end

-- Short form
config_short = function(config)
  return string.format("#%d", config.index:get())
end

-- Target counter within config
config_target_counter = function(session)
  local cfg = session.config:get()
  if not cfg then return "" end
  
  local current_index = 0
  local i = 0
  for target in cfg.targets:iter() do
    i = i + 1
    if target._id == session._id then
      current_index = i
      break
    end
  end
  
  return string.format("[%d/%d]", current_index, cfg.targetCount:get())
end

-- Config state indicator
config_state = function(config)
  local stopped = config.stoppedTargetCount:get()
  local total = config.targetCount:get()
  if stopped > 0 then
    return string.format("⏸ %d/%d", stopped, total)
  else
    return string.format("▶ %d", total)
  end
end
```

## Migration / Backwards Compatibility

- Existing code uses `debugger.sessions`, `debugger.leafSessions` - unchanged
- Config is additive, not breaking
- Old keymaps/commands continue to work on focused session
- New commands provide Config-level operations

## Open Questions

1. **Specification storage**: Store full configuration tables? Or just names for re-resolution from launch.json?

2. **preLaunchTask handling**: If configuration has preLaunchTask, should restart re-run it?

3. **Multi-root workspace**: Different configurations from different workspace folders - same Config or separate?

4. **DAP restartRequest**: Some adapters support restart. Use that vs terminate+relaunch?

5. **Partial failure**: If 2/3 configurations in compound fail to start, what's Config state?

6. **Focus on terminate**: When Config terminates, where should focus go? Next active Config?

7. **Naming collision**: `session.config` vs `session.configuration` (if we add stored spec reference)?
