# Config Entity Acceptance Criteria

User-facing acceptance criteria for the Config entity implementation.

## Commands

### `:Dap start {name}`

| Scenario | Expected Outcome |
|----------|------------------|
| Start single configuration "App A: Debug" | Config #1 "App A: Debug" created, visible in tree/lualine |
| Start compound "Debug Both Apps" | Config #1 "Debug Both Apps" created with multiple roots |
| Start "App A: Debug" again while #1 exists | Config #2 "App A: Debug" created (separate instance) |
| Start "Debug Both Apps" again while #1 exists | Config #2 "Debug Both Apps" created (separate instance) |

### `:Dap stop`

| Scenario | Expected Outcome |
|----------|------------------|
| Focus on target, run `:Dap stop` | Target's root tree terminates; Config remains (may become terminated state) |
| Config has 2 roots, stop one | One root tree terminates; Config still active (other root running) |
| Config has 1 root, stop it | Root terminates; Config state becomes "terminated" |

### `:Dap stop config`

| Scenario | Expected Outcome |
|----------|------------------|
| Focus on any session in Config #1 | All roots in Config #1 terminate; Config state -> "terminated" |
| Config #2 exists | Config #2 unaffected |

### `:Dap stop all`

| Scenario | Expected Outcome |
|----------|------------------|
| Multiple Configs exist | All Configs terminate all their roots |

### `:Dap restart`

| Scenario | Expected Outcome |
|----------|------------------|
| Focus on target in Config #1 | Target's root terminates -> new root starts in **same** Config #1 |
| Config #1 had 2 roots, restart one | One root replaced; other root unaffected; same Config #1 |

### `:Dap restart config`

| Scenario | Expected Outcome |
|----------|------------------|
| Focus on any session in Config #1 | All roots terminate -> all roots restart in **same** Config #1 |
| Config index | Remains #1 (not #2) |

### `:Dap configs`

| Scenario | Expected Outcome |
|----------|------------------|
| Multiple Configs exist | Picker shows all Configs with state indicators |
| Select a Config | Focus moves to first stopped target (or first target) in that Config |

### `:Dap targets`

| Scenario | Expected Outcome |
|----------|------------------|
| Multiple Configs with targets | Picker shows targets grouped by Config |
| Select a target | Focus moves to that target |

## Session Lifecycle -> Config State

### Session Created

| Event | Config Effect |
|-------|---------------|
| Root session created (from `:Dap start`) | Session linked to Config, `isConfigRoot = true` |
| Child session spawned (DAP protocol) | Session inherits parent's Config, `isConfigRoot = false` |
| Session becomes leaf (`leaf = true`) | Appears in `config.targets` |

### Session Running

| Event | Config Effect |
|-------|---------------|
| Session state -> "running" | Config state -> "active" (if was terminated) |
| Thread stops in target | Config unchanged; target shows stopped indicator |

### Session Terminated

| Event | Config Effect |
|-------|---------------|
| One session terminates, others running | Config remains "active" |
| All sessions terminate | Config state -> "terminated" |
| Session was only target | `config.targets` becomes empty; `config.targetCount` = 0 |

### Session Restarted

| Event | Config Effect |
|-------|---------------|
| Root restarted via `:Dap restart` | Old sessions unlinked; new sessions linked to **same** Config |
| New root creates children | Children inherit same Config |
| Config index | Unchanged |

## Tree Display

### Sessions Tree

| State | Display |
|-------|---------|
| Single Config, single root | `Config #1 "App A" > root > targets` |
| Single Config, compound | `Config #1 "Debug Both" > root A > targets` <br> `                      > root B > targets` |
| Multiple Configs | `Config #1 "Debug Both" > ...` <br> `Config #2 "Debug Both" > ...` |
| Config terminated | Greyed out or marked with indicator |

### Targets Tree

| State | Display |
|-------|---------|
| Multiple Configs | Targets grouped under Config headers |
| Focus on target | Target highlighted; Config header shows context |

## Lualine Display

| State | Display |
|-------|---------|
| Single Config, single target | `[pause] server.js [#1]` |
| Single Config, multiple targets | `[pause] server.js [#1: 1/3]` |
| Multiple Configs | `[pause] server.js [#1: 1/3]` (shows focused Config) |
| Config terminated, still displayed | `[stop] server.js [#1: 0/0]` or hidden |

## Focus Behavior

| Event | Behavior |
|-------|----------|
| New Config started | Focus moves to first stopped target in new Config |
| Thread stops in same Config as focus | Auto-focus to stopped target |
| Thread stops in different Config | No auto-focus (stays on current) |
| `:Dap restart` | Focus follows to new target in same Config |
| Config terminates while focused | Focus moves to next active Config (or clears) |

## Overseer Integration

| Event | Overseer Task |
|-------|---------------|
| `:Dap start` via Overseer | Task created = Config representation |
| Config terminates | Task completes |
| Task restarted | Config restarts (same Config entity, new sessions) |
| Task name | Shows Config name with index |
