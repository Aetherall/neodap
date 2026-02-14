---@class neodap.schema
local M = {}

--[[
  neodap schema for neograph-native (flat format)

  Naming conventions:
  - Edges are plural: `sessions`, `threads`, `frames`
  - Reference rollups are singular: `session`, `thread`, `frame`
  - Collection rollups are descriptive: `stoppedThreads`, `activeFrames`
  - Property rollups are descriptive: `threadCount`, `targetCount`
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
    -- REMOVED: activeTargets, stoppedTargets (unused)

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
    targetCount = { type = "count", edge = "sessions", filter = { leaf = true } },
    stoppedTargetCount = {
      type = "count",
      edge = "sessions",
      filters = {
        { field = "leaf", value = true },
        { field = "state", value = "stopped" },
      },
    },
    terminatedTargetCount = {
      type = "count",
      edge = "sessions",
      filters = {
        { field = "leaf", value = true },
        { field = "state", value = "terminated" },
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
        { name = "by_name", fields = { { name = "name" } } },
        { name = "by_viewMode", fields = { { name = "viewMode" } } },
      },
    },
    activeConfigs = {
      type = "collection",
      edge = "configs",
      filter = { state = "active" },
    },
    sessions = {
      type = "edge",
      target = "Session",
      reverse = "debuggers",
      __indexes = {
        { name = "default",      fields = {} },
        { name = "by_sessionId", fields = { { name = "sessionId" } } },
        { name = "by_leaf",      fields = { { name = "leaf" } } },
        { name = "by_state",     fields = { { name = "state" } } },
      }
    },
    rootSessions = { type = "edge", target = "Session", reverse = "rootOfs" },

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
        { name = "default", fields = {} },
        { name = "by_line", fields = { { name = "line", dir = "asc" } } },
        { name = "by_enabled", fields = { { name = "enabled" } } },
        { name = "by_condition", fields = { { name = "condition" } } },
        { name = "by_enabled_line", fields = { { name = "enabled" }, { name = "line", dir = "asc" } } },
        { name = "by_line_enabled", fields = { { name = "line", dir = "asc" }, { name = "enabled" } } },
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

    -- Rollups: property
    rootSessionCount = { type = "count", edge = "rootSessions" },
    stoppedSessionCount = {
      type = "count",
      edge = "sessions",
      filter = { state = "stopped" },
    },
    leafSessionCount = {
      type = "count",
      edge = "sessions",
      filter = { leaf = true }
    },
    breakpointCount = { type = "count", edge = "breakpoints" },
    exceptionFilterCount = { type = "count", edge = "exceptionFilters" },
    enabledExceptionFilterCount = {
      type = "count",
      edge = "exceptionFilters",
      filter = { defaultEnabled = true }
    },
    configCount = { type = "count", edge = "configs" },

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
        { name = "default", fields = {} },
        { name = "by_line", fields = { { name = "line", dir = "asc" } } },
      }
    },
    frames = {
      type = "edge",
      target = "Frame",
      reverse = "sources",
      __indexes = {
        { name = "default",   fields = {} },
        { name = "by_active", fields = { { name = "active" } } },
        { name = "by_active_line", fields = { { name = "active" }, { name = "line", dir = "asc" } } },
      }
    },
    outputs = { type = "edge", target = "Output", reverse = "sources" },

    -- Rollups: reference
    debugger = { type = "reference", edge = "debuggers" },
    firstBinding = { type = "reference", edge = "bindings" },

    -- Rollups: property
    breakpointCount = { type = "count", edge = "breakpoints" },
    -- REMOVED: bindingCount, breakpointsByLine, enabledBreakpoints (unused)

    -- Rollups: collection
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
    parents = { type = "edge", target = "Session", reverse = "children" },
    children = {
      type = "edge",
      target = "Session",
      reverse = "parents",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_state", fields = { { name = "state" } } },
      }
    },
    threads = {
      type = "edge",
      target = "Thread",
      reverse = "sessions",
      __indexes = {
        { name = "default",     fields = {} },
        { name = "by_threadId", fields = { { name = "threadId" } } },
        { name = "by_state",    fields = { { name = "state" } } },
      }
    },
    sourceBindings = { type = "edge", target = "SourceBinding", reverse = "sessions" },
    outputs = {
      type = "edge",
      target = "Output",
      reverse = "sessions",
      __indexes = {
        { name = "default", fields = {} },
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
    parent = { type = "reference", edge = "parents" },
    firstThread = { type = "reference", edge = "threads" },
    firstStoppedThread = {
      type = "reference",
      edge = "threads",
      filters = { { field = "state", value = "stopped" } }
    },

    -- Rollups: property
    exceptionFilterBindingCount = { type = "count", edge = "exceptionFilterBindings" },
    childCount = { type = "count", edge = "children" },
    terminatedChildCount = {
      type = "count",
      edge = "children",
      filter = { state = "terminated" },
    },
    threadCount = { type = "count", edge = "threads" },
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
    -- REMOVED: runningThreads, consoleOutputs (unused)

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
        { name = "by_seq", fields = { { name = "seq" } } },
      }
    },
    currentStacks = {
      type = "edge",
      target = "Stack",
      reverse = "stackOfs",
      __indexes = {
        { name = "default", fields = {} },
      }
    },

    -- Rollups: reference
    session = { type = "reference", edge = "sessions" },
    stack = { type = "reference", edge = "currentStacks" },

    __indexes = {
      { name = "default",     fields = { { name = "uri" } } },
      { name = "by_threadId", fields = { { name = "threadId" } } },
      { name = "by_state",    fields = { { name = "state" } } },
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
        { name = "default",  fields = {} },
        { name = "by_index", fields = { { name = "index", dir = "asc" } } },
        { name = "by_line",  fields = { { name = "line", dir = "asc" } } },
      }
    },
    stackOfs = { type = "edge", target = "Thread", reverse = "currentStacks" },

    -- Rollups: reference
    thread = { type = "reference", edge = "threads" },
    topFrame = {
      type = "reference",
      edge = "frames",
      sort = { field = "index", dir = "asc" }
    },
    -- REMOVED: focusedFrame, frameCount, topFrameName (unused)

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
        { name = "default", fields = {} },
        { name = "by_name", fields = { { name = "name" } } },
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

    __indexes = {
      { name = "default",  fields = { { name = "uri" } } },
      { name = "by_index", fields = { { name = "index", dir = "asc" } } },
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

    -- REMOVED: variableCount (unused)

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

    -- REMOVED: childCount, hasChildren (unused; entity method Variable:hasChildren reads variablesReference instead)

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

    -- REMOVED: childCount, hasChildren (unused)

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
  -- Uses inline hop: Configs → debuggers → Debugger → configs
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
