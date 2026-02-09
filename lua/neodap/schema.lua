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
  -- Config (running instance of a configuration/compound)
  ---------------------------------------------------------------------------
  Config = {
    -- Properties
    uri = "string",
    configId = "string",
    name = "string",
    index = "number",
    state = "string",              -- "active" | "terminated"
    isCompound = "bool",
    stopAll = "bool",              -- compound: terminate all sessions when any terminates
    postDebugTask = "string",      -- compound: overseer task to run when Config terminates
    viewMode = "string",           -- "targets" | "roots" (for tree display)

    -- Stored data (not edges) - for restart capability
    specifications = "table",      -- original configuration specs

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
        { name = "by_leaf_state", fields = { { name = "leaf" }, { name = "state" } } },
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

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },
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

    -- Rollups: property
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

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
      { name = "by_configId", fields = { { name = "configId" } } },
      { name = "by_state", fields = { { name = "state" } } },
      { name = "by_name", fields = { { name = "name" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Debugger (singleton root)
  ---------------------------------------------------------------------------
  Debugger = {
    -- Properties
    uri = "string",
    focusedUrl = "string",

    -- Edges
    configs = {
      type = "edge",
      target = "Config",
      reverse = "debuggers",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_state", fields = { { name = "state" } } },
        { name = "by_index", fields = { { name = "index" } } },
        { name = "by_name", fields = { { name = "name" } } },
      },
    },
    activeConfigs = {
      type = "collection",
      edge = "configs",
      filters = { { field = "state", value = "terminated", op = "ne" } },
    },
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
        { name = "by_key",  fields = { { name = "key" } } },
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
    configsGroups = { type = "edge", target = "Configs", reverse = "debuggers" },
    sessionsGroups = { type = "edge", target = "Sessions", reverse = "debuggers" },
    targets = { type = "edge", target = "Targets", reverse = "debuggers" },
    exceptionFiltersGroups = { type = "edge", target = "ExceptionFiltersGroup", reverse = "debuggers" },
    exceptionFilters = {
      type = "edge",
      target = "ExceptionFilter",
      reverse = "debuggers",
      __indexes = {
        { name = "default",          fields = {} },
        { name = "by_filterId",      fields = { { name = "filterId" } } },
        { name = "by_defaultEnabled", fields = { { name = "defaultEnabled" } } },
      }
    },

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
    exceptionFilterCount = { type = "count", edge = "exceptionFilters" },
    enabledExceptionFilterCount = {
      type = "count",
      edge = "exceptionFilters",
      filter = { defaultEnabled = true }
    },
    configCount = { type = "count", edge = "configs" },
    activeConfigCount = {
      type = "count",
      edge = "configs",
      filters = { { field = "state", value = "terminated", op = "ne" } },
    },

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
    fallbackFiletype = "string", -- Fallback filetype from adapter (for virtual sources)
    presentationHint = "string", -- "normal" | "emphasize" | "deemphasize"

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
    -- Override properties (nil = inherit from Breakpoint)
    enabled = "bool",
    condition = "string",
    hitCondition = "string",
    logMessage = "string",

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
    isConfigRoot = "bool",      -- true if this session was created directly from a configuration
    adapterTaskId = "number",   -- Backend task ID for adapter process
    sessionTaskId = "number",   -- Backend task ID for session lifecycle
    terminalBufnr = "number",   -- Buffer number for integratedTerminal (nil if using DAP output events)
    logDir = "string",          -- Temp directory for session logs (stdout.log, stderr.log, etc.)
    fallbackFiletype = "string", -- Fallback filetype for virtual sources (from adapter config)

    -- Edges
    configs = { type = "edge", target = "Config", reverse = "sessions" },
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
        { name = "by_seq",      fields = { { name = "seq", dir = "asc" } } },
        { name = "by_seq_desc", fields = { { name = "seq", dir = "desc" } } },
        { name = "by_visible", fields = { { name = "visible" } } },
        { name = "by_visible_seq_desc", fields = { { name = "visible" }, { name = "seq", dir = "desc" } } },
      }
    },
    -- All outputs visible to this session (own outputs + ancestor outputs)
    -- Populated by linking ancestor outputs when child sessions are created,
    -- and by propagating new outputs to descendant sessions
    allOutputs = {
      type = "edge",
      target = "Output",
      reverse = "allSessions",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_globalSeq", fields = { { name = "globalSeq", dir = "asc" } } },
        { name = "by_visible", fields = { { name = "visible" } } },
        { name = "by_visible_globalSeq", fields = { { name = "visible" }, { name = "globalSeq", dir = "asc" } } },
        { name = "by_visible_matched_globalSeq_desc", fields = { { name = "visible" }, { name = "matched" }, { name = "globalSeq", dir = "desc" } } },
      }
    },
    exceptionFilterBindings = {
      type = "edge",
      target = "ExceptionFilterBinding",
      reverse = "sessions",
      __indexes = {
        { name = "default", fields = {} },
      }
    },
    stdios = { type = "edge", target = "Stdio", reverse = "sessions" },
    threadGroups = { type = "edge", target = "Threads", reverse = "sessions" },

    -- Rollups: reference
    config = { type = "reference", edge = "configs" },
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
    outputCount = {
      type = "count",
      edge = "outputs",
      filters = { { field = "visible", value = true } }
    },

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
    consoleOutputs = {
      type = "collection",
      edge = "allOutputs",
      filters = { { field = "visible", value = true } },
      sort = { field = "globalSeq", dir = "asc" }
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
    presentationHint = "string", -- "normal" | "label" | "subtle"

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
    variables = {
      type = "edge",
      target = "Variable",
      reverse = "frames",
      __indexes = {
        { name = "default",         fields = {} },
        { name = "by_evaluateName", fields = { { name = "evaluateName" } } },
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
    outputs = { type = "edge", target = "Output", reverse = "children" },
    frames = { type = "edge", target = "Frame", reverse = "variables" },
    repl = { type = "edge", target = "Output", reverse = "variables" },
    children = {
      type = "edge",
      target = "Variable",
      reverse = "parents",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_name", fields = { { name = "name" } } },
      }
    },

    -- Rollups: reference
    scope = { type = "reference", edge = "scopes" },
    parent = { type = "reference", edge = "parents" },
    output = { type = "reference", edge = "outputs" },
    frame = { type = "reference", edge = "frames" },

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
    globalSeq = "number",  -- Global sequence across all sessions for ordering
    text = "string",
    category = "string",
    group = "string",
    line = "number",
    column = "number",
    variablesReference = "number",
    visible = "bool",  -- false for telemetry, true otherwise (used by console view)
    matched = "bool",  -- true by default, set to false when a console regex filter excludes this output

    -- Edges
    sessions = { type = "edge", target = "Session", reverse = "outputs" },
    allSessions = { type = "edge", target = "Session", reverse = "allOutputs" },  -- Sessions where this output is visible
    sources = { type = "edge", target = "Source", reverse = "outputs" },
    variables = { type = "edge", target = "Variable", reverse = "repl" },
    children = {
      type = "edge",
      target = "Variable",
      reverse = "outputs",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_name", fields = { { name = "name" } } },
      }
    },

    -- Rollups: reference
    session = { type = "reference", edge = "sessions" },
    source = { type = "reference", edge = "sources" },
    variable = { type = "reference", edge = "variables" },

    -- Rollups: property
    childCount = { type = "count", edge = "children" },
    hasChildren = { type = "any", edge = "children" },

    __indexes = {
      { name = "default",     fields = { { name = "uri" } } },
      { name = "by_seq",      fields = { { name = "seq", dir = "asc" } } },
      { name = "by_globalSeq", fields = { { name = "globalSeq", dir = "asc" } } },
      { name = "by_category", fields = { { name = "category" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- ExceptionFilter (global, persistent across sessions)
  ---------------------------------------------------------------------------
  ExceptionFilter = {
    -- Properties
    uri = "string",
    filterId = "string",
    label = "string",
    description = "string",
    defaultEnabled = "bool",      -- global default state
    supportsCondition = "bool",
    conditionDescription = "string",

    -- Edges
    debuggers = { type = "edge", target = "Debugger", reverse = "exceptionFilters" },
    bindings = {
      type = "edge",
      target = "ExceptionFilterBinding",
      reverse = "exceptionFilters",
      __indexes = {
        { name = "default", fields = {} },
      }
    },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },

    __indexes = {
      { name = "default",          fields = { { name = "uri" } } },
      { name = "by_filterId",      fields = { { name = "filterId" } } },
      { name = "by_defaultEnabled", fields = { { name = "defaultEnabled" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- ExceptionFilterBinding (per-session overrides)
  ---------------------------------------------------------------------------
  ExceptionFilterBinding = {
    -- Properties
    uri = "string",
    enabled = "bool",           -- session override (nil = use global default)
    condition = "string",       -- session-specific condition

    -- Edges
    exceptionFilters = { type = "edge", target = "ExceptionFilter", reverse = "bindings" },
    sessions = { type = "edge", target = "Session", reverse = "exceptionFilterBindings" },

    -- Rollups: reference
    exceptionFilter = { type = "reference", edge = "exceptionFilters" },
    session = { type = "reference", edge = "sessions" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
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
  -- ExceptionFiltersGroup (group entity)
  ---------------------------------------------------------------------------
  ExceptionFiltersGroup = {
    -- Properties
    uri = "string",

    -- Edges (uses inline hop: ExceptionFiltersGroup → debuggers → Debugger → exceptionFilters)
    debuggers = { type = "edge", target = "Debugger", reverse = "exceptionFiltersGroups" },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Configs (UI group entity for Config instances)
  -- Primary top-level grouping in debugger tree
  -- Uses inline hop: Configs → debuggers → Debugger → activeConfigs
  ---------------------------------------------------------------------------
  Configs = {
    -- Properties
    uri = "string",

    -- Edges
    debuggers = { type = "edge", target = "Debugger", reverse = "configsGroups" },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },

    __indexes = {
      { name = "default", fields = { { name = "uri" } } },
    },
  },

  ---------------------------------------------------------------------------
  -- Sessions (group entity) - Legacy, kept for backwards compatibility
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
  -- Targets (UI group entity for leaf sessions) - Legacy
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
