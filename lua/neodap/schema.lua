---@class neodap.schema
local M = {}

--[[
  neodap schema for neograph-native (flat format)

  Naming conventions:
  - Edges are plural: `sessions`, `threads`, `frames`
  - Reference rollups are singular: `session`, `thread`, `frame`
  - Collection rollups are descriptive: `stoppedThreads`, `enabledBreakpoints`
  - Property rollups are descriptive: `threadCount`, `hasStoppedThread`
]]

M.schema = {
  ---------------------------------------------------------------------------
  -- Debugger (singleton root)
  ---------------------------------------------------------------------------
  Debugger = {
    -- Properties
    uri = "string",
    focusedUrl = "string",

    -- Edges
    sessions = {
      type = "edge",
      target = "Session",
      reverse = "debuggers",
      __indexes = {
        { name = "default",      fields = {} },
        { name = "by_sessionId", fields = { { name = "sessionId" } } },
        { name = "by_state",     fields = { { name = "state" } } },
        { name = "by_leaf",      fields = { { name = "leaf" } } },
      }
    },
    rootSessions = { type = "edge", target = "Session", reverse = "rootOfs" },
    leafSessions = {
      type = "collection",
      edge = "sessions",
      filter = { leaf = true }
    },
    sources = {
      type = "edge",
      target = "Source",
      reverse = "debuggers",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_path", fields = { { name = "path" } } },
      }
    },
    breakpoints = {
      type = "edge",
      target = "Breakpoint",
      reverse = "debuggers",
      __indexes = {
        { name = "default",         fields = {} },
        { name = "by_uri",          fields = { { name = "uri" } } },
        { name = "by_enabled",      fields = { { name = "enabled" } } },
        { name = "by_condition",    fields = { { name = "condition" } } },
        { name = "by_line",         fields = { { name = "line" } } },
        { name = "by_enabled_line", fields = { { name = "enabled" }, { name = "line" } } },
        { name = "by_line_enabled", fields = { { name = "line" }, { name = "enabled" } } },
      }
    },
    breakpointsGroups = { type = "edge", target = "Breakpoints", reverse = "debuggers" },
    sessionsGroups = { type = "edge", target = "Sessions", reverse = "debuggers" },
    targets = { type = "edge", target = "Targets", reverse = "debuggers" },

    -- Rollups: reference
    firstSession = { type = "reference", edge = "sessions" },
    firstRootSession = { type = "reference", edge = "rootSessions" },

    -- Rollups: property
    sessionCount = { type = "count", edge = "sessions" },
    rootSessionCount = { type = "count", edge = "rootSessions" },
    leafSessionCount = {
      type = "count",
      edge = "sessions",
      filter = { leaf = true }
    },
    breakpointCount = { type = "count", edge = "breakpoints" },
    sourceCount = { type = "count", edge = "sources" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Source
  ---------------------------------------------------------------------------
  Source = {
    -- Properties
    uri = "string",
    key = "string",
    path = "string",
    name = "string",
    content = "string",

    -- Edges
    debuggers = { type = "edge", target = "Debugger", reverse = "sources" },
    bindings = { type = "edge", target = "SourceBinding", reverse = "sources" },
    breakpoints = {
      type = "edge",
      target = "Breakpoint",
      reverse = "sources",
      __indexes = {
        { name = "default",    fields = {} },
        { name = "by_line",    fields = { { name = "line", dir = "asc" } } },
        { name = "by_enabled", fields = { { name = "enabled" } } },
      }
    },
    frames = {
      type = "edge",
      target = "Frame",
      reverse = "sources",
      __indexes = {
        { name = "default",   fields = {} },
        { name = "by_active", fields = { { name = "active" } } },
      }
    },
    outputs = { type = "edge", target = "Output", reverse = "sources" },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },

    -- Rollups: property
    breakpointCount = { type = "count", edge = "breakpoints" },
    bindingCount = { type = "count", edge = "bindings" },

    -- Rollups: collection
    breakpointsByLine = {
      type = "collection",
      edge = "breakpoints",
      sort = { field = "line", dir = "asc" }
    },
    enabledBreakpoints = {
      type = "collection",
      edge = "breakpoints",
      filters = { { field = "enabled", value = true } }
    },
    activeFrames = {
      type = "collection",
      edge = "frames",
      filters = { { field = "active", value = true } }
    },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
      { name = "by_key",  fields = { { name = "key" } } },
      { name = "by_path", fields = { { name = "path" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- SourceBinding
  ---------------------------------------------------------------------------
  SourceBinding = {
    -- Properties
    uri = "string",
    sourceReference = "number",

    -- Edges
    sources = { type = "edge", target = "Source", reverse = "bindings" },
    sessions = { type = "edge", target = "Session", reverse = "sourceBindings" },
    breakpointBindings = { type = "edge", target = "BreakpointBinding", reverse = "sourceBindings" },

    -- Rollups: reference
    source = { type = "reference", edge = "sources" },
    session = { type = "reference", edge = "sessions" },

    __indexes = {
      { name = "default",      fields = { { name = "uri" } } },
      { name = "by_sourceRef", fields = { { name = "sourceReference" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Breakpoint
  ---------------------------------------------------------------------------
  Breakpoint = {
    -- Properties
    uri = "string",
    line = "number",
    column = "number",
    condition = "string",
    hitCondition = "string",
    logMessage = "string",
    enabled = "bool",

    -- Edges
    debuggers = { type = "edge", target = "Debugger", reverse = "breakpoints" },
    sources = { type = "edge", target = "Source", reverse = "breakpoints" },
    bindings = {
      type = "edge",
      target = "BreakpointBinding",
      reverse = "breakpoints",
      __indexes = {
        { name = "default",     fields = {} },
        { name = "by_hit",      fields = { { name = "hit" } } },
        { name = "by_verified", fields = { { name = "verified" } } },
      }
    },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },
    source = { type = "reference", edge = "sources" },
    hitBinding = {
      type = "reference",
      edge = "bindings",
      filters = { { field = "hit", value = true } }
    },
    verifiedBinding = {
      type = "reference",
      edge = "bindings",
      filters = { { field = "verified", value = true } }
    },

    -- Rollups: property
    bindingCount = { type = "count", edge = "bindings" },
    hasHitBinding = {
      type = "any",
      edge = "bindings",
      filters = { { field = "hit", value = true } }
    },
    hasVerifiedBinding = {
      type = "any",
      edge = "bindings",
      filters = { { field = "verified", value = true } }
    },
    verifiedCount = {
      type = "count",
      edge = "bindings",
      filters = { { field = "verified", value = true } }
    },

    __indexes = {
      { name = "default",    fields = { { name = "uri" } } },
      { name = "by_line",    fields = { { name = "line", dir = "asc" } } },
      { name = "by_enabled", fields = { { name = "enabled" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- BreakpointBinding
  ---------------------------------------------------------------------------
  BreakpointBinding = {
    -- Properties
    uri = "string",
    breakpointId = "number",
    verified = "bool",
    hit = "bool",
    message = "string",
    actualLine = "number",
    actualColumn = "number",

    -- Edges
    breakpoints = { type = "edge", target = "Breakpoint", reverse = "bindings" },
    sourceBindings = { type = "edge", target = "SourceBinding", reverse = "breakpointBindings" },

    -- Rollups: reference
    breakpoint = { type = "reference", edge = "breakpoints" },
    sourceBinding = { type = "reference", edge = "sourceBindings" },

    __indexes = {
      { name = "default",         fields = { { name = "uri" } } },
      { name = "by_breakpointId", fields = { { name = "breakpointId" } } },
      { name = "by_verified",     fields = { { name = "verified" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Session
  ---------------------------------------------------------------------------
  Session = {
    -- Properties
    uri = "string",
    sessionId = "string",
    name = "string",
    state = "string",
    leaf = "bool",

    -- Edges
    debuggers = { type = "edge", target = "Debugger", reverse = "sessions" },
    rootOfs = { type = "edge", target = "Debugger", reverse = "rootSessions" },
    rootGroups = { type = "edge", target = "Sessions", reverse = "sessions" },
    parents = { type = "edge", target = "Session", reverse = "children" },
    children = { type = "edge", target = "Session", reverse = "parents" },
    threads = {
      type = "edge",
      target = "Thread",
      reverse = "sessions",
      __indexes = {
        { name = "default",     fields = {} },
        { name = "by_threadId", fields = { { name = "threadId" } } },
        { name = "by_state",    fields = { { name = "state" } } },
        { name = "by_focused",  fields = { { name = "focused" } } },
        { name = "by_stops",  fields = { { name = "stops" } } },
      }
    },
    sourceBindings = { type = "edge", target = "SourceBinding", reverse = "sessions" },
    outputs = {
      type = "edge",
      target = "Output",
      reverse = "sessions",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_seq",  fields = { { name = "seq", dir = "asc" } } },
      }
    },
    exceptionFilters = {
      type = "edge",
      target = "ExceptionFilter",
      reverse = "sessions",
      __indexes = {
        { name = "default",             fields = {} },
        { name = "by_filterId",         fields = { { name = "filterId" } } },
        { name = "by_filterId_enabled", fields = { { name = "filterId" }, { name = "enabled" } } },
        { name = "by_enabled_filterId", fields = { { name = "enabled" }, { name = "filterId" } } },
      }
    },
    stdios = { type = "edge", target = "Stdio", reverse = "sessions" },
    threadGroups = { type = "edge", target = "Threads", reverse = "sessions" },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },
    rootOf = { type = "reference", edge = "rootOfs" },
    rootGroup = { type = "reference", edge = "rootGroups" },
    parent = { type = "reference", edge = "parents" },
    stdio = { type = "reference", edge = "stdios" },
    threadGroup = { type = "reference", edge = "threadGroups" },
    firstThread = { type = "reference", edge = "threads" },
    focusedThread = {
      type = "reference",
      edge = "threads",
      filters = { { field = "focused", value = true } }
    },
    firstStoppedThread = {
      type = "reference",
      edge = "threads",
      filters = { { field = "state", value = "stopped" } }
    },

    -- Rollups: property
    threadCount = { type = "count", edge = "threads" },
    stoppedThreadCount = {
      type = "count",
      edge = "threads",
      filters = { { field = "state", value = "stopped" } }
    },
    hasStoppedThread = {
      type = "any",
      edge = "threads",
      filters = { { field = "state", value = "stopped" } }
    },
    childCount = { type = "count", edge = "children" },
    outputCount = { type = "count", edge = "outputs" },

    -- Rollups: collection
    stoppedThreads = {
      type = "collection",
      edge = "threads",
      filters = { { field = "state", value = "stopped" } }
    },
    runningThreads = {
      type = "collection",
      edge = "threads",
      filters = { { field = "state", value = "running" } }
    },

    __indexes = {
      { name = "default",      fields = { { name = "uri" } } },
      { name = "by_sessionId", fields = { { name = "sessionId" } } },
      { name = "by_leaf",      fields = { { name = "leaf" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Thread
  ---------------------------------------------------------------------------
  Thread = {
    -- Properties
    uri = "string",
    threadId = "number",
    name = "string",
    state = "string",
    focused = "bool",
    stops = "number",

    -- Edges
    sessions = { type = "edge", target = "Session", reverse = "threads" },
    stacks = {
      type = "edge",
      target = "Stack",
      reverse = "threads",
      __indexes = {
        { name = "default", fields = { { name = "index", dir = "asc" } } },
        { name = "by_seq",  fields = { { name = "seq" } } },
      }
    },
    currentStacks = {
      type = "edge",
      target = "Stack",
      reverse = "stackOfs",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_seq",  fields = { { name = "seq" } } },
      }
    },

    -- Rollups: reference
    session = { type = "reference", edge = "sessions" },
    currentStack = {
      type = "reference",
      edge = "stacks",
      sort = { field = "index", dir = "asc" }
    },
    stack = { type = "reference", edge = "currentStacks" },

    -- Rollups: property
    stackCount = { type = "count", edge = "stacks" },

    __indexes = {
      { name = "default",     fields = { { name = "uri" } } },
      { name = "by_threadId", fields = { { name = "threadId" } } },
      { name = "by_state",    fields = { { name = "state" } } },
      { name = "by_focused",  fields = { { name = "focused" } } },
      { name = "by_stops",  fields = { { name = "stops" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Stack
  ---------------------------------------------------------------------------
  Stack = {
    -- Properties
    uri = "string",
    index = "number",
    seq = "number",

    -- Edges
    threads = { type = "edge", target = "Thread", reverse = "stacks" },
    frames = {
      type = "edge",
      target = "Frame",
      reverse = "stacks",
      __indexes = {
        { name = "default",    fields = {} },
        { name = "by_frameId", fields = { { name = "frameId" } } },
        { name = "by_index",   fields = { { name = "index", dir = "asc" } } },
        { name = "by_focused", fields = { { name = "focused" } } },
        { name = "by_line",    fields = { { name = "line" } } },
      }
    },
    stackOfs = { type = "edge", target = "Thread", reverse = "currentStacks" },

    -- Rollups: reference
    thread = { type = "reference", edge = "threads" },
    stackOf = { type = "reference", edge = "stackOfs" },
    topFrame = {
      type = "reference",
      edge = "frames",
      sort = { field = "index", dir = "asc" }
    },
    focusedFrame = {
      type = "reference",
      edge = "frames",
      filters = { { field = "focused", value = true } }
    },

    -- Rollups: property
    frameCount = { type = "count", edge = "frames" },
    topFrameName = {
      type = "first",
      edge = "frames",
      property = "name"
    },

    __indexes = {
      { name = "default",  fields = { { name = "uri" } } },
      { name = "by_index", fields = { { name = "index", dir = "asc" } } },
      { name = "by_seq",   fields = { { name = "seq" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Frame
  ---------------------------------------------------------------------------
  Frame = {
    -- Properties
    uri = "string",
    frameId = "number",
    index = "number",
    name = "string",
    line = "number",
    column = "number",
    focused = "bool",
    active = "bool",

    -- Edges
    stacks = { type = "edge", target = "Stack", reverse = "frames" },
    sources = { type = "edge", target = "Source", reverse = "frames" },
    scopes = {
      type = "edge",
      target = "Scope",
      reverse = "frames",
      __indexes = {
        { name = "default",             fields = {} },
        { name = "by_name",             fields = { { name = "name" } } },
        { name = "by_presentationHint", fields = { { name = "presentationHint" } } },
      }
    },

    -- Rollups: reference
    stack = { type = "reference", edge = "stacks" },
    source = { type = "reference", edge = "sources" },
    localsScope = {
      type = "reference",
      edge = "scopes",
      filters = { { field = "presentationHint", value = "locals" } }
    },

    -- Rollups: property
    scopeCount = { type = "count", edge = "scopes" },

    __indexes = {
      { name = "default",    fields = { { name = "uri" } } },
      { name = "by_frameId", fields = { { name = "frameId" } } },
      { name = "by_index",   fields = { { name = "index", dir = "asc" } } },
      { name = "by_focused", fields = { { name = "focused" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Scope
  ---------------------------------------------------------------------------
  Scope = {
    -- Properties
    uri = "string",
    name = "string",
    presentationHint = "string",
    expensive = "bool",
    variablesReference = "number",

    -- Edges
    frames = { type = "edge", target = "Frame", reverse = "scopes" },
    variables = {
      type = "edge",
      target = "Variable",
      reverse = "scopes",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_name", fields = { { name = "name" } } },
      }
    },

    -- Rollups: reference
    frame = { type = "reference", edge = "frames" },

    -- Rollups: property
    variableCount = { type = "count", edge = "variables" },

    __indexes = {
      { name = "default",             fields = { { name = "uri" } } },
      { name = "by_name",             fields = { { name = "name" } } },
      { name = "by_presentationHint", fields = { { name = "presentationHint" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Variable
  ---------------------------------------------------------------------------
  Variable = {
    -- Properties
    uri = "string",
    name = "string",
    value = "string",
    varType = "string",
    variablesReference = "number",
    evaluateName = "string",

    -- Edges
    scopes = { type = "edge", target = "Scope", reverse = "variables" },
    parents = { type = "edge", target = "Variable", reverse = "children" },
    children = { type = "edge", target = "Variable", reverse = "parents" },

    -- Rollups: reference
    scope = { type = "reference", edge = "scopes" },
    parent = { type = "reference", edge = "parents" },

    -- Rollups: property
    childCount = { type = "count", edge = "children" },
    hasChildren = { type = "any", edge = "children" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
      { name = "by_name", fields = { { name = "name" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Output
  ---------------------------------------------------------------------------
  Output = {
    -- Properties
    uri = "string",
    seq = "number",
    text = "string",
    category = "string",
    group = "string",
    line = "number",
    column = "number",
    variablesReference = "number",

    -- Edges
    sessions = { type = "edge", target = "Session", reverse = "outputs" },
    sources = { type = "edge", target = "Source", reverse = "outputs" },

    -- Rollups: reference
    session = { type = "reference", edge = "sessions" },
    source = { type = "reference", edge = "sources" },

    __indexes = {
      { name = "default",     fields = { { name = "uri" } } },
      { name = "by_seq",      fields = { { name = "seq", dir = "asc" } } },
      { name = "by_category", fields = { { name = "category" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- ExceptionFilter
  ---------------------------------------------------------------------------
  ExceptionFilter = {
    -- Properties
    uri = "string",
    filterId = "string",
    label = "string",
    description = "string",
    defaultEnabled = "bool",
    supportsCondition = "bool",
    conditionDescription = "string",
    enabled = "bool",
    condition = "string",

    -- Edges
    sessions = { type = "edge", target = "Session", reverse = "exceptionFilters" },

    -- Rollups: reference
    session = { type = "reference", edge = "sessions" },

    __indexes = {
      { name = "default",     fields = { { name = "uri" } } },
      { name = "by_filterId", fields = { { name = "filterId" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Stdio
  ---------------------------------------------------------------------------
  Stdio = {
    -- Properties
    uri = "string",

    -- Edges
    sessions = { type = "edge", target = "Session", reverse = "stdios" },

    -- Rollups: reference
    session = { type = "reference", edge = "sessions" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Threads (UI group entity for tree traversal)
  ---------------------------------------------------------------------------
  Threads = {
    -- Properties
    uri = "string",

    -- Edges
    sessions = { type = "edge", target = "Session", reverse = "threadGroups" },

    -- Rollups: reference
    session = { type = "reference", edge = "sessions" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Breakpoints (group entity)
  ---------------------------------------------------------------------------
  Breakpoints = {
    -- Properties
    uri = "string",

    -- Edges
    debuggers = { type = "edge", target = "Debugger", reverse = "breakpointsGroups" },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Sessions (group entity)
  ---------------------------------------------------------------------------
  Sessions = {
    -- Properties
    uri = "string",

    -- Edges (uses inline hop: Sessions → debuggers → Debugger → rootSessions)
    debuggers = { type = "edge", target = "Debugger", reverse = "sessionsGroups" },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Targets (UI group entity for leaf sessions)
  -- Uses inline hop: Targets → debuggers → Debugger → leafSessions
  ---------------------------------------------------------------------------
  Targets = {
    -- Properties
    uri = "string",

    -- Edges
    debuggers = { type = "edge", target = "Debugger", reverse = "targets" },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
    },
  },
}

return M
