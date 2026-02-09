-- Query edge definitions for tree buffer
-- Format: neograph-native view edges (object-based, not array-based)
-- Note: Use actual edge names (usually plural), not rollup names (singular)
-- eager = true only for edges where data already exists (no fetch needed)
-- on_expand = function(entity) called when expanding into this edge

-- Fetch helpers with termination guards
local function fetch_children(entity)
  local ref = entity.variablesReference and entity.variablesReference:get()
  if ref and ref > 0 and not entity:isSessionTerminated() then
    entity:fetchChildren()
  end
end

local function fetch_variables(entity)
  if not entity:isSessionTerminated() then
    entity:fetchVariables()
  end
end

local function fetch_scopes(entity)
  if not entity:isSessionTerminated() then
    entity:fetchScopes()
  end
end

local function fetch_frames(entity)
  if not entity:isSessionTerminated() then
    -- Stack doesn't have fetchFrames, frames come with stack trace
  end
end

local function fetch_stacks(entity)
  if not entity:isSessionTerminated() then
    entity:fetchStackTrace()
  end
end

local function fetch_threads(entity)
  if not entity:isTerminated() then
    entity:fetchThreads()
  end
end

-- Fetch threads from Threads group by navigating to parent Session
local function fetch_threads_from_group(threads_entity)
  local session = threads_entity.session and threads_entity.session:get()
  if session and not session:isTerminated() then
    session:fetchThreads()
  end
end

local VARIABLE = { children = { recursive = true, on_expand = fetch_children } }
-- Eager for all scopes except Global (too many variables)
local function is_not_global_scope(scope)
  local name = scope.name and scope.name:get()
  return name ~= "Global"
end
local SCOPE = { variables = { eager = is_not_global_scope, edges = VARIABLE, on_expand = fetch_variables } }
local FRAME = { scopes = { edges = SCOPE, on_expand = fetch_scopes } }
local STACK = { frames = { edges = FRAME, on_expand = fetch_frames } }
local THREAD = { stacks = { edges = STACK, on_expand = fetch_stacks } }

local OUTPUT = { children = { edges = VARIABLE, on_expand = fetch_children } }

-- Console: visible+matched outputs (excludes telemetry and regex-filtered) sorted newest-first
-- Used for dap://tree/console:<session_id> tree view
local CONSOLE = {
  allOutputs = {
    eager = true,
    sort = { field = "globalSeq", dir = "desc" },
    filters = { { field = "visible", value = true }, { field = "matched", value = true } },
    edges = OUTPUT,
  }
}

-- Traverse session (inlined) -> outputs: when user expands Stdio, sessions expands,
-- Session enters view (hidden), then outputs eagerly expands showing children under Stdio
-- Filter by visible=true to exclude telemetry
local STDIO = { sessions = { inline = true, edges = { outputs = { eager = true, sort = { field = "seq", dir = "desc" }, filters = { { field = "visible", value = true } }, edges = OUTPUT } }}}

-- Traverse session (inlined) -> threads: when user expands Threads, sessions expands,
-- Session enters view (hidden), then threads eagerly expands showing Thread entities under Threads
-- on_expand fetches threads from parent Session when Threads group is expanded
local THREADS = {
  sessions = { inline = true, on_expand = fetch_threads_from_group, edges = { threads = { eager = true, edges = THREAD } }},
}

local SESSION = {
  children = { eager = true },  -- child sessions already linked
  threadGroups = { eager = true, edges = THREADS },  -- Threads group eager, threads on expand
  stdios = { eager = true, edges = STDIO },  -- Stdio nodes eager, outputs on expand
}

local BREAKPOINT_BINDING = {}
local BREAKPOINT = { bindings = { edges = BREAKPOINT_BINDING } }

local BREAKPOINTS_GROUP = { debuggers = { inline = true, edges = {
  breakpoints = { eager = true, edges = BREAKPOINT },
}}}

-- Exception filter binding edges - shows per-session bindings
local EXCEPTION_FILTER_BINDING = {}

-- Global exception filters with bindings as children (like Breakpoint -> BreakpointBinding)
local EXCEPTION_FILTER = { bindings = { edges = EXCEPTION_FILTER_BINDING } }
local EXCEPTION_FILTERS = { exceptionFilters = { eager = true, edges = EXCEPTION_FILTER } }

-- Exception filters group for debugger tree (like BREAKPOINTS_GROUP)
local EXCEPTION_FILTERS_GROUP = { debuggers = { inline = true, edges = {
  exceptionFilters = { eager = true, edges = EXCEPTION_FILTER },
}}}

local CHILD_SESSION = {
  children = { eager = true, recursive = true },
  threadGroups = { eager = true, edges = THREADS },
  stdios = { eager = true, edges = STDIO },
}

-- Root session edges (used inside Config grouping)
local ROOT_SESSION = {
  children = { eager = true, edges = CHILD_SESSION },
  threadGroups = { eager = true, edges = THREADS },
  stdios = { eager = true, edges = STDIO },
}

-- Target session edges (used inside Config grouping)
local TARGET_SESSION = {
  threadGroups = { eager = true, edges = THREADS },
  stdios = { eager = true, edges = STDIO },
}

-- Config edges for Roots view (shows root sessions with their children)
local CONFIG_ROOTS = {
  roots = { eager = true, edges = ROOT_SESSION },
}

-- Config edges for Targets view (shows leaf sessions directly)
local CONFIG_TARGETS = {
  targets = { eager = true, edges = TARGET_SESSION },
}

-- Build Configs group edges dynamically based on current viewMode settings
-- Called when building the Debugger tree query
---@param debugger? table Debugger entity for querying active configs
---@return table CONFIGS_GROUP edges
local function build_configs_group_edges(debugger)
  -- Determine which edge set to use (majority wins, or default to targets)
  local use_roots = false
  if debugger and debugger.activeConfigs then
    for config in debugger.activeConfigs:iter() do
      local mode = config.viewMode and config.viewMode:get()
      if mode == "roots" then
        use_roots = true
        break -- Use roots if any config is in roots mode
      end
    end
  end
  
  local config_edges = use_roots and CONFIG_ROOTS or CONFIG_TARGETS
  return { debuggers = { inline = true, eager = true, edges = {
    activeConfigs = { eager = true, edges = config_edges },
  }}}
end

-- Default Configs group (targets view) - used when debugger is not available
local CONFIGS_GROUP = { debuggers = { inline = true, eager = true, edges = {
  activeConfigs = { eager = true, edges = CONFIG_TARGETS },
}}}

-- Legacy: Sessions group (kept for backwards compatibility)
local SESSIONS_GROUP = { debuggers = { inline = true, edges = {
  activeConfigs = { eager = true, edges = CONFIG_ROOTS },
}}}

-- Legacy: Targets group (kept for backwards compatibility)
local TARGETS = { debuggers = { inline = true, eager = true, edges = {
  activeConfigs = { eager = true, edges = CONFIG_TARGETS },
}}}

local by_type = {
  Debugger = {
    -- Primary view: Configs (replaces Sessions/Targets)
    configsGroups = { eager = true, edges = CONFIGS_GROUP },
    breakpointsGroups = { eager = true, edges = BREAKPOINTS_GROUP },
    exceptionFiltersGroups = { eager = true, edges = EXCEPTION_FILTERS_GROUP },
  },
  -- Config entity edges - default to targets, can switch to roots
  Config = CONFIG_TARGETS,
  ConfigRoots = CONFIG_ROOTS,     -- Alternative view showing root hierarchy
  ConfigTargets = CONFIG_TARGETS, -- Explicit targets view
  Session = SESSION,
  -- Legacy groups (kept for backwards compatibility)
  Sessions = SESSIONS_GROUP,
  Targets = TARGETS,
  Thread = THREAD,
  Stack = STACK,
  Frame = FRAME,
  Scope = SCOPE,
  Variable = VARIABLE,
  Breakpoint = BREAKPOINT,
  Breakpoints = BREAKPOINTS_GROUP,
  Stdio = STDIO,
  Threads = THREADS,
  Output = OUTPUT,
  -- Console is Session with filtered allOutputs (used by console_buffer)
  Console = CONSOLE,
  -- Exception filters (global filters with per-session bindings)
  ExceptionFilter = EXCEPTION_FILTER,
  ExceptionFilters = EXCEPTION_FILTERS,
  ExceptionFiltersGroup = EXCEPTION_FILTERS_GROUP,
  ExceptionFilterBinding = EXCEPTION_FILTER_BINDING,
}

--- Get edges for a Config based on its viewMode
---@param config table Config entity
---@return table edges
local function get_config_edges(config)
  local view_mode = config.viewMode and config.viewMode:get() or "targets"
  if view_mode == "roots" then
    return CONFIG_ROOTS
  else
    return CONFIG_TARGETS
  end
end

--- Build a view query for an entity
---@param root_type string Entity type (e.g., "Session", "Frame")
---@param root_uri string Entity URI
---@param edge_type? string Optional edge type override (e.g., "Console" to use Console edges on Session)
---@param entity? table Optional entity for dynamic edge resolution
---@return table query View query configuration
local function build_query(root_type, root_uri, edge_type, entity)
  local query_edges
  
  -- For Config entities, check viewMode for dynamic edges
  if root_type == "Config" and entity and not edge_type then
    query_edges = get_config_edges(entity)
  elseif root_type == "Debugger" and entity and not edge_type then
    -- For Debugger, build Configs group edges dynamically based on viewMode
    local configs_group = build_configs_group_edges(entity)
    query_edges = {
      configsGroups = { eager = true, edges = configs_group },
      breakpointsGroups = { eager = true, edges = BREAKPOINTS_GROUP },
      exceptionFiltersGroups = { eager = true, edges = EXCEPTION_FILTERS_GROUP },
    }
  else
    query_edges = by_type[edge_type or root_type] or {}
  end
  
  -- Make root entity's direct child edges eager so they're visible even when root is hidden
  -- This enables any entity type to be used as tree root (Frame, Thread, Stack, etc.)
  -- Inline edges (e.g., debuggers) must also be eager at root level — they're the only
  -- way to reach children, and there's no visible node to click to expand them.
  local processed_edges = {}
  for name, config in pairs(query_edges) do
    if type(config) == "table" and not config.eager then
      -- Make non-eager edges eager when entity is root
      processed_edges[name] = vim.tbl_extend("force", config, { eager = true })
    else
      processed_edges[name] = config
    end
  end
  return {
    type = root_type,
    filters = { { field = "uri", op = "eq", value = root_uri } },
    edges = processed_edges,
  }
end

return {
  by_type = by_type,
  build_query = build_query,
  get_config_edges = get_config_edges,
  build_configs_group_edges = build_configs_group_edges,
  -- Export individual edge configs for custom use
  CONSOLE = CONSOLE,
  OUTPUT = OUTPUT,
  CONFIG_ROOTS = CONFIG_ROOTS,
  CONFIG_TARGETS = CONFIG_TARGETS,
}
