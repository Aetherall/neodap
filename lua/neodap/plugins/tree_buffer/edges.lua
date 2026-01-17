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
local SCOPE = { variables = { edges = VARIABLE, on_expand = fetch_variables } }
local FRAME = { scopes = { edges = SCOPE, on_expand = fetch_scopes } }
local STACK = { frames = { edges = FRAME, on_expand = fetch_frames } }
local THREAD = { stacks = { edges = STACK, on_expand = fetch_stacks } }

local OUTPUT = {}
-- Traverse session (inlined) -> outputs: when user expands Stdio, sessions expands,
-- Session enters view (hidden), then outputs eagerly expands showing children under Stdio
local STDIO = { sessions = { inline = true, edges = { outputs = { eager = true, edges = OUTPUT } }}}

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

local CHILD_SESSION = {
  children = { eager = true, recursive = true },
  threadGroups = { eager = true, edges = THREADS },
  stdios = { eager = true, edges = STDIO },
}

-- Sessions uses inline hop to show root sessions via debugger.rootSessions
-- Not eager at top level - users manually expand Sessions group
local SESSIONS_GROUP = { debuggers = { inline = true, edges = {
  rootSessions = { eager = true, edges = {
    children = { eager = true, edges = CHILD_SESSION },
    threadGroups = { eager = true, edges = THREADS },
    stdios = { eager = true, edges = STDIO },
  }}
}}}

-- Targets uses inline hop to show leaf sessions via debugger.leafSessions
-- eager = true on debuggers ensures sessions show without manual expansion
local TARGETS = { debuggers = { inline = true, eager = true, edges = {
  leafSessions = { eager = true, edges = {
    threadGroups = { eager = true, edges = THREADS },
    stdios = { eager = true, edges = STDIO },
  }}
}}}

local by_type = {
  Debugger = {
    sessionsGroups = { eager = true, edges = SESSIONS_GROUP },
    targets = { eager = true, edges = TARGETS },
    breakpointsGroups = { eager = true, edges = BREAKPOINTS_GROUP },
  },
  Session = SESSION,
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
}

local function build_query(root_type, root_uri)
  return {
    type = root_type,
    filters = { { field = "uri", op = "eq", value = root_uri } },
    edges = by_type[root_type] or {},
  }
end

return {
  by_type = by_type,
  build_query = build_query,
}
