---@class Debugger : Class
---@field store EntityStore  -- Single source of truth for all entities
---@field breakpoints Collection<Breakpoint>
---@field sessions Collection<Session>
---@field exception_filters Collection<ExceptionFilter>
---@field exception_filter_bindings Collection<ExceptionFilterBinding>
local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")
local dap_client = require("dap-client")
local Breakpoint = require("neodap.sdk.debugger.breakpoint").Breakpoint
local ExceptionFilter = require("neodap.sdk.debugger.exception_filter").ExceptionFilter
local Context = require("neodap.sdk.context").Context

local M = {}

-- =============================================================================
-- DEBUGGER
-- =============================================================================

---@class Debugger : Class
local Debugger = neostate.Class("Debugger")

function Debugger:init()
  -- =============================================================================
  -- ENTITY STORE (Single source of truth for all entities)
  -- =============================================================================
  self.store = EntityStore.new("Debugger")
  self.store:set_parent(self)

  -- Register debugger as root entity
  self._type = "debugger"
  self.uri = "dap:"
  self.key = "dap"
  self.store:add(self, "debugger", {})

  -- =============================================================================
  -- ENTITY INDEXES
  -- =============================================================================

  -- Breakpoint indexes
  self.store:add_index("breakpoint:by_id", function(bp) return bp.id end)
  self.store:add_index("breakpoint:by_source_path", function(bp) return bp.source.path end)
  self.store:add_index("breakpoint:by_source_correlation_key", function(bp)
    return bp.source.correlation_key or bp.source.path or bp.source.name
  end)
  self.store:add_index("breakpoint:by_location", function(bp)
    local source_id = bp.source.correlation_key or bp.source.path or bp.source.name
    local key = source_id .. ":" .. bp.line
    if bp.column then
      key = key .. ":" .. bp.column
    end
    return key
  end)

  -- Session indexes
  self.store:add_index("session:by_id", function(session) return session.id end)
  self.store:add_index("session:by_parent_id", function(session)
    return session.parent and session.parent.id or nil
  end)
  self.store:add_index("session:by_root_id", function(session)
    return session:get_root_id()
  end)

  -- Binding indexes
  self.store:add_index("binding:by_session_id", function(binding)
    return binding.session.id
  end)
  self.store:add_index("binding:by_breakpoint_id", function(binding)
    return binding.breakpoint.id
  end)
  self.store:add_index("binding:by_dap_id", function(binding)
    return binding.dapId
  end)
  self.store:add_index("binding:by_location", function(binding)
    return binding.location
  end)
  self.store:add_index("binding:by_source_correlation_key", function(binding)
    local source = binding.breakpoint.source
    return source.correlation_key or source.path or source.name or "unknown"
  end)

  -- Thread indexes
  self.store:add_index("thread:by_id", function(thread) return thread.id end)
  self.store:add_index("thread:by_global_id", function(thread) return thread.global_id end)
  self.store:add_index("thread:by_session_id", function(thread) return thread.session.id end)
  self.store:add_index("thread:by_state", function(thread) return thread.state end)

  -- Frame indexes
  self.store:add_index("frame:by_id", function(frame) return frame.id end)
  self.store:add_index("frame:by_session_id", function(frame) return frame.stack.thread.session.id end)
  self.store:add_index("frame:by_thread_id", function(frame) return frame.stack.thread.global_id end)
  self.store:add_index("frame:by_stack_id", function(frame) return frame.stack.id end)
  self.store:add_index("frame:by_source_id", function(frame)
    return frame.source and frame.source.correlation_key or nil
  end)
  self.store:add_index("frame:by_index", function(frame) return frame.index end)
  self.store:add_index("frame:by_is_current", function(frame) return frame._is_current end)

  -- Stack indexes
  self.store:add_index("stack:by_id", function(stack) return stack.id end)
  self.store:add_index("stack:by_sequence", function(stack) return stack.sequence end)
  self.store:add_index("stack:by_index", function(stack) return stack.index end)
  self.store:add_index("stack:by_session_id", function(stack) return stack.thread.session.id end)
  self.store:add_index("stack:by_thread_id", function(stack) return stack.thread.global_id end)
  self.store:add_index("stack:by_is_current", function(stack) return stack._is_current end)

  -- Reactively manage stack indexes when new stacks are added
  self.store:on_added("stack", function(new_stack)
    local thread_id = new_stack.thread.global_id
    for stack in self.store:where("stack:by_thread_id", thread_id):iter() do
      if stack ~= new_stack then
        stack.index:set(stack.index:get() + 1)
      end
    end
  end)

  -- Variable indexes
  self.store:add_index("variable:by_session_id", function(variable)
    return variable.session and variable.session.id or nil
  end)
  self.store:add_index("variable:by_stack_id", function(variable)
    return variable.stack_id
  end)
  self.store:add_index("variable:by_name", function(variable)
    return variable.name
  end)
  self.store:add_index("variable:by_is_current", function(variable)
    return variable._is_current
  end)
  self.store:add_index("variable:by_evaluate_name", function(variable)
    return variable.evaluateName
  end)
  self.store:add_index("variable:by_uri", function(variable)
    return variable.uri
  end)
  self.store:add_index("variable:by_parent_uri", function(variable)
    return variable.parent and variable.parent.uri or nil
  end)

  -- Source indexes
  self.store:add_index("source:by_correlation_key", function(source)
    return source.correlation_key
  end)
  self.store:add_index("source:by_location_uri", function(source) return source:location_uri() end)

  -- Source binding indexes
  self.store:add_index("source_binding:by_session_id", function(binding)
    return binding.session.id
  end)
  self.store:add_index("source_binding:by_source_correlation_key", function(binding)
    return binding.source.correlation_key
  end)

  -- Output indexes
  self.store:add_index("output:by_session_id", function(output)
    return output.session.id
  end)
  self.store:add_index("output:by_index", function(output)
    return output.index
  end)
  self.store:add_index("output:by_category", function(output)
    return output.category
  end)

  -- Scope indexes
  self.store:add_index("scope:by_frame_id", function(scope)
    return scope.frame.uri
  end)
  self.store:add_index("scope:by_name", function(scope)
    return scope.name
  end)
  self.store:add_index("scope:by_is_current", function(scope)
    return scope._is_current
  end)

  -- Exception filter indexes
  self.store:add_index("exception_filter:by_id", function(filter)
    return filter.id
  end)
  self.store:add_index("exception_filter:by_adapter", function(filter)
    return filter.adapter_type
  end)

  -- Exception filter binding indexes
  self.store:add_index("exception_filter_binding:by_adapter", function(binding)
    return binding.adapter_type
  end)
  self.store:add_index("exception_filter_binding:by_session", function(binding)
    return binding.session_id
  end)
  self.store:add_index("exception_filter_binding:by_filter", function(binding)
    return binding.filter_id
  end)
  self.store:add_index("exception_filter_binding:by_verified", function(binding)
    return binding.verified
  end)

  -- =============================================================================
  -- ENTITY VIEWS
  -- =============================================================================
  -- Views provide reactive access to EntityStore entities

  self.breakpoints = self.store:view("breakpoint")
  self.sessions = self.store:view("session")
  self.bindings = self.store:view("binding")
  self.threads = self.store:view("thread")
  self.frames = self.store:view("frame")
  self.stacks = self.store:view("stack")
  self.variables = self.store:view("variable")
  self.sources = self.store:view("source")
  self.source_bindings = self.store:view("source_binding")
  self.outputs = self.store:view("output")
  self.scopes = self.store:view("scope")
  self.exception_filters = self.store:view("exception_filter")
  self.exception_filter_bindings = self.store:view("exception_filter_binding")

  -- Adapter registry (logical type -> physical config)
  self.adapters = {}

  -- Type aliases (VSCode type -> DAP adapter type)
  -- Maps launch.json types (like "node") to adapter types (like "pwa-node")
  self.type_aliases = {}

  -- Context management
  self._global_context = Context:new(nil)
  self._global_context:set_parent(self)
  self._buffer_contexts = {}  -- bufnr -> Context (stored in Lua, not buffer vars)
end

---Run a command in a terminal
---@param args dap.RunInTerminalRequestArguments
---@return number? processId
function Debugger:run_in_terminal(args)
  local cmd = args.args or {}
  local env = args.env or {}
  local cwd = args.cwd or vim.loop.cwd()

  -- Prepare options for termopen
  local opts = {
    cwd = cwd,
    env = env,
  }

  -- Create a new buffer for the terminal
  vim.cmd("vsplit")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)

  -- Run terminal
  local chan_id = vim.fn.termopen(cmd, opts)

  -- Get process ID
  local pid = vim.fn.jobpid(chan_id)

  -- Set buffer name if title provided
  if args.title then
    pcall(vim.api.nvim_buf_set_name, buf, args.title)
  end

  return pid
end

---Register an adapter configuration
---@param type_or_config string|AdapterConfig Logical type OR config with type field
---@param config? AdapterConfig Physical config (if first arg is string)
function Debugger:register_adapter(type_or_config, config)
  local adapter_type, adapter_config
  if type(type_or_config) == "string" then
    adapter_type = type_or_config
    adapter_config = config
  else
    adapter_type = type_or_config.type
    adapter_config = type_or_config
  end

  self.adapters[adapter_type] = adapter_config

  -- Register type aliases (e.g., "node" -> "pwa-node")
  if adapter_config.aliases then
    for _, alias in ipairs(adapter_config.aliases) do
      self.type_aliases[alias] = adapter_type
    end
  end

  -- Create ExceptionFilter objects from adapter config
  if adapter_config.exceptionFilters then
    for _, filter_config in ipairs(adapter_config.exceptionFilters) do
      local filter = ExceptionFilter:new(self, adapter_type, filter_config)
      -- Add to EntityStore (global exception filter, no edges)
      self.store:add(filter, "exception_filter", {})
    end
  end
end

---Resolve a type to its adapter type (follows aliases)
---@param type_name string
---@return string resolved_type
function Debugger:resolve_type(type_name)
  return self.type_aliases[type_name] or type_name
end

---Create a new global breakpoint
---@param source { path: string }
---@param line number
---@param opts? { condition?: string, logMessage?: string, hitCondition?: string }
---@return Breakpoint
function Debugger:add_breakpoint(source, line, opts)
  local breakpoint = Breakpoint:new(self, source, line, opts)

  -- Add to EntityStore (global breakpoint, no edges)
  self.store:add(breakpoint, "breakpoint", {})

  -- Create bindings in all existing sessions for this file
  for session in self.sessions:iter() do
    session:_try_bind_breakpoint(breakpoint)
  end

  return breakpoint
end

---Remove a global breakpoint (unbinds from all sessions)
---@param breakpoint Breakpoint
function Debugger:remove_breakpoint(breakpoint)
  self.store:dispose_entity(breakpoint.uri)
end

---Create a new debug session
---@param logical_type string The adapter type (e.g., "pwa-node", "python")
---@param parent_session? Session Parent session (for child sessions, reuses adapter)
---@return Session
function Debugger:create_session(logical_type, parent_session)
  -- Get adapter (reuse from parent or create new)
  local adapter
  if parent_session then
    adapter = parent_session.adapter
  else
    local adapter_config = self.adapters[logical_type]
    if not adapter_config then
      error("No adapter registered for type: " .. logical_type)
    end
    local dap_client = require("dap-client")
    adapter = dap_client.create_adapter(adapter_config)
  end

  local Session = require("neodap.sdk.session").Session
  local session = Session:new(self, logical_type, adapter, parent_session)

  -- Add to EntityStore
  local edges = {}
  if parent_session then
    -- Child session: add "parent" edge to parent session
    table.insert(edges, { type = "parent", to = parent_session.uri })
  else
    -- Root session: add "parent" edge to debugger
    table.insert(edges, { type = "parent", to = self.uri })
  end
  self.store:add(session, "session", edges)

  -- Add children edge from parent to child (for follow traversal)
  if parent_session then
    self.store:add_edge(parent_session.uri, "children", session.uri)
  else
    -- Root session: add children edge from debugger
    self.store:add_edge(self.uri, "children", session.uri)
  end

  return session
end

---Start a debug session with a VSCode-style launch configuration
---This is the recommended high-level API for starting debugging sessions
---Must be called from within a coroutine (e.g., using neostate.void())
---@param config table  -- Launch configuration (like VSCode's launch.json)
---@return Session
---
---Example:
---```lua
---neostate.void(function()
---  local session = debugger:start({
---    type = "python",
---    request = "launch",
---    name = "Debug Python Script",
---    program = "${file}",
---    console = "internalConsole",
---  })
---  -- Session is now initialized and ready
---end)()
---```
function Debugger:start(config)
  -- Validate required fields
  if not config.type then
    error("Debug configuration must have a 'type' field")
  end
  if not config.request then
    error("Debug configuration must have a 'request' field (launch or attach)")
  end

  -- Resolve type alias (e.g., "node" -> "pwa-node")
  local resolved_type = self:resolve_type(config.type)

  -- Create session with resolved type
  local session = self:create_session(resolved_type)

  -- Merge current environment with config's env (config takes precedence)
  -- Also ensure nix-profile is in PATH (MCP may not inherit full shell environment)
  local base_env = vim.fn.environ()
  local home = os.getenv("HOME") or ""
  local nix_profile = home .. "/.nix-profile/bin"
  if base_env.PATH and not base_env.PATH:find(nix_profile, 1, true) then
    base_env.PATH = nix_profile .. ":" .. base_env.PATH
  end

  -- Load envFile if specified (VSCode-style .env file support)
  local env_file_vars = {}
  if config.envFile then
    local env_path = config.envFile
    vim.notify("[DAP] Loading envFile: " .. env_path, vim.log.levels.INFO)
    local file = io.open(env_path, "r")
    if file then
      local count = 0
      for line in file:lines() do
        -- Skip empty lines and comments
        if line ~= "" and not line:match("^%s*#") then
          -- Parse KEY=VALUE (handles quoted values)
          local key, value = line:match("^([%w_]+)%s*=%s*(.*)$")
          if key and value then
            -- Remove surrounding quotes if present
            value = value:gsub("^['\"](.*)['\"']$", "%1")
            env_file_vars[key] = value
            count = count + 1
          end
        end
      end
      file:close()
      vim.notify("[DAP] Loaded " .. count .. " env vars from envFile", vim.log.levels.INFO)
    else
      vim.notify("Could not read envFile: " .. env_path, vim.log.levels.WARN)
    end
  end

  -- Merge order: envFile < inline env (later values override)
  -- Note: Don't include base_env here - js-debug merges with its own process env
  -- We only need to pass the additional vars we want to set
  local merged_env = vim.tbl_extend("force", env_file_vars, config.env or {})

  -- Resolve runtimeExecutable for NixOS compatibility
  -- js-debug doesn't use env.PATH for executable lookup, so we need to help it
  local runtime_exec = config.runtimeExecutable
  local runtime_args = config.runtimeArgs
  if runtime_exec and not runtime_exec:match("^/") then
    local nix_path = nix_profile .. "/" .. runtime_exec
    if vim.fn.executable(nix_path) == 1 then
      -- Found in nix-profile, use node to run the script
      -- This avoids issues with symlink resolution in js-debug
      runtime_exec = "node"
      runtime_args = vim.list_extend({ nix_path }, runtime_args or {})
    end
  end

  -- Create a modified config with resolved type and merged environment
  -- Only include env if it has content (debugpy doesn't like empty env dict)
  local overrides = {
    type = resolved_type,
    runtimeExecutable = runtime_exec,
    runtimeArgs = runtime_args,
  }
  if next(merged_env) then
    overrides.env = merged_env
  end
  local dap_config = vim.tbl_extend("force", config, overrides)

  -- Set session name from config
  session.name:set(config.name)

  -- Initialize with defaults (awaits in coroutine context)
  local err = session:initialize()
  if err then
    error("Failed to initialize session: " .. err)
  end

  -- Launch or attach based on request type
  if config.request == "launch" then
    session:launch(dap_config)
  elseif config.request == "attach" then
    err = session:attach(dap_config)
    if err then
      error("Failed to attach session: " .. err)
    end
  else
    error("Invalid request type: " .. config.request .. " (must be 'launch' or 'attach')")
  end

  return session
end

-- =============================================================================
-- BREAKPOINT LOCATIONS
-- =============================================================================

---Get possible breakpoint locations, aggregated across all active sessions
---Deduplicates by position
---@param source { path: string }|dap.Source  -- Source to query
---@param pos integer|integer[]                -- Start position (0-indexed line, or {line, col})
---@param end_pos? integer[]                   -- Optional end position {line, col} for range query
---@return string? error, { pos: integer[], end_pos?: integer[] }[]? locations
function Debugger:breakpointLocations(source, pos, end_pos)
  local all_locations = {}
  local seen = {}  -- Dedup key: "line:col:endLine:endCol"
  local any_success = false
  local last_error = nil

  for session in self.sessions:iter() do
    if session.state:get() ~= "terminated" and session:supportsBreakpointLocations() then
      local err, locations = session:breakpointLocations(source, pos, end_pos)
      if err then
        last_error = err
      elseif locations then
        any_success = true
        for _, loc in ipairs(locations) do
          local key = string.format("%d:%d:%s:%s",
            loc.pos[1], loc.pos[2],
            loc.end_pos and loc.end_pos[1] or "",
            loc.end_pos and loc.end_pos[2] or "")
          if not seen[key] then
            seen[key] = true
            table.insert(all_locations, loc)
          end
        end
      end
    end
  end

  if not any_success and last_error then
    return last_error, nil
  end

  -- Sort by line, then column
  table.sort(all_locations, function(a, b)
    if a.pos[1] ~= b.pos[1] then return a.pos[1] < b.pos[1] end
    return a.pos[2] < b.pos[2]
  end)

  return nil, all_locations
end

-- =============================================================================
-- LIFECYCLE HOOKS
-- =============================================================================

---Register callback for debug sessions (existing + future)
---@param fn function  -- Called with (session)
---@return function unsubscribe
function Debugger:onSession(fn)
  return self.sessions:each(fn)
end

---Register callback for breakpoints (existing + future)
---@param fn function  -- Called with (breakpoint)
---@return function unsubscribe
function Debugger:onBreakpoint(fn)
  return self.breakpoints:each(fn)
end

---Set exception filter enabled state
---@param adapter_type string  -- "python", "pwa-node", etc.
---@param filter_id string     -- "raised", "uncaught", etc.
---@param enabled boolean
function Debugger:set_exception_filter(adapter_type, filter_id, enabled)
  local id = adapter_type .. ":" .. filter_id
  local filter = self.exception_filters:get_one("by_id", id)
  if filter then
    filter.enabled:set(enabled)
  end
end

---Get enabled exception filter IDs for an adapter type
---@param adapter_type string
---@return string[]
function Debugger:enabled_exception_filters(adapter_type)
  local filters = {}
  for filter in self.exception_filters:where("by_adapter", adapter_type):iter() do
    if filter.enabled:get() then
      table.insert(filters, filter.filter_id)
    end
  end
  return filters
end

---Register callback for exception filters (existing + future)
---@param fn function  -- Called with (filter: ExceptionFilter)
---@return function unsubscribe
function Debugger:onExceptionFilter(fn)
  return self.exception_filters:each(fn)
end

---Register callback for frames (existing + future)
---@param fn function  -- Called with (frame: Frame)
---@return function unsubscribe
function Debugger:onFrame(fn)
  return self.frames:each(fn)
end

---Register callback for threads (existing + future)
---@param fn function  -- Called with (thread: Thread)
---@return function unsubscribe
function Debugger:onThread(fn)
  return self.threads:each(fn)
end

---Register callback for stacks (existing + future)
---@param fn function  -- Called with (stack: Stack)
---@return function unsubscribe
function Debugger:onStack(fn)
  return self.stacks:each(fn)
end

-- =============================================================================
-- URI RESOLUTION
-- =============================================================================

local uri = require("neodap.sdk.uri")

---Resolve a URI to a reactive collection of entities
---Supports index accessors like stack[0]/frame[0] for relative references
---Supports contextual URIs like @stack/frame which expand using current context
---@param uri_string string  -- URI like "dap:session:xxx/thread:1/stack[0]/frame[0]" or "@stack/frame"
---@return table? collection  -- Reactive collection that updates as state changes
---@return string? error
function Debugger:resolve(uri_string)
  -- Expand contextual URIs if needed
  if uri.is_contextual(uri_string) then
    local expanded = self:expand_contextual_uri(uri_string)
    if not expanded then
      return nil, "Failed to expand contextual URI (no context set)"
    end
    uri_string = expanded
  end
  return uri.resolve(self, uri_string)
end

---Resolve a URI and return the first matching entity
---Optionally drill down to a target entity type
---Supports contextual URIs like @frame which expand using current context
---@param uri_string string
---@param target_type? "session"|"thread"|"stack"|"frame"
---@return table? entity
---@return string? error
function Debugger:resolve_one(uri_string, target_type)
  -- Expand contextual URIs if needed
  if uri.is_contextual(uri_string) then
    local expanded = self:expand_contextual_uri(uri_string)
    if not expanded then
      return nil, "Failed to expand contextual URI (no context set)"
    end
    uri_string = expanded
  end
  local entity, err = uri.resolve_one(self, uri_string)
  if not entity or not target_type then
    return entity, err
  end
  return self:drill_down(entity, target_type)
end

---Drill down from entity to target type
---Follows: session -> thread -> stack -> frame
---@param entity table
---@param target_type "session"|"thread"|"stack"|"frame"
---@return table?
function Debugger:drill_down(entity, target_type)
  if not entity then return nil end

  -- Detect current entity type by structure
  -- Use unique properties: Frame has .line, Stack has .sequence, Thread has .session but no .sequence
  local current_type
  if entity.line then
    current_type = "frame"
  elseif entity.sequence then
    current_type = "stack"
  elseif entity.session then
    current_type = "thread"
  else
    current_type = "session"
  end

  -- Already at target type
  if current_type == target_type then
    return entity
  end

  -- Drill down hierarchy
  if target_type == "thread" then
    if current_type == "session" then
      return entity:threads():iter()()  -- First thread
    end
  elseif target_type == "stack" then
    local thread = self:drill_down(entity, "thread")
    return thread and thread:stack()
  elseif target_type == "frame" then
    local stack = self:drill_down(entity, "stack")
    return stack and stack:top()
  end

  return nil
end

-- =============================================================================
-- CONTEXT MANAGEMENT
-- =============================================================================

---Get a context for a buffer or the global context
---If bufnr is nil or 0, returns the global context
---If bufnr is provided, returns (or creates) a buffer-specific context that inherits from global
---Buffer contexts are stored on the buffer itself and auto-cleanup when buffer is wiped
---@param bufnr? number Buffer number (nil or 0 for global context)
---@return Context
function Debugger:context(bufnr)
  -- Global context
  if not bufnr or bufnr == 0 then
    return self._global_context
  end

  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return self._global_context
  end

  -- Get or create buffer context (stored in Lua table to preserve metatables)
  local ctx = self._buffer_contexts[bufnr]
  if not ctx then
    ctx = Context:new(self._global_context)
    ctx:set_parent(self)
    self._buffer_contexts[bufnr] = ctx
  end

  return ctx
end

---Expand a contextual URI pattern to a concrete URI using current context
---@param pattern string URI pattern with @ markers
---@param ctx? Context Context to use (defaults to current buffer's context)
---@return string? expanded_uri The expanded URI, or nil if expansion failed
function Debugger:expand_contextual_uri(pattern, ctx)
  -- Default to current buffer's context (which falls back to global if not pinned)
  ctx = ctx or self:context(vim.api.nvim_get_current_buf())

  local frame_uri = ctx.frame_uri:get()
  if not frame_uri then return nil end

  local context_entity = self:resolve_one(frame_uri)
  if not context_entity then return nil end

  local context_map = uri.build_context_map(context_entity)
  return uri.expand_contextual(pattern, context_map)
end

---Resolve a contextual URI pattern that follows context changes
---Patterns like "dap:@session", "dap:@thread", "dap:@frame" resolve based on context
---Returns a computed Signal that updates when context changes
---@param pattern string URI pattern with @ markers (e.g., "dap:@frame", "dap:@session/thread[0]")
---@param ctx? Context Context to use (defaults to global)
---@return Signal Computed signal containing the resolved entity or collection
function Debugger:resolve_contextual(pattern, ctx)
  ctx = ctx or self._global_context

  -- Normalize pattern first (e.g., @frame -> dap:@frame)
  local normalized = uri.normalize(pattern)

  -- Check if this is a simple @entity pattern (returns single entity)
  -- Matches @frame, @session, and relative patterns like @frame+1, @frame-1
  local is_single_entity = normalized:match("^dap:@[%w%-]+[%+%-]?%d*$") ~= nil

  return neostate.computed(function()
    local frame_uri = ctx.frame_uri:get()
    if not frame_uri then return nil end

    -- Resolve the context's frame_uri to get the entity
    local context_entity = self:resolve_one(frame_uri)
    if not context_entity then return nil end

    -- Build context map from the resolved entity
    local context_map = uri.build_context_map(context_entity)

    -- Expand the pattern with actual IDs
    local concrete_uri = uri.expand_contextual(pattern, context_map)
    if not concrete_uri then return nil end

    -- Resolve the concrete URI
    if is_single_entity then
      return self:resolve_one(concrete_uri)
    else
      return self:resolve(concrete_uri)
    end
  end, { ctx.frame_uri }, "contextual:" .. pattern)
end

---Resolve a contextual URI and return a single entity (convenience method)
---@param pattern string URI pattern with @ markers
---@param target_type? "session"|"thread"|"stack"|"frame" Optional target type to drill down to
---@param ctx? Context Context to use (defaults to global)
---@return Signal Computed signal containing the resolved entity
function Debugger:resolve_contextual_one(pattern, target_type, ctx)
  ctx = ctx or self._global_context

  return neostate.computed(function()
    local frame_uri = ctx.frame_uri:get()
    if not frame_uri then return nil end

    local context_entity = self:resolve_one(frame_uri)
    if not context_entity then return nil end

    local context_map = uri.build_context_map(context_entity)
    local concrete_uri = uri.expand_contextual(pattern, context_map)
    if not concrete_uri then return nil end

    return self:resolve_one(concrete_uri, target_type)
  end, { ctx.frame_uri }, "contextual_one:" .. pattern)
end

-- =============================================================================
-- ENTITY STORE HELPERS
-- =============================================================================

---Get an entity from the store by URI
---@param uri string
---@return table?
function Debugger:get_entity(uri)
  return self.store:get(uri)
end

---Get children of an entity by edge type
---@param parent_uri string Parent entity URI
---@param edge_type string Edge type (e.g., "thread", "stack", "frame")
---@return table[] Array of child entities
function Debugger:get_children(parent_uri, edge_type)
  local edges = self.store:edges_to(parent_uri, edge_type)
  local children = {}
  for _, edge in ipairs(edges) do
    local entity = self.store:get(edge.from)
    if entity then
      table.insert(children, entity)
    end
  end
  return children
end

---Get parent of an entity by edge type
---@param child_uri string Child entity URI
---@param edge_type string Edge type (e.g., "thread", "stack", "frame")
---@return table? Parent entity
function Debugger:get_parent(child_uri, edge_type)
  local edges = self.store:edges_from(child_uri, edge_type)
  if #edges > 0 then
    return self.store:get(edges[1].to)
  end
  return nil
end

---Find ancestor of a specific entity type
---@param uri string Starting entity URI
---@param target_type string Entity type to find (e.g., "session", "thread")
---@return table? Ancestor entity
function Debugger:find_ancestor(uri, target_type)
  local entity = self.store:get(uri)
  if not entity then return nil end

  -- Edge type hierarchy for traversal
  local edge_hierarchy = {
    variable = "variable",  -- Variable → Scope or Variable
    scope = "scope",        -- Scope → Frame
    frame = "frame",        -- Frame → Stack
    stack = "stack",        -- Stack → Thread
    thread = "thread",      -- Thread → Session
    session = "parent",     -- Session → Session (child sessions)
  }

  while entity do
    if entity._type == target_type then
      return entity
    end

    local edge_type = edge_hierarchy[entity._type]
    if not edge_type then break end

    local edges = self.store:edges_from(entity.uri, edge_type)
    if #edges == 0 then break end

    entity = self.store:get(edges[1].to)
  end

  return nil
end

---Subscribe to entities of a specific type being added
---@param entity_type string Entity type (e.g., "session", "thread")
---@param callback function Called with (entity) when entity is added
---@return function unsubscribe
function Debugger:on_entity_added(entity_type, callback)
  return self.store:on_added(entity_type, callback)
end

---Subscribe to entities of a specific type being removed
---@param entity_type string Entity type (e.g., "session", "thread")
---@param callback function Called with (entity) when entity is removed
---@return function unsubscribe
function Debugger:on_entity_removed(entity_type, callback)
  return self.store:on_removed(entity_type, callback)
end

-- =============================================================================
-- VIEW API
-- =============================================================================

---Create a View over entities of a specific type
---Views are lightweight query definitions with shared caching and reactivity.
---
---Example:
---  local stopped = debugger:view("thread"):where("by_state", "stopped")
---  stopped:each(function(thread) print(thread.name) end)
---  stopped:dispose()
---
---@param entity_type string Entity type (e.g., "session", "thread", "breakpoint")
---@return View
function Debugger:view(entity_type)
  return self.store:view(entity_type)
end

M.Debugger = Debugger

return Debugger -- Export the class directly
