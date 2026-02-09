# Variable Model

This document describes neodap's unified model for variables, expressions, and values.

## Core Insight

In DAP, variables can be addressed two ways:
1. **Scope path**: `variablesReference` + `name`
2. **Expression**: `evaluateName` or any valid expression

These are two ways to reach the same underlying value. The `evaluateName` field bridges them — it's the expression form of a variable found via scope traversal.

## Single Core Entity: Variable

**Variable** represents any value in the debugger — whether found via scope traversal or expression evaluation.

```
┌─────────────────────────────────────────────────────────────┐
│                         Variable                            │
├─────────────────────────────────────────────────────────────┤
│  uri                 - unique identifier                    │
│  name                - display name within parent           │
│  value               - current value                        │
│  type                - type annotation                      │
│  variablesReference  - children handle (if > 0)             │
│  evaluateName        - expression to address this variable  │
├─────────────────────────────────────────────────────────────┤
│  Edges:                                                     │
│    scope    → Scope     (if found via scope)                │
│    parent   → Variable  (if nested in another variable)     │
│    frame    → Frame     (if found via expression)           │
│    children → Variable  (structured children)               │
│    outputs  → Output    (if referenced by REPL log)         │
├─────────────────────────────────────────────────────────────┤
│  Editable if: evaluateName OR scope OR parent               │
└─────────────────────────────────────────────────────────────┘
```

## Two Ways to Find a Variable

```
By Scope Path                          By Expression
─────────────────                      ─────────────────
Frame                                  Frame
  └─► Scope                              └─► evaluate(expr)
        └─► variablesReference                   │
              └─► Variable ◄─────────────────────┘
                    │
                    └─► evaluateName (bridges the two)
```

### Scope Traversal

```lua
-- Frame → Scope → variables request → Variable
frame:fetchScopes()
for scope in frame.scopes:iter() do
  scope:fetchVariables()
  for variable in scope.variables:iter() do
    -- Variable has: name, value, evaluateName, variablesReference
  end
end
```

### Expression Evaluation

```lua
-- Frame + expression → Variable
local variable = frame:variable("obj.items[0].name")
-- Variable has: name, value, evaluateName, variablesReference
```

Both paths yield the same Variable entity structure.

## Two Ways to Edit a Variable

| Method | DAP Request | When to Use |
|--------|-------------|-------------|
| By scope path | `setVariable(variablesReference, name, value)` | Have parent scope/variable |
| By expression | `setExpression(expression, value, frameId)` | Have `evaluateName` |

### Unified setValue()

`Variable:setValue()` picks the right DAP request automatically:

```lua
function Variable:setValue(newValue)
  local evaluateName = self.evaluateName:get()
  local scope = self.scope:get()
  local parent = self.parent:get()

  if evaluateName then
    -- Address by expression
    local frame = self:findFrame()
    dap:setExpression({
      expression = evaluateName,
      value = newValue,
      frameId = frame.frameId
    })
  elseif scope then
    -- Address by scope path
    dap:setVariable({
      variablesReference = scope.variablesReference:get(),
      name = self.name:get(),
      value = newValue
    })
  elseif parent then
    -- Address by parent variable
    dap:setVariable({
      variablesReference = parent.variablesReference:get(),
      name = self.name:get(),
      value = newValue
    })
  else
    error("Variable is not editable")
  end
end
```

## Three Use Cases

### 1. Scope Traversal (Variables Panel)

User expands scope in variables panel, sees and edits variables.

```
Frame → Scope { variablesReference: 5 }
                        │
                        ▼
              Variable {
                name: "count",
                value: "42",
                evaluateName: "count"
              }
                        │
                        ▼
              setValue("100") → setVariable or setExpression
```

### 2. Addressable Expression (Source Hover/Edit)

User hovers over `obj.items[0].name` in source code, wants to edit it.

```
Frame + expression "obj.items[0].name"
                        │
                        ▼
                   evaluate()
                        │
                        ▼
              Variable {
                value: "apple",
                evaluateName: "obj.items[0].name"
              }
                        │
                        ▼
              setValue("banana") → setExpression
```

### 3. Computed Expression (REPL)

User types `getConfig()` — can't assign to result, but children may be editable.

```
Frame + expression "getConfig()"
              │
              ▼
         evaluate()
              │
              ▼
    Variable (root) {
      value: "{timeout: 30}",
      variablesReference: 5,
      evaluateName: nil        ← NOT editable
    }
              │
              ▼
       fetchChildren()
              │
              ▼
    Variable (child) {
      name: "timeout",
      value: "30",
      evaluateName: "getConfig().timeout"  ← editable!
    }
```

## Editability Rules

| Has evaluateName? | Has scope/parent? | Editable? | Edit Method |
|-------------------|-------------------|-----------|-------------|
| Yes | — | Yes | setExpression |
| No | Yes | Yes | setVariable |
| No | No | No | — |

A computed expression like `x + 1` or `getConfig()` has no `evaluateName` and no scope parent, so it's not editable. But its children (fetched via `variablesReference`) may have `evaluateName` and be editable.

## Output Entity

**Output** is a log entry — it records that something happened.

```
┌─────────────────────────────────────────────────────────────┐
│                          Output                             │
├─────────────────────────────────────────────────────────────┤
│  uri       - unique identifier                              │
│  seq       - sequence number                                │
│  text      - display text                                   │
│  category  - stdout, stderr, console, repl, telemetry       │
├─────────────────────────────────────────────────────────────┤
│  Edges:                                                     │
│    session  → Session   (console history)                   │
│    variable → Variable  (optional link to REPL result)      │
└─────────────────────────────────────────────────────────────┘
```

- **Output** = immutable record ("this happened")
- **Variable** = live data (can be modified)
- For REPL results, Output links to Variable when the result is addressable

### REPL Flow

```
User types "obj.name" in REPL
              │
              ▼
    frame:variable("obj.name")
              │
              ▼
    Variable { value: "hello", evaluateName: "obj.name" }
              │
              ├──► Output { text: "obj.name → hello", variable: <link> }
              │
              └──► User can edit Variable, Output stays as history
```

## API

### Ephemeral Evaluation

For display-only use cases (inline values, computed expressions):

```lua
local value, variablesReference, type = frame:evaluate("x + 1")
-- Returns tuple, no entity created
-- Use when you just need the value
```

### Persistent Variable

For interactive use cases (REPL, expression editing):

```lua
local variable = frame:variable("obj.name")
-- Returns Variable entity (creates or finds existing)
-- Can expand children, edit value, bind to UI
variable:setValue("newValue")
```

## Summary

| Concept | Entity | Notes |
|---------|--------|-------|
| Any value | Variable | Universal container |
| Addressable value | Variable with `evaluateName` or scope | Can edit |
| Computed result | Variable without `evaluateName` | Can't edit root, children may be editable |
| Log entry | Output | Links to Variable for REPL |

**One entity (Variable) for all values. Two ways to find it (scope or expression). One method to edit it (setValue picks the right DAP request).**
