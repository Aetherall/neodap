-- Plugin: Tree exploration buffer for dap-tree: URIs
-- Provides an interactive tree view of debug entities
--
-- URI format:
--   dap-tree:@session                    - Tree rooted at context session
--   dap-tree:@frame                      - Tree rooted at context frame
--   dap-tree:@variable                   - Tree rooted at context variable
--   dap-tree:session:<id>                - Tree rooted at specific session
--   dap-tree:variable:<uri>              - Tree rooted at specific variable
--   dap-tree:<uri>?collapsed             - Start with nodes collapsed

local neostate = require("neostate")
local TreeWindow = require("neostate.tree_window")
local ExplorationLens = require("neodap.lib.exploration_lens")

---@class ExtmarkSpec
---@field id? string Optional identifier for lookup (e.g., cursor anchoring)
---@field opts table Options passed directly to nvim_buf_set_extmark

---@class RenderSegment
---@field [1] string Text content
---@field [2]? string Highlight group (optional)
---@field [3]? ExtmarkSpec[] Extmarks to create at this segment's position (optional)

---@class RenderResult
---@field line RenderSegment[] Array of {text, hl_group?} tuples
---@field deps? table[] Signals that trigger re-render when changed

---@class RenderContext
---@field depth number Indentation depth
---@field has_children boolean Whether node has children
---@field is_collapsed boolean Whether node is collapsed
---@field is_focused boolean Whether node is focused
---@field is_last boolean Whether this is the last sibling at its depth
---@field guides boolean[] Array of booleans per depth: true = has more siblings (draw │), false = no more (draw space)
---@field icons table<string, string> Icon configuration
---@field indent number Indent size per level

---@alias EntityRenderer fun(entity: table, ctx: RenderContext): RenderResult

---@class KeybindContext
---@field entity table? The focused entity (via getFocus()), nil if nothing focused
---@field window TreeWindow The tree window instance
---@field debugger Debugger The debugger instance

---@alias KeybindHandler fun(ctx: KeybindContext): boolean? Return true to prevent default behavior

---@alias TypeHandler fun(node: table, ctx: KeybindContext): boolean? Handler receives wrapper (entity + _virtual) and context

---@class KeybindDispatch
---@field [string] TypeHandler Type-specific handlers (e.g., frame, stack, variable)
---@field default? TypeHandler Fallback handler when no type matches

---@class TreeBufferConfig
---@field indent? number Indentation per level (default: 2)
---@field icons? table<string, string> Icons for entity types
---@field highlights? table<string, string> Highlight groups per entity type
---@field renderers? table<string, EntityRenderer> Custom renderers per entity type
---@field above? number Viewport items above focus (default: 50)
---@field below? number Viewport items below focus (default: 50)
---@field keybinds? table<string, KeybindHandler|KeybindDispatch> Custom keybind handlers (function or type dispatch table)

local default_config = {
  indent = 2,
  icons = {
    -- Entity type icons (prefix before name)
    debugger = "",
    session = "",
    thread = "",
    stack = "",
    frame = "",
    scope = "",
    variable = "",
    source = "",
    breakpoint = "",
    output = "",
    eval = "",
    binding = "",
    group = "",
    -- Tree structure icons
    collapsed = "▶",
    expanded = "▼",
    leaf = " ",
    -- Gutter characters (set all to "" to disable gutters)
    gutter_branch = "├─",    -- Has siblings below
    gutter_last = "╰─",      -- Last child (no siblings below)
    gutter_vertical = "│ ",  -- Vertical continuation
    gutter_blank = "  ",     -- Blank (ancestor was last child)
  },
  -- Highlight group definitions (can override defaults)
  -- Each key is a highlight group name, value is vim.api.nvim_set_hl opts
  highlight_defs = {
    -- Entity types
    DapTreeDebugger = { link = "Title" },
    DapTreeSession = { link = "Type" },
    DapTreeThread = { link = "Function" },
    DapTreeStack = { link = "Identifier" },
    DapTreeFrame = { link = "String" },
    DapTreeScope = { link = "Keyword" },
    DapTreeVariable = { link = "Identifier" },
    DapTreeSource = { link = "Directory" },
    DapTreeBreakpoint = { link = "Error" },
    DapTreeBinding = { link = "WarningMsg" },
    DapTreeOutput = { link = "Comment" },
    DapTreeExpression = { link = "Identifier" },
    DapTreeGroup = { link = "Directory" },
    DapTreeCount = { link = "Number" },
    -- State highlights
    DapTreeState = { link = "Comment" },
    DapTreeStopped = { link = "WarningMsg" },
    DapTreeRunning = { link = "DiffAdd" },
    DapTreeCurrent = { link = "Special" },
    -- Value highlights
    DapTreeType = { link = "Type" },
    DapTreeValue = { link = "String" },
    DapTreeCategory = { link = "Label" },
    DapTreeLineNum = { link = "LineNr" },
    DapTreePunctuation = { link = "Delimiter" },
    -- UI highlights
    DapTreeFocused = { link = "CursorLine" },
    DapTreeIcon = { link = "Special" },
    DapTreeDepth = { link = "Comment" },
  },
  above = 50,
  below = 50,
  keybinds = {}, -- User-defined keybind handlers
}

---@param debugger Debugger
---@param config? TreeBufferConfig
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local group = vim.api.nvim_create_augroup("neodap-tree-buffer", { clear = true })
  local buffer_state = {} -- bufnr -> { window: TreeWindow, subscriptions: function[] }

  -- Define highlight groups from config (user can override defaults)
  local function setup_highlights()
    for name, opts in pairs(config.highlight_defs) do
      -- Always set highlights from config (allows user customization)
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  -- =============================================================================
  -- Tree Structure Management (virtual groups via tree_parent edges)
  -- =============================================================================

  -- Track plugin-managed subscriptions for cleanup
  local tree_subscriptions = {}

  -- Group definitions: which entity types get grouped under virtual nodes
  local group_definitions = {
    -- { parent_type, group_name, child_types, filter? }
    { parent = "session", name = "Threads", key = "~threads", child_types = { "thread" } },
    {
      parent = "session",
      name = "Outputs",
      key = "~outputs",
      child_types = { "output" },
      -- Filter out telemetry outputs
      filter = function(entity)
        return entity.category ~= "telemetry"
      end,
    },
    { parent = "session", name = "Evaluations", key = "~evaluations", child_types = { "evaluate_result" } },
    { parent = "session", name = "Breakpoints", key = "~bindings", child_types = { "binding" } },
    {
      parent = "session",
      name = "REPL",
      key = "~repl",
      child_types = { "output", "evaluate_result" },
      filter = function(entity)
        -- Include stdout, stderr, console outputs (exclude telemetry)
        if entity._type == "output" then
          local cat = entity.category
          return cat == "stdout" or cat == "stderr" or cat == "console"
        end
        -- Include all evaluations
        return true
      end,
      prepend = true, -- Newest first (auto-scroll effect)
    },
  }

  ---Create a virtual group entity (lazy - only when first child is added)
  ---@param parent_uri string Parent entity URI
  ---@param group_def table Group definition
  ---@return table group The created group entity
  local function create_group(parent_uri, group_def)
    local group_uri = parent_uri .. "/" .. group_def.key
    local group_entity = {
      uri = group_uri,
      key = group_def.key,
      name = group_def.name,
      _type = "group",
      count = neostate.Signal(0),
    }

    -- Add to store
    debugger.store:add(group_entity, "group", {})
    -- Add tree_parent edge to parent
    debugger.store:add_edge(group_uri, "tree_parent", parent_uri)

    return group_entity
  end

  ---Setup tree structure when a session is added
  ---@param session table Session entity
  local function setup_session_tree(session)
    -- Groups are created lazily when first child is added
    local groups = {} -- key -> group entity (nil until created)
    local group_counts = {} -- key -> count

    -- Add tree_parent edge: child sessions → parent session, root sessions → debugger
    local tree_parent = session.parent and session.parent.uri or debugger.uri
    debugger.store:add_edge(session.uri, "tree_parent", tree_parent)

    -- Subscribe to child entity additions and add tree_parent to appropriate group
    for _, def in ipairs(group_definitions) do
      if def.parent == "session" then
        group_counts[def.key] = 0

        for _, child_type in ipairs(def.child_types) do
          local unsub = debugger.store:on_added(child_type, function(entity)
            -- Check if this entity belongs to this session
            local entity_session_id = entity.uri:match("^dap:session:([^/]+)")
            if entity_session_id ~= session.id then return end

            -- Apply filter if defined
            if def.filter and not def.filter(entity) then return end

            -- Create group lazily on first child
            if not groups[def.key] then
              groups[def.key] = create_group(session.uri, def)
            end
            local group = groups[def.key]

            -- Add tree_parent edge to group
            if def.prepend then
              debugger.store:prepend_edge(entity.uri, "tree_parent", group.uri)
            else
              debugger.store:add_edge(entity.uri, "tree_parent", group.uri)
            end
            -- Update count
            group_counts[def.key] = group_counts[def.key] + 1
            group.count:set(group_counts[def.key])
          end)
          table.insert(tree_subscriptions, unsub)

          local unsub_remove = debugger.store:on_removed(child_type, function(entity)
            local entity_session_id = entity.uri:match("^dap:session:([^/]+)")
            if entity_session_id ~= session.id then return end

            -- Apply filter if defined
            if def.filter and not def.filter(entity) then return end

            local group = groups[def.key]
            if group then
              group_counts[def.key] = math.max(0, group_counts[def.key] - 1)
              group.count:set(group_counts[def.key])
              -- TODO: Could dispose group when count reaches 0
            end
          end)
          table.insert(tree_subscriptions, unsub_remove)
        end
      end
    end
  end

  -- Subscribe to session additions
  local unsub_session = debugger.store:on_added("session", function(session)
    setup_session_tree(session)
  end)
  table.insert(tree_subscriptions, unsub_session)

  -- Handle entities that don't belong to groups (stack -> thread, frame -> stack, etc.)
  -- These mirror their parent edge as tree_parent
  -- Use on_edge_added to catch the edge after it's created (avoids timing issues)
  local passthrough_types = { stack = true, frame = true, scope = true, variable = true }

  -- Mirror "parent" edges as tree_parent
  -- Stacks use prepend_edge to maintain newest-first order (latest stack at top)
  local unsub_parent_edge = debugger.store:on_edge_added("parent", function(from_uri, to_uri)
    local entity = debugger.store:get(from_uri)
    if entity and passthrough_types[entity._type] then
      if entity._type == "stack" then
        -- Stacks: prepend so newest appears first (above older stacks)
        debugger.store:prepend_edge(from_uri, "tree_parent", to_uri)
      else
        -- Other types: append in natural order
        debugger.store:add_edge(from_uri, "tree_parent", to_uri)
      end
    end
  end)
  table.insert(tree_subscriptions, unsub_parent_edge)

  -- Mirror "scope" edges as tree_parent (scopes use "scope" edge type to frames)
  local unsub_scope_edge = debugger.store:on_edge_added("scope", function(from_uri, to_uri)
    debugger.store:add_edge(from_uri, "tree_parent", to_uri)
  end)
  table.insert(tree_subscriptions, unsub_scope_edge)

  -- Mirror "variable" edges as tree_parent (variables use "variable" edge type to parent scope/variable)
  local unsub_variable_edge = debugger.store:on_edge_added("variable", function(from_uri, to_uri)
    debugger.store:add_edge(from_uri, "tree_parent", to_uri)
  end)
  table.insert(tree_subscriptions, unsub_variable_edge)

  ---Parse dap-tree: URI into root pattern and options
  ---@param uri string
  ---@return string root_pattern, table options
  local function parse_tree_uri(uri)
    -- Remove dap-tree: prefix
    local path = uri:gsub("^dap%-tree:", "")

    -- Split path and query string
    -- Use * instead of + to allow empty root pattern (e.g., dap-tree:?focus=@frame)
    local root_pattern, query = path:match("^([^?]*)%??(.*)")
    root_pattern = root_pattern or path

    -- Parse query options
    local options = {}
    if query and query ~= "" then
      for param in query:gmatch("[^&]+") do
        local key, value = param:match("([^=]+)=?(.*)")
        if key then
          options[key] = value ~= "" and value or true
        end
      end
    end

    return root_pattern, options
  end

  -- Contextual pattern types
  local contextual_types = {
    ["@session"] = "session",
    ["@frame"] = "frame",
    ["@thread"] = "thread",
    ["@variable"] = "variable",
  }

  ---Resolve root entity URI from pattern
  ---@param pattern string
  ---@return string? uri, table? entity, Signal? signal Signal that emits new entity when root should change
  local function resolve_root(pattern)
    -- Handle empty pattern → debugger root
    if pattern == "" then
      return debugger.uri, debugger, nil
    end

    -- Split pattern into segments for path navigation (e.g., "@session/$repl")
    local segments = {}
    for segment in pattern:gmatch("[^/]+") do
      table.insert(segments, segment)
    end
    local root_segment = segments[1] or pattern

    -- Handle contextual patterns (@session, @frame, @thread, @variable)
    local target_type = contextual_types[root_segment]
    local root_entity, context_signal
    if target_type then
      -- Use global context for tree buffers - they should follow global debug state
      -- (Using alternate buffer is unreliable during BufReadCmd)
      context_signal = debugger:resolve_contextual_one(root_segment, target_type, nil)
      root_entity = context_signal:get()

      -- Fallback for @session only: first available session
      if not root_entity and root_segment == "@session" then
        for s in debugger.sessions:iter() do
          root_entity = s
          break
        end
      end
    else
      -- Handle explicit URI patterns (dap:session:xxx, etc.)
      local full_uri = "dap:" .. root_segment
      root_entity = debugger:resolve_one(full_uri) or debugger.store:get(full_uri)
    end

    if not root_entity then
      return nil, nil, nil
    end

    -- Navigate down path segments (e.g., "~repl" in "@session/~repl")
    local current_entity = root_entity
    for i = 2, #segments do
      local target_key = segments[i]
      local found = false

      -- Search children via tree_parent edges (inbound edges to current entity)
      local edges = debugger.store:edges_to(current_entity.uri, "tree_parent")
      for _, edge in ipairs(edges) do
        local child = debugger.store:get(edge.from)
        if child and child.key == target_key then
          current_entity = child
          found = true
          break
        end
      end

      if not found then
        vim.notify(string.format("Path segment '%s' not found in %d edges from %s", target_key, #edges, current_entity.uri), vim.log.levels.WARN)
        return nil, nil, nil
      end
    end

    return current_entity.uri, current_entity, context_signal
  end

  ---Get a value, unwrapping Signals if needed
  ---@param val any
  ---@return any
  local function unwrap(val)
    if type(val) == "table" and val.get then
      return val:get()
    end
    return val
  end

  ---Build the prefix (gutter + expand/collapse icon + type icon)
  ---@param ctx RenderContext
  ---@param type_icon string
  ---@return RenderSegment[]
  local function build_prefix(ctx, type_icon)
    local segments = {}
    local icons = ctx.icons

    -- Check if gutters are enabled
    local has_gutters = icons.gutter_branch and icons.gutter_branch ~= ""

    if has_gutters and ctx.depth > 0 then
      -- Draw continuation lines for ancestor depths (depth 0 to depth-2)
      for d = 1, ctx.depth - 1 do
        local guide = ctx.guides[d]
        if guide then
          -- Ancestor has more siblings below - draw vertical line
          table.insert(segments, { icons.gutter_vertical or "│ ", "DapTreeDepth" })
        else
          -- Ancestor was last child - draw blank
          table.insert(segments, { icons.gutter_blank or "  ", "DapTreeDepth" })
        end
      end

      -- Draw branch character for current item
      if ctx.is_last then
        table.insert(segments, { icons.gutter_last or "╰─", "DapTreeDepth" })
      else
        table.insert(segments, { icons.gutter_branch or "├─", "DapTreeDepth" })
      end
    elseif not has_gutters then
      -- Fallback to space-based indent
      local indent = string.rep(" ", ctx.depth * ctx.indent)
      if indent ~= "" then
        table.insert(segments, { indent })
      end
    end

    -- Expand/collapse state icon
    local state_icon
    if ctx.has_children then
      state_icon = ctx.is_collapsed and icons.collapsed or icons.expanded
    else
      state_icon = icons.leaf
    end
    table.insert(segments, { state_icon .. " ", "DapTreeIcon" })

    -- Entity type icon
    table.insert(segments, { type_icon .. " ", "DapTreeIcon" })

    return segments
  end

  ---Default renderers for each entity type
  ---@type table<string, EntityRenderer>
  local default_renderers = {
    debugger = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.debugger or "")
      local session_count = 0
      if entity.sessions then
        for _ in entity.sessions:iter() do
          session_count = session_count + 1
        end
      end

      local line = vim.list_extend(prefix, {
        { "Debugger", "DapTreeDebugger", { { id = "cursor", opts = {} } } },
        { " (" },
        { tostring(session_count), "DapTreeCount" },
        { session_count == 1 and " session)" or " sessions)" },
      })
      return { line = line, deps = {} }
    end,

    session = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.session or "")
      local name = unwrap(entity.name) or (entity.adapter_config and entity.adapter_config.type) or "Session"
      local state = unwrap(entity.state) or "unknown"
      local deps = {}
      if entity.name and entity.name.watch then table.insert(deps, entity.name) end
      if entity.state and entity.state.watch then table.insert(deps, entity.state) end

      local line = vim.list_extend(prefix, {
        { name, "DapTreeSession", { { id = "cursor", opts = {} } } },
        { " (" },
        { state, state == "stopped" and "DapTreeStopped" or "DapTreeState" },
        { ")" },
      })
      return { line = line, deps = deps }
    end,

    thread = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.thread or "")
      local state = unwrap(entity.state) or "unknown"
      local dap_id = entity.dap_id or 0
      local name = unwrap(entity.name) or "unnamed"
      local deps = {}
      if entity.name and entity.name.watch then table.insert(deps, entity.name) end
      if entity.state and entity.state.watch then table.insert(deps, entity.state) end

      local line = vim.list_extend(prefix, {
        { string.format("Thread %d: ", dap_id) },
        { name, "DapTreeThread", { { id = "cursor", opts = {} } } },
        { " (" },
        { state, state == "stopped" and "DapTreeStopped" or "DapTreeRunning" },
        { ")" },
      })
      return { line = line, deps = deps }
    end,

    stack = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.stack or "")
      local index = unwrap(entity.index) or 0
      local is_current = unwrap(entity._is_current)
      local deps = {}
      if entity.index and entity.index.watch then table.insert(deps, entity.index) end
      if entity._is_current and entity._is_current.watch then table.insert(deps, entity._is_current) end

      local line = vim.list_extend(prefix, {
        { is_current and "*" or "", "DapTreeCurrent" },
        { string.format("Stack [%d]", index), "DapTreeStack", { { id = "cursor", opts = {} } } },
      })
      return { line = line, deps = deps }
    end,

    frame = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.frame or "")
      local name = entity.name or "frame"
      local line_num = entity.line or 0
      local source_name = entity.source and entity.source.name or "unknown"
      local frame_id = entity.id or 0

      local line = vim.list_extend(prefix, {
        { string.format("[%d] ", frame_id), "DapTreeLineNum" },
        -- Cursor anchor at function name
        { name, "DapTreeFrame", { { id = "cursor", opts = {} } } },
        { " @ " },
        { source_name, "DapTreeSource" },
        { string.format(":%d", line_num), "DapTreeLineNum" },
      })
      return { line = line, deps = {} }
    end,

    scope = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.scope or "")
      local line = vim.list_extend(prefix, {
        { entity.name or "scope", "DapTreeScope", { { id = "cursor", opts = {} } } },
      })
      return { line = line, deps = {} }
    end,

    variable = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.variable or "")
      local name = entity.name or "?"
      local value = unwrap(entity.value) or ""
      local type_str = entity.type_hint or unwrap(entity.type) or ""
      local deps = {}
      if entity.value and entity.value.watch then table.insert(deps, entity.value) end
      if entity.type and entity.type.watch then table.insert(deps, entity.type) end

      local line = vim.list_extend(prefix, {
        -- Cursor anchor at variable name for quick editing/yanking
        { name, "DapTreeVariable", { { id = "cursor", opts = {} } } },
      })
      if type_str ~= "" then
        table.insert(line, { ": ", "DapTreePunctuation" })
        table.insert(line, { type_str, "DapTreeType" })
      end
      table.insert(line, { " = ", "DapTreePunctuation" })
      table.insert(line, { value, "DapTreeValue" })

      return { line = line, deps = deps }
    end,

    source = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.source or "")
      local line = vim.list_extend(prefix, {
        { entity.name or entity.path or "source", "DapTreeSource", { { id = "cursor", opts = {} } } },
      })
      return { line = line, deps = {} }
    end,

    breakpoint = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.breakpoint or "")
      local source = (entity.source and entity.source.path) or (entity.source and entity.source.name) or "unknown"
      local line = vim.list_extend(prefix, {
        { "BP @ ", "DapTreeBreakpoint", { { id = "cursor", opts = {} } } },
        { source, "DapTreeSource" },
        { string.format(":%d", entity.line or 0), "DapTreeLineNum" },
      })
      return { line = line, deps = {} }
    end,

    output = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.output or "")
      local category = entity.category or "output"
      local output = entity.output or ""
      -- Truncate long output
      if #output > 50 then
        output = output:sub(1, 47) .. "..."
      end
      -- Remove newlines
      output = output:gsub("\n", " ")

      local line = vim.list_extend(prefix, {
        { "[", "DapTreePunctuation" },
        { category, "DapTreeCategory" },
        { "] ", "DapTreePunctuation" },
        { output, "DapTreeOutput", { { id = "cursor", opts = {} } } },
      })
      return { line = line, deps = {} }
    end,

    evaluate_result = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.eval or "")
      local expression = entity.expression or "?"
      local result = entity.result or ""
      local type_str = entity.type or ""

      -- Truncate long values
      if #expression > 30 then
        expression = expression:sub(1, 27) .. "..."
      end
      if #result > 40 then
        result = result:sub(1, 37) .. "..."
      end

      local line = vim.list_extend(prefix, {
        { expression, "DapTreeExpression", { { id = "cursor", opts = {} } } },
        { " = ", "DapTreePunctuation" },
        { result, "DapTreeValue" },
      })
      if type_str ~= "" then
        table.insert(line, { " : ", "DapTreePunctuation" })
        table.insert(line, { type_str, "DapTreeType" })
      end
      return { line = line, deps = {} }
    end,

    binding = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.binding or "")
      local bp = entity.breakpoint
      local source = bp and ((bp.source and bp.source.path) or (bp.source and bp.source.name)) or "unknown"
      local line_num = bp and bp.line or 0

      local line = vim.list_extend(prefix, {
        { "Binding @ ", "DapTreeBinding", { { id = "cursor", opts = {} } } },
        { source, "DapTreeSource" },
        { string.format(":%d", line_num), "DapTreeLineNum" },
      })
      return { line = line, deps = {} }
    end,

    group = function(entity, ctx)
      local prefix = build_prefix(ctx, ctx.icons.group or "")
      local name = entity.name or "Group"
      local count = entity.count and entity.count:get() or 0
      local deps = {}
      if entity.count and entity.count.watch then table.insert(deps, entity.count) end

      local line = vim.list_extend(prefix, {
        { name, "DapTreeGroup", { { id = "cursor", opts = {} } } },
        { " (" },
        { tostring(count), "DapTreeCount" },
        { ")" },
      })
      return { line = line, deps = deps }
    end,
  }

  ---Fallback renderer for unknown entity types
  ---@type EntityRenderer
  local function fallback_renderer(entity, ctx)
    local prefix = build_prefix(ctx, "")
    local name = entity.name or entity.key or entity.uri or tostring(entity)
    local line = vim.list_extend(prefix, {
      { name },
    })
    return { line = line, deps = {} }
  end

  ---Get renderer for entity type
  ---@param entity_type string
  ---@return EntityRenderer
  local function get_renderer(entity_type)
    -- Check user config first, then defaults, then fallback
    if config.renderers and config.renderers[entity_type] then
      return config.renderers[entity_type]
    end
    return default_renderers[entity_type] or fallback_renderer
  end

  ---Check if entity has children (incoming edges in the tree direction)
  ---Also checks variablesReference for lazy-loaded DAP entities (scopes, variables)
  ---@param window TreeWindow
  ---@param item table Tree item with _virtual metadata
  ---@return boolean
  local function has_children(window, item)
    if not item or not item.uri then return false end

    -- Check for variablesReference (lazy-loaded DAP scopes/variables)
    -- These can have children even before they're fetched from the debugger
    if item.variablesReference and item.variablesReference > 0 then
      return true
    end

    -- Check for loaded children via edges
    local edges = window.store._reverse[item.uri]
    if not edges then return false end
    for _, edge in ipairs(edges) do
      if vim.tbl_contains(window.edge_types, edge.type) then
        return true
      end
    end
    return false
  end

  ---Render a single tree item using the renderer system
  ---@param item table Tree item with _virtual metadata
  ---@param is_focused boolean
  ---@param window TreeWindow
  ---@param guides boolean[] Pre-computed guides array
  ---@param is_last boolean Whether this is last sibling
  ---@return string line_text, table[] highlights, table[] deps, table[] extmarks
  local function render_item(item, is_focused, window, guides, is_last)
    local virtual = item._virtual
    local depth = virtual and virtual.depth or 0
    local vuri = virtual and virtual.uri or ""

    -- Check if has children and collapsed state
    local item_has_children = has_children(window, item)
    local entity_uri = virtual and virtual.entity_uri or item.uri
    local is_collapsed = window:is_collapsed(vuri, entity_uri)

    -- Build render context
    ---@type RenderContext
    local ctx = {
      depth = depth,
      has_children = item_has_children,
      is_collapsed = is_collapsed,
      is_focused = is_focused,
      is_last = is_last,
      guides = guides,
      icons = config.icons,
      indent = config.indent,
    }

    -- Get renderer and render
    local entity_type = item._type or "unknown"
    local renderer = get_renderer(entity_type)
    local result = renderer(item, ctx)

    -- Convert segments to line text, highlights, and extmarks
    local line_text = ""
    local highlights = {}
    local extmarks = {}
    local col = 0

    for _, segment in ipairs(result.line) do
      -- Sanitize text: replace newlines with spaces (nvim_buf_set_lines doesn't allow newlines)
      local text = (segment[1] or ""):gsub("\n", " ")
      local hl_group = segment[2]
      local segment_extmarks = segment[3]

      if hl_group then
        table.insert(highlights, {
          group = hl_group,
          col_start = col,
          col_end = col + #text,
        })
      end

      -- Collect extmarks at this column position
      if segment_extmarks then
        for _, ext in ipairs(segment_extmarks) do
          table.insert(extmarks, { col = col, spec = ext })
        end
      end

      line_text = line_text .. text
      col = col + #text
    end

    -- Add focused highlight (full line background)
    if is_focused then
      table.insert(highlights, {
        group = "DapTreeFocused",
        col_start = 0,
        col_end = -1,
        priority = 100,
      })
    end

    return line_text, highlights, result.deps or {}, extmarks
  end

  ---Compute guides and is_last for all items in viewport (O(n) algorithm)
  ---@param items table[] Window items array
  ---@return table[] Array of {guides: boolean[], is_last: boolean} per item
  local function compute_guides(items)
    local n = #items
    local result = {}

    -- Process in reverse to know about future siblings
    -- has_sibling_at[key] = true if a sibling exists later at "depth:parent_vuri"
    -- has_depth[d] = true if any item exists later at depth d (for guide lines)
    local has_sibling_at = {}
    local has_depth = {}

    for i = n, 1, -1 do
      local item = items[i]
      local depth = item._virtual and item._virtual.depth or 0
      local parent_vuri = item._virtual and item._virtual.parent_vuri or ""

      -- Key for this item's sibling group
      local key = depth .. ":" .. parent_vuri

      -- This item is "last" if no future sibling exists at same depth with same parent
      local is_last = not has_sibling_at[key]

      -- Build guides: for each ancestor depth, check if continuation line needed
      local guides = {}
      for d = 1, depth - 1 do
        guides[d] = has_depth[d] or false
      end

      result[i] = { guides = guides, is_last = is_last }

      -- Mark that a sibling exists at this depth for items before us
      has_sibling_at[key] = true
      has_depth[depth] = true

      -- Clear deeper levels (they're in our subtree, not ancestors)
      for d = depth + 1, depth + 100 do  -- reasonable max depth delta
        if has_depth[d] then
          has_depth[d] = nil
        else
          break  -- stop at first unset depth
        end
      end
      -- Also clear sibling keys at deeper depths
      for k, _ in pairs(has_sibling_at) do
        local k_depth = tonumber(k:match("^(%d+):"))
        if k_depth and k_depth > depth then
          has_sibling_at[k] = nil
        end
      end
    end

    return result
  end

  ---Render the tree buffer
  ---@param bufnr number
  local function render_buffer(bufnr)
    local state = buffer_state[bufnr]
    if not state or not state.window then return end

    local window = state.window
    local focus_vuri = window.focus:get()

    -- Clear old dep subscriptions
    if state.dep_subscriptions then
      for _, unsub in pairs(state.dep_subscriptions) do
        pcall(unsub)
      end
    end
    state.dep_subscriptions = {}

    -- Pre-compute guides for all items
    local items = window._window_items
    local guide_data = compute_guides(items)

    -- Collect all lines, highlights, extmarks, and deps
    local lines = {}
    local all_highlights = {}
    local all_extmarks = {}
    local all_deps = {} -- vuri -> deps[]

    for i, item in ipairs(items) do
      local vuri = item._virtual and item._virtual.uri
      local is_focused = vuri == focus_vuri
      local gd = guide_data[i] or { guides = {}, is_last = true }

      local line, highlights, deps, extmarks = render_item(item, is_focused, window, gd.guides, gd.is_last)
      table.insert(lines, line)

      for _, hl in ipairs(highlights) do
        table.insert(all_highlights, {
          line = i - 1,
          group = hl.group,
          col_start = hl.col_start,
          col_end = hl.col_end,
          priority = hl.priority,
        })
      end

      -- Collect extmarks with line number
      for _, ext in ipairs(extmarks) do
        table.insert(all_extmarks, {
          line = i - 1,
          col = ext.col,
          spec = ext.spec,
        })
      end

      -- Track deps for this item
      if deps and #deps > 0 then
        all_deps[vuri] = deps
      end
    end

    -- Update buffer (with safety check for deleted buffers)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
      return
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false

    -- Clear old highlights/extmarks and apply new ones
    vim.api.nvim_buf_clear_namespace(bufnr, state.ns_id, 0, -1)
    for _, hl in ipairs(all_highlights) do
      pcall(vim.api.nvim_buf_add_highlight, bufnr, state.ns_id, hl.group, hl.line, hl.col_start, hl.col_end)
    end

    -- Apply extmarks and track cursor anchors
    state.cursor_anchors = {} -- line -> col for extmarks with id="cursor"
    for _, ext in ipairs(all_extmarks) do
      pcall(vim.api.nvim_buf_set_extmark, bufnr, state.ns_id, ext.line, ext.col, ext.spec.opts)
      -- Track cursor anchor positions
      if ext.spec.id == "cursor" then
        state.cursor_anchors[ext.line] = ext.col
      end
    end

    -- Subscribe to deps for reactive updates
    for vuri, deps in pairs(all_deps) do
      for _, dep in ipairs(deps) do
        if dep and dep.watch then
          local unsub = dep:watch(function()
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(bufnr) then
                render_buffer(bufnr)
              end
            end)
          end)
          state.dep_subscriptions[vuri .. tostring(dep)] = unsub
        end
      end
    end

    -- Position cursor at focused item ONLY if focus changed
    -- (Avoids fighting with user's vim navigation like j/k/G)
    -- Snaps to cursor anchor extmark if present, otherwise column 0
    local current_focus = window.focus:get()
    if state.last_focus ~= current_focus then
      state.last_focus = current_focus
      local focus_index = window:focus_viewport_index()
      if focus_index > 0 then
        local win = vim.fn.bufwinid(bufnr)
        if win ~= -1 then
          -- Use cursor anchor column if available, otherwise column 0
          local col = state.cursor_anchors[focus_index - 1] or 0
          pcall(vim.api.nvim_win_set_cursor, win, { focus_index, col })
        end
      end
    end
  end

  ---Create keybind context for handlers
  ---@param bufnr number
  ---@return KeybindContext
  local function create_keybind_context(bufnr)
    local state = buffer_state[bufnr]
    local window = state and state.window
    -- Get focused item wrapper (has _virtual metadata)
    local focus_wrapper = window and window:getFocus() or nil
    -- Get actual entity from store (not wrapper) - this ensures methods like
    -- variables() and scopes() modify the real entity's state, not the wrapper's
    local entity = focus_wrapper and debugger.store:get(focus_wrapper.uri) or nil
    return {
      entity = entity,
      wrapper = focus_wrapper,  -- Still expose wrapper for _virtual metadata access
      window = window,
      debugger = debugger,
    }
  end

  ---Default keybind handlers (used when user doesn't override)
  ---Note: Rendering is automatic via on_rebuild subscription
  local default_keybinds = {
    -- Expand/Collapse
    ["<CR>"] = function(ctx)
      ctx.window:toggle()
    end,
    ["<Tab>"] = function(ctx)
      ctx.window:toggle()
    end,
    ["o"] = function(ctx)
      ctx.window:toggle()
    end,
    -- Expand and move into children (fetches children if needed)
    ["l"] = function(ctx)
      local entity = ctx.entity
      if entity and entity.children then
        entity:children()  -- Fetches if not loaded (no-op if no children)
      end

      local focus_vuri = ctx.window.focus:get()
      local focus_item = ctx.window:getFocus()
      local entity_uri = focus_item and focus_item.uri or nil
      local was_collapsed = ctx.window:is_collapsed(focus_vuri, entity_uri)

      if was_collapsed then
        ctx.window:expand()
        ctx.window:once_rebuild(function()
          ctx.window:move_into()
        end)
      else
        -- Already expanded, just move into first child
        ctx.window:move_into()
      end
    end,
    ["h"] = function(ctx)
      local window = ctx.window
      local focus_vuri = window.focus:get()
      local focus_item = window:getFocus()

      -- Check if node has children and is expanded
      local item_has_children = focus_item and has_children(window, focus_item)
      local entity_uri = focus_item and focus_item.uri or nil
      local is_expanded = item_has_children and not window:is_collapsed(focus_vuri, entity_uri)

      if is_expanded then
        -- Node is expanded, just collapse it
        window:collapse()
      else
        -- Node is collapsed or has no children, go to parent
        window:move_out()
      end
    end,

    -- Refresh
    ["R"] = function(ctx)
      ctx.window:refresh()
    end,

    -- Jump to entity (default: frames jump to source)
    ["gd"] = function(ctx)
      local entity = ctx.entity
      if not entity then return end

      -- For frames, jump to source location
      if entity._type == "frame" and entity.source then
        local source = entity.source
        if source.path then
          vim.cmd("edit " .. vim.fn.fnameescape(source.path))
          if entity.line then
            vim.api.nvim_win_set_cursor(0, { entity.line, (entity.column or 1) - 1 })
          end
        elseif source:is_virtual() then
          -- Open virtual source
          vim.cmd("edit " .. source:uri())
        end
      end
    end,

    -- Close buffer
    ["q"] = function(ctx)
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end,

    -- Debug: print focus node info
    ["?"] = function(ctx)
      local window = ctx.window
      local wrapper = ctx.wrapper
      local entity = ctx.entity
      print("=== Focus Node Debug ===")
      print("focus vuri: " .. tostring(window.focus:get()))
      if wrapper and wrapper._virtual then
        print("_virtual.uri: " .. tostring(wrapper._virtual.uri))
        print("_virtual.entity_uri: " .. tostring(wrapper._virtual.entity_uri))
        print("_virtual.depth: " .. tostring(wrapper._virtual.depth))
        if wrapper._virtual.path then
          print("_virtual.path: " .. table.concat(wrapper._virtual.path, " -> "))
        end
        if wrapper._virtual.pathkeys then
          print("_virtual.pathkeys: " .. table.concat(wrapper._virtual.pathkeys, "/"))
        end
      end
      if entity then
        print("entity.uri: " .. tostring(entity.uri))
        print("entity.key: " .. tostring(entity.key))
        print("entity._type: " .. tostring(entity._type))
      else
        print("entity: nil")
      end
    end,

    -- REPL input (on REPL group node)
    ["i"] = {
      group = function(entity, ctx)
        -- Only handle REPL group
        if entity.key ~= "~repl" then return end

        -- Open floating REPL input at cursor
        vim.cmd("DapReplLine")
      end,
    },
  }

  ---Setup keymaps for tree navigation
  ---@param bufnr number
  local function setup_keymaps(bufnr)
    local state = buffer_state[bufnr]
    if not state or not state.window then return end

    local window = state.window

    ---Invoke a handler (function or type dispatch table)
    ---Wraps handler in neostate.void() for async support
    ---@param handler KeybindHandler|KeybindDispatch
    ---@param ctx KeybindContext
    ---@return boolean? handled
    local function invoke_handler(handler, ctx)
      if type(handler) == "function" then
        -- Wrap in void to support async operations (children(), etc.)
        neostate.void(function()
          handler(ctx)
        end)()
        return true
      elseif type(handler) == "table" then
        -- Type dispatch table: { frame = fn(node, ctx), stack = fn, default = fn }
        local node = ctx.entity  -- wrapper with entity props + _virtual
        local entity_type = node and node._type
        local type_handler = entity_type and handler[entity_type]
        if type_handler then
          neostate.void(function()
            type_handler(node, ctx)
          end)()
          return true
        elseif handler.default then
          neostate.void(function()
            handler.default(node, ctx)
          end)()
          return true
        end
        -- No matching handler in dispatch table, fall through
        return nil
      end
    end

    ---Create a keybind handler that calls user handler first, then default
    ---@param key string
    ---@param default_handler KeybindHandler|KeybindDispatch|nil
    ---@return function
    local function make_handler(key, default_handler)
      return function()
        local ctx = create_keybind_context(bufnr)
        if not ctx.window then return end

        -- Check for user-defined handler
        local user_handler = config.keybinds[key]
        if user_handler then
          local handled = invoke_handler(user_handler, ctx)
          if handled then return end -- User handled it, skip default
        end

        -- Fall through to default handler
        if default_handler then
          invoke_handler(default_handler, ctx)
        end
      end
    end

    -- Navigation (these are hardcoded, not overridable via keybinds config)
    local function with_render(fn)
      return function()
        fn()
        render_buffer(bufnr)
      end
    end

    -- Use nowait to prevent conflicts with global mappings
    local map_opts = { buffer = bufnr, nowait = true }

    -- j/k use normal Vim motions (no mapping) - CursorMoved event syncs focus
    -- This allows count-prefixed motions like 20j, 4k, gg, G, etc.
    vim.keymap.set("n", "L", with_render(function() window:move_into() end), vim.tbl_extend("force", map_opts, { desc = "Move into child" }))
    vim.keymap.set("n", "H", with_render(function() window:move_out() end), vim.tbl_extend("force", map_opts, { desc = "Move to parent" }))

    -- Configurable keybinds (user can override or extend)
    for key, default_handler in pairs(default_keybinds) do
      vim.keymap.set("n", key, make_handler(key, default_handler), vim.tbl_extend("force", map_opts, { desc = "Tree action: " .. key }))
    end

    -- Also set up any user-defined keybinds that don't have defaults
    for key, _ in pairs(config.keybinds) do
      if not default_keybinds[key] then
        vim.keymap.set("n", key, make_handler(key, nil), vim.tbl_extend("force", map_opts, { desc = "Custom action: " .. key }))
      end
    end
  end

  ---Setup buffer options
  ---@param bufnr number
  local function setup_buffer(bufnr)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].filetype = "dap-tree"

    -- Set window options when buffer is displayed
    vim.api.nvim_create_autocmd("BufWinEnter", {
      buffer = bufnr,
      callback = function()
        vim.wo.wrap = false
        vim.wo.sidescrolloff = 5
      end,
    })

    -- Create namespace for highlights
    local ns_id = vim.api.nvim_create_namespace("dap-tree-" .. bufnr)

    return ns_id
  end

  ---Initialize tree for a buffer
  ---@param bufnr number
  ---@param root_uri string
  ---@param context_signal Signal? Optional signal to follow for root updates
  ---@param options table
  local function init_tree(bufnr, root_uri, context_signal, options)
    local ns_id = setup_buffer(bufnr)

    -- Use tree_parent edges (managed by this plugin for grouping)
    local edge_types = { "tree_parent" }

    -- Create TreeWindow
    local window = TreeWindow:new(debugger.store, root_uri, {
      edge_types = edge_types,
      direction = "in",
      above = config.above,
      below = config.below,
      default_collapsed = true,
      -- Fetch children when a node is expanded (including eager auto-expand)
      -- TreeWindow wraps on_expand in neostate.void() for async support
      on_expand = function(entity, vuri, entity_uri)
        if entity and entity.children then
          entity:children() -- Trigger lazy-loading of children
        end
      end,
    })

    -- Auto-expand root node on open
    local root_entity = debugger.store:get(root_uri)
    if root_entity then
      local root_vuri = root_entity.key or root_uri
      window:expand(root_vuri)
    end

    -- Track state
    local state = {
      window = window,
      ns_id = ns_id,
      subscriptions = {},
      dep_subscriptions = {},  -- Signal deps per-item
      last_focus = nil,  -- Track focus to avoid cursor jumping on re-render
    }
    buffer_state[bufnr] = state

    -- Exploration Lens: context-relative exploration state with BURN/TRANSPOSE
    -- Always create lens for contextual patterns to preserve expansion state on context change
    -- The ?focus= option controls whether focus is also preserved/transposed
    if context_signal then
      -- Create exploration lens to handle expansion state transfer
      local lens = ExplorationLens:new(window, context_signal, {
        on_render = function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            render_buffer(bufnr)
          end
        end,
      })
      state.lens = lens

      -- Initial focus only if ?focus= option is set
      if options.focus then
        vim.schedule(function()
          local initial_entity = context_signal:get()
          if initial_entity then
            window:focus_entity(initial_entity.uri)
            render_buffer(bufnr)
          end
        end)
      end

      -- Cleanup lens on buffer close
      table.insert(state.subscriptions, function()
        lens:dispose()
      end)

      -- Root-following: update root_uri when context changes
      -- Must also reset focus so _build_window starts from new root, not old focus
      local unsub_context = context_signal:watch(function(entity)
        if entity and entity.uri and entity.uri ~= window.root_uri then
          -- Update root and clear focus so _build_window uses new root_uri
          window.root_uri = entity.uri

          -- Compute new root's vuri and set focus to it
          local root_entity = window.store:get(entity.uri)
          local root_vuri = root_entity and root_entity.key or entity.uri
          window.focus:set(root_vuri)

          -- Refresh first to build window with new root, then expand
          -- (expand needs item to be in window to work)
          window:refresh()
          window:expand(root_vuri)
        end
      end)
      table.insert(state.subscriptions, unsub_context)
    end

    -- Subscribe to focus changes for reactive updates
    local unsub_focus = window.focus:watch(function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          render_buffer(bufnr)
        end
      end)
    end)
    table.insert(state.subscriptions, unsub_focus)

    -- Subscribe to window rebuild for reactive updates
    local unsub_rebuild = window:on_rebuild(function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          render_buffer(bufnr)
        end
      end)
    end)
    table.insert(state.subscriptions, unsub_rebuild)

    -- Track cursor movement to sync TreeWindow focus with Vim cursor
    local cursor_move_augroup = vim.api.nvim_create_augroup("dap-tree-cursor-" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = bufnr,
      group = cursor_move_augroup,
      callback = function()
        local win = vim.api.nvim_get_current_win()
        local row = vim.api.nvim_win_get_cursor(win)[1]

        -- Get the vuri at the current cursor row
        local items = window._window_items
        if row > 0 and row <= #items then
          local item = items[row]
          if item and item._virtual and item._virtual.uri then
            local vuri = item._virtual.uri
            -- Only update if focus is different (avoid loops)
            -- Render is automatic via focus:watch subscription
            if window.focus:get() ~= vuri then
              window:focus_on(vuri)
            end
          end
        end
      end,
    })

    -- Clean up cursor move autocmd when buffer is wiped
    table.insert(state.subscriptions, function()
      pcall(vim.api.nvim_del_augroup_by_id, cursor_move_augroup)
    end)

    -- Setup keymaps
    setup_keymaps(bufnr)

    -- Initial render
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        render_buffer(bufnr)
      end
    end)

    -- Start collapsed if requested
    if options.collapsed then
      window:collapse()
    end
  end

  -- Setup highlights on load
  setup_highlights()

  -- BufReadCmd for dap-tree: URIs
  -- Note: Vim's * doesn't match /, so we need multiple patterns for path depths
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = { "dap-tree:", "dap-tree:*", "dap-tree:*/*", "dap-tree:*/*/*", "dap-tree:*/*/*/*" },
    group = group,
    callback = function(opts)
      local bufnr = opts.buf
      local uri = opts.file

      -- Parse URI
      local root_pattern, options = parse_tree_uri(uri)

      -- Resolve root entity (returns signal for contextual patterns like @frame)
      local root_uri, root_entity, context_signal = resolve_root(root_pattern)

      if not root_uri then
        vim.notify("Could not resolve tree root: " .. root_pattern, vim.log.levels.WARN)
        return
      end

      -- Initialize tree with context signal for root-following
      init_tree(bufnr, root_uri, context_signal, options)
    end,
  })

  -- Cleanup on buffer delete or wipeout
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    pattern = { "dap-tree:", "dap-tree:*", "dap-tree:*/*", "dap-tree:*/*/*", "dap-tree:*/*/*/*" },
    group = group,
    callback = function(opts)
      local bufnr = opts.buf
      local state = buffer_state[bufnr]
      if state then
        -- Unsubscribe all viewport subscriptions
        for _, unsub in ipairs(state.subscriptions) do
          pcall(unsub)
        end
        -- Unsubscribe all dep subscriptions
        if state.dep_subscriptions then
          for _, unsub in pairs(state.dep_subscriptions) do
            pcall(unsub)
          end
        end
        -- Dispose window
        if state.window then
          state.window:dispose()
        end
        buffer_state[bufnr] = nil
      end
    end,
  })

  ---Cleanup a single buffer state
  ---@param state table
  local function cleanup_state(state)
    -- Unsubscribe all viewport subscriptions
    for _, unsub in ipairs(state.subscriptions or {}) do
      pcall(unsub)
    end
    -- Unsubscribe all dep subscriptions
    for _, unsub in pairs(state.dep_subscriptions or {}) do
      pcall(unsub)
    end
    -- Dispose window
    if state.window then
      state.window:dispose()
    end
  end

  ---Cleanup tree structure subscriptions
  local function cleanup_tree_subscriptions()
    for _, unsub in ipairs(tree_subscriptions) do
      pcall(unsub)
    end
    tree_subscriptions = {}
  end


  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    for _, state in pairs(buffer_state) do
      cleanup_state(state)
    end
    buffer_state = {}
    cleanup_tree_subscriptions()
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end)

  -- Return cleanup function
  return function()
    for _, state in pairs(buffer_state) do
      cleanup_state(state)
    end
    buffer_state = {}
    cleanup_tree_subscriptions()
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
end
