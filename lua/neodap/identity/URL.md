# URL Specification

URLs are navigation paths through the entity graph that compile to neograph view queries.

## Syntax

```
URL     := Context? Path
Context := "@" ContextName
Path    := ("/" Segment)+
Segment := Edge Key? Filter? Index?
Edge    := [a-zA-Z_]+
Key     := ":" Value
Filter  := "(" FilterExpr ("," FilterExpr)* ")"
FilterExpr := Field "=" Value
Index   := "[" Number "]"
Value   := Number | Boolean | String
```

## Key Syntax Rule

**Slashes (`/`) separate edges. Colons (`:`) precede key values.**

```
/sessions/threads      ← edges only (all threads in all sessions)
/sessions:abc/threads  ← key lookup (threads in session "abc")
         ↑
         colon, not slash!
```

Wrong: `/sessions/abc/threads` (treats "abc" as an edge name)
Right: `/sessions:abc/threads` (treats "abc" as a session key)

## Examples

| URL | Description |
|-----|-------------|
| `/sessions` | All sessions |
| `/sessions:xotat` | Session with sessionId="xotat" |
| `/sessions/threads` | All threads (across all sessions) |
| `/sessions/threads[0]` | First thread per session |
| `/sessions/threads(state=stopped)` | Stopped threads |
| `/sessions/threads(state=stopped)[0]` | First stopped thread per session |
| `@frame/scopes` | Scopes of focused frame |
| `@session/threads` | Threads of focused session |

## Compilation to View Query

URLs compile to neograph view queries. The key insight:

- **Root type** (e.g., Debugger): always visible in view, filtered out by wrapper
- **All edges**: `eager = true` (auto-expand when parent enters view)
- **Intermediate edges** (all except last): also `inline = true` (hidden in results)
- **Final edge**: only `eager = true` (visible in results)
- **Any segment** can have `filters` and `take` from `(filter)` and `[N]` syntax

Note: The root type cannot have `inline`/`eager` - these only apply to edges.
When a URL has segments, the wrapper filters out root-level items (depth 0).

### Single Segment

```
/sessions
```

```lua
{
  type = "Debugger",
  edges = {
    sessions = { eager = true }
  }
}
```

### Multi-Segment Path

```
/sessions/threads
```

```lua
{
  type = "Debugger",
  edges = {
    sessions = {
      inline = true,
      eager = true,
      edges = {
        threads = { eager = true }
      }
    }
  }
}
```

Result: Thread entities only (Sessions are inline/hidden)

### Index on Intermediate Segment

```
/sessions/threads[0]/stack/frames
```

```lua
{
  type = "Debugger",
  edges = {
    sessions = {
      inline = true,
      eager = true,
      edges = {
        threads = {
          inline = true,
          eager = true,
          take = 1,  -- [0] → take = 1
          edges = {
            stack = {
              inline = true,
              eager = true,
              edges = {
                frames = { eager = true }
              }
            }
          }
        }
      }
    }
  }
}
```

Result: All frames from the first thread of each session

### Filter and Index Combined

```
/sessions/threads(state=stopped)[0]/stack/frames[0]
```

```lua
{
  type = "Debugger",
  edges = {
    sessions = {
      inline = true,
      eager = true,
      edges = {
        threads = {
          inline = true,
          eager = true,
          filters = {{ field = "state", value = "stopped" }},
          take = 1,
          edges = {
            stack = {
              inline = true,
              eager = true,
              edges = {
                frames = {
                  eager = true,
                  take = 1
                }
              }
            }
          }
        }
      }
    }
  }
}
```

Result: Top frame from the first stopped thread of each session

### Key Lookup

```
/sessions:xotat/threads
```

```lua
{
  type = "Debugger",
  edges = {
    sessions = {
      inline = true,
      eager = true,
      filters = {{ field = "sessionId", value = "xotat" }},
      edges = {
        threads = { eager = true }
      }
    }
  }
}
```

Result: Threads of the session with sessionId="xotat"

## Index Semantics

`[N]` translates to `skip = N, take = 1`:

| Syntax | View Config |
|--------|-------------|
| `[0]` | `take = 1` |
| `[1]` | `skip = 1, take = 1` |
| `[N]` | `skip = N, take = 1` |

The index is applied **per parent**, not globally. `/sessions/threads[0]` returns the first thread of **each** session.

## Key Field Mapping

The `:key` syntax maps to a field based on the edge name:

| Edge | Key Field |
|------|-----------|
| `sessions` | `sessionId` |
| `threads` | `threadId` |
| `frames` | `frameId` |
| `stacks` | `index` |
| `scopes` | `name` |
| `variables` | `name` |
| `sources` | `path` |
| `breakpoints` | `uri` |

## Context Resolution

Context markers resolve to focused entities:

| Context | Expands To |
|---------|------------|
| `@debugger` | `debugger` (root) |
| `@session` | `session:{uri}` |
| `@thread` | `thread:{uri}` |
| `@frame` | `frame:{uri}` |

Context markers are expanded via `debugger.ctx:expand(url)` which returns a
reactive signal. When focus changes, the expanded URL updates automatically.

After context resolution, the path is appended as edges:

```
@frame/scopes
```

```lua
-- First resolve @frame to get frame entity
-- Then query from that frame:
{
  type = "Frame",
  id = <focused_frame_id>,
  edges = {
    scopes = { eager = true }
  }
}
```

## View Result Handling

The view returns items. For URL queries:

- **Single result expected** (has `[N]` or `:key` on final segment): return first item or nil
- **Multiple results expected**: return array of items

The view's `on_enter`/`on_leave` callbacks enable reactivity for `watch()`.
