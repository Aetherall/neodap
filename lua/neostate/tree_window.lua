-- tree_window.lua
-- O(window + depth) windowed tree view using segment-based reactive collections
-- Rebuilds entire window on any change, but only traverses O(window) items

local neostate = require("neostate")

---@class TreeWindow
---@field store table EntityStore
---@field root_uri string Root entity URI
---@field edge_types string[] Edge types to follow
---@field direction "in"|"out" Edge direction
---@field budget { above: number, below: number } Viewport size
---@field scroll_margin number Items between focus and viewport edge before scrolling
---@field filter_fn function? Optional filter function
---@field prune_fn function? Optional prune function
---@field collapsed table<string, Signal> vuri -> Signal(bool) collapse state
---@field focus Signal Current focus vuri
---@field items Collection Viewport items (windowed view)
---@field _segments table Active segment collections (disposed on rebuild)
---@field _window_items table Raw items from last build (for index lookup)
local TreeWindow = {}
TreeWindow.__index = TreeWindow

---Create a new TreeWindow
---@param store table EntityStore
---@param root_uri string Root entity URI
---@param opts? { edge_type?: string, edge_types?: string[], direction?: "in"|"out", above?: number, below?: number, scroll_margin?: number, filter?: function, prune?: function, default_collapsed?: boolean }
---@return TreeWindow
function TreeWindow:new(store, root_uri, opts)
  opts = opts or {}

  local self = setmetatable({}, TreeWindow)

  -- Apply Disposable trait
  neostate.Disposable(self, nil, "TreeWindow:" .. root_uri)

  -- Store binding
  self.store = store
  self.root_uri = root_uri

  -- Edge configuration
  if opts.edge_types then
    self.edge_types = opts.edge_types
  elseif opts.edge_type then
    self.edge_types = { opts.edge_type }
  else
    self.edge_types = { "parent" }
  end

  -- Direction: "in" follows incoming edges (children point to parents)
  self.direction = opts.direction or "in"

  -- Viewport budget
  self.budget = {
    above = opts.above or 50,
    below = opts.below or 50,
  }

  -- Scroll margin
  self.scroll_margin = opts.scroll_margin or math.min(self.budget.above, self.budget.below)

  -- Filter/prune functions from opts
  self._user_filter = opts.filter
  self._user_prune = opts.prune

  -- Collapse defaults
  self._default_collapsed = opts.default_collapsed or false

  -- Expand/collapse hooks
  self._on_expand = opts.on_expand  -- function(entity, vuri, entity_uri)
  self._on_collapse = opts.on_collapse  -- function(entity, vuri, entity_uri)

  -- Track vuris that have had on_expand called (to avoid calling repeatedly for eager nodes)
  self._expanded_notified = {}

  -- Collapse state (path-specific, using Signals for reactivity)
  self.collapsed = {}

  -- Focus (reactive)
  self.focus = neostate.Signal(nil)
  self.focus:set_parent(self)

  -- Viewport (reactive Collection) - the windowed view
  self.items = neostate.Collection("TreeWindow:viewport")
  self.items:set_parent(self)

  -- Segment collections (disposed on rebuild)
  self._segments = {}

  -- Raw window items for O(1) index lookup
  self._window_items = {}

  -- Search state
  self.search_query = nil

  -- Reactive filter subscriptions (vuri -> unsubscribe function)
  self._filter_subs = {}

  -- Rebuild timer
  self._rebuild_timer = nil

  -- Rebuild listeners (called after _build_window completes)
  self._on_rebuild_listeners = {}

  -- Build initial window
  self:_build_window()

  -- Initialize focus to first item if available
  if #self._window_items > 0 then
    local first_item = self._window_items[1]
    if first_item and first_item._virtual then
      self.focus:set(first_item._virtual.uri)
    end
  end

  return self
end

-- =============================================================================
-- Segment Lifecycle Management
-- =============================================================================

---Create a reactive DFS segment that triggers rebuild on change
---@param uri string Starting entity URI
---@param budget number Maximum items to collect
---@param reverse boolean Whether to reverse iteration order
---@param order "pre"|"post" DFS order (pre=parent before children, post=children before parent)
---@param segment_opts? { start_at_child?: string, start_after_child?: string } Options to skip children at depth 0
---@param prefix_keys? string[] Keys to prefix vuris with (for building full vuris from segment-relative vuris)
---@return table Collection segment
function TreeWindow:_create_segment(uri, budget, reverse, order, segment_opts, prefix_keys)
  local tw = self
  prefix_keys = prefix_keys or {}
  local prefix_str = #prefix_keys > 0 and (table.concat(prefix_keys, "/") .. "/") or ""

  -- Prune function that combines user prune + collapse state
  local function prune_fn(entity, ctx)
    -- Check user prune first
    if tw._user_prune then
      local result = tw._user_prune(entity, ctx)
      if type(result) == "table" and result.get then
        if result:get() then return true end
      elseif result then
        return true
      end
    end

    -- Check collapse state by full virtual URI (path-specific collapse)
    local rel_vuri = ctx and ctx.uri
    if rel_vuri then
      local full_vuri = prefix_str .. rel_vuri
      local signal = tw.collapsed[full_vuri]

      if signal then
        -- Explicit state exists, use it
        local is_collapsed = signal:get()
        if not is_collapsed then
          -- Node is explicitly expanded, notify (idempotent)
          local entity_uri = entity and entity.uri
          tw:_notify_expand(full_vuri, entity_uri)
        end
        return is_collapsed
      end

      -- No explicit state - check default behavior
      if tw._default_collapsed then
        -- Default is collapsed, but check if entity has eager flag
        local entity_uri = entity and entity.uri
        if entity_uri then
          local e = tw.store:get(entity_uri)
          if e and e.eager ~= nil then
            -- Handle both Signal and plain boolean (can't use and/or pattern since false is valid)
            local eager
            if type(e.eager) == "table" and e.eager.get then
              eager = e.eager:get()
            else
              eager = e.eager
            end
            if eager then
              -- Notify on_expand for eager nodes (fires once per vuri)
              tw:_notify_expand(full_vuri, entity_uri)
              return false -- Eager entities expand by default
            end
          end
        end
        return true -- Default collapsed
      end
    end

    return false
  end

  -- Prune watch returns collapse signal for the full virtual URI (if it exists)
  -- Signals are created lazily when toggle/collapse is called, not during traversal
  local function prune_watch(entity, ctx)
    local rel_vuri = ctx and ctx.uri
    if not rel_vuri then return nil end
    local full_vuri = prefix_str .. rel_vuri
    return tw.collapsed[full_vuri]  -- Only return existing signal, don't create
  end

  -- Filter function
  local function filter_fn(entity, ctx)
    -- 1. Check user filter
    if tw._user_filter then
      local result = tw._user_filter(entity, ctx)

      -- Handle Signal return (reactive filter)
      if type(result) == "table" and result.get and result.watch then
        local vuri = ctx and ctx.uri or entity.uri
        -- Subscribe if not already subscribed
        if not tw._filter_subs[vuri] then
          tw._filter_subs[vuri] = result:watch(function()
            tw:_schedule_rebuild()
          end)
        end
        -- Get current value
        if not result:get() then return false end
      elseif not result then
        return false
      end
    end

    -- 2. Check search query
    if tw.search_query and #tw.search_query > 0 then
      if not tw:_matches_search(entity, tw.search_query) then return false end
    end

    return true
  end

  segment_opts = segment_opts or {}
  -- Only limit scanning when using start_at_child/start_after_child (flat tree optimization)
  -- For regular hierarchical traversal, we want to scan the full tree
  local uses_linked_list = segment_opts.start_at_child or segment_opts.start_after_child
  local collection = self.store:dfs(uri, {
    direction = self.direction,
    edge_types = self.edge_types,
    reverse = reverse,
    order = order,
    unique_budget = budget,
    scanning_budget = uses_linked_list and (budget * 2) or nil,
    filter = filter_fn,
    prune = prune_fn,
    prune_watch = prune_watch,
    start_at_child = segment_opts.start_at_child,
    start_after_child = segment_opts.start_after_child,
  })

  -- Parent to self for auto-disposal
  collection:set_parent(self)

  -- Track for manual disposal on rebuild
  table.insert(self._segments, collection)

  -- Subscribe: any change triggers full rebuild
  collection:on_added(function()
    self:_schedule_rebuild()
  end)
  collection:on_removed(function()
    self:_schedule_rebuild()
  end)

  return collection
end

---Dispose all segment collections and clean up filter subscriptions
function TreeWindow:_dispose_segments()
  -- Dispose segments
  for _, segment in ipairs(self._segments or {}) do
    segment:dispose()
  end
  self._segments = {}

  -- Clean up filter signal subscriptions
  for _, unsub in pairs(self._filter_subs or {}) do
    if type(unsub) == "function" then unsub() end
  end
  self._filter_subs = {}
end

---Schedule a debounced rebuild
function TreeWindow:_schedule_rebuild()
  if self._rebuild_timer then
    vim.fn.timer_stop(self._rebuild_timer)
  end
  self._rebuild_timer = vim.fn.timer_start(16, function() -- 16ms = ~60fps
    self._rebuild_timer = nil
    if not self._disposed then
      self:_build_window()
    end
  end)
end

-- =============================================================================
-- Window Building (O(window + depth))
-- =============================================================================

---Build the window around the current focus
function TreeWindow:_build_window()
  -- Dispose previous segments before creating new ones
  self:_dispose_segments()

  -- Get focused item to access its _virtual.path (correct path through tree)
  local focus_vuri = self.focus:get()
  local focus_item = focus_vuri and self:_find_in_window(focus_vuri) or nil
  local focus_uri = focus_item and focus_item.uri or nil

  -- If no focus, start from root
  if not focus_uri then
    focus_uri = self.root_uri
  end

  -- Get path from focus to root
  -- Use _virtual.path from focused item if available (preserves correct path through multi-parent entities)
  -- Fall back to path_to_root for initial window build when no focus item exists yet
  local path
  if focus_item and focus_item._virtual and focus_item._virtual.path then
    -- _virtual.path is in root-to-parent order [root, ..., parent]
    -- We need focus-to-root order [focus, parent, ..., root], so iterate in reverse
    path = { focus_uri }
    for i = #focus_item._virtual.path, 1, -1 do
      table.insert(path, focus_item._virtual.path[i])
    end
  else
    path = self.store:path_to_root(focus_uri, self.edge_types[1])
  end

  -- Truncate path at root_uri (don't traverse above configured root)
  local truncated_path = {}
  for i = 1, #path do
    table.insert(truncated_path, path[i])
    if path[i] == self.root_uri then
      break
    end
  end
  path = truncated_path

  -- Build path prefix lookups: entity_uri -> ancestor keys/uris from root
  -- This is used to prefix segment vuris with the full path
  local path_prefix_keys = {}  -- path_prefix_keys[entity_uri] = {"root_key", "A_key", ...}
  local path_prefix_uris = {}  -- path_prefix_uris[entity_uri] = {"root_uri", "A_uri", ...}
  for i = #path, 1, -1 do
    local entity = self.store:get(path[i])
    local key = entity and entity.key or path[i]
    path_prefix_keys[path[i]] = {}
    path_prefix_uris[path[i]] = {}
    for j = #path, i + 1, -1 do
      local anc = self.store:get(path[j])
      table.insert(path_prefix_keys[path[i]], anc and anc.key or path[j])
      table.insert(path_prefix_uris[path[i]], path[j])
    end
  end

  local above_items, below_items = {}, {}
  local above_budget, below_budget = self.budget.above, self.budget.below

  -- ABOVE: Walk up path, collect preceding siblings using start_after_child optimization
  -- This reduces from O(siblings) segments per level to O(1) segment per level
  for level = 1, #path do
    if above_budget <= 0 then break end
    local node_uri = path[level]

    -- Add ancestor (skip focus at level 1)
    if level > 1 then
      local entity = self.store:get(node_uri)
      if entity and self:_passes_filter(entity, node_uri) then
        table.insert(above_items, self:_make_ancestor_item(node_uri, path, level))
        above_budget = above_budget - 1
      end
    end

    -- If there's a parent, create ONE segment for all preceding sibling subtrees
    if level < #path and above_budget > 0 then
      local parent_uri = path[level + 1]
      -- Use parent_uri prefix since segment starts at parent (items already have parent key in vuri)
      local prefix_keys = path_prefix_keys[parent_uri] or {}
      local prefix_uris = path_prefix_uris[parent_uri] or {}
      -- +1 budget to account for parent which we'll skip
      local segment = self:_create_segment(parent_uri, above_budget + 1, true, "post", {
        start_after_child = node_uri,
      }, prefix_keys)
      -- Skip the last item (parent) since it's added separately as ancestor
      for i = 1, #segment._items - 1 do
        local item = segment._items[i]
        table.insert(above_items, self:_wrap_with_prefix(item, prefix_keys, prefix_uris))
      end
      above_budget = above_budget - math.max(0, #segment._items - 1)
    end
  end

  -- BELOW: Focus subtree first
  local focus_prefix_keys = path_prefix_keys[focus_uri] or {}
  local focus_prefix_uris = path_prefix_uris[focus_uri] or {}
  local focus_segment = self:_create_segment(focus_uri, below_budget, false, "pre", nil, focus_prefix_keys)
  for _, item in ipairs(focus_segment._items) do
    table.insert(below_items, self:_wrap_with_prefix(item, focus_prefix_keys, focus_prefix_uris))
  end
  below_budget = below_budget - #focus_segment._items

  -- Then following siblings at each level using start_after_child optimization
  for level = 1, #path do
    if below_budget <= 0 then break end
    local node_uri = path[level]

    -- If there's a parent, create ONE segment for all following sibling subtrees
    if level < #path then
      local parent_uri = path[level + 1]
      -- Use parent_uri prefix since segment starts at parent (items already have parent key in vuri)
      local prefix_keys = path_prefix_keys[parent_uri] or {}
      local prefix_uris = path_prefix_uris[parent_uri] or {}
      -- +1 budget to account for parent which we'll skip
      local segment = self:_create_segment(parent_uri, below_budget + 1, false, "pre", {
        start_after_child = node_uri,
      }, prefix_keys)
      -- Skip the first item (parent) since it's the DFS start node
      for i = 2, #segment._items do
        local item = segment._items[i]
        table.insert(below_items, self:_wrap_with_prefix(item, prefix_keys, prefix_uris))
      end
      below_budget = below_budget - math.max(0, #segment._items - 1)
    end
  end

  -- Combine: reverse above, then below
  self._window_items = {}
  for i = #above_items, 1, -1 do
    table.insert(self._window_items, above_items[i])
  end
  for _, item in ipairs(below_items) do
    table.insert(self._window_items, item)
  end

  self:_refresh_viewport()

  -- Notify rebuild listeners
  for _, listener in ipairs(self._on_rebuild_listeners) do
    listener()
  end
end

---Wrap a segment item with a path prefix to create correct full vuri
---@param item table Segment item
---@param prefix_keys string[] Keys of ancestors from root to parent
---@param prefix_uris? string[] Entity URIs of ancestors from root to parent
---@param depth_offset? number Optional depth adjustment (use -1 for start_after_child segments)
---@return table Wrapped item with correct vuri
function TreeWindow:_wrap_with_prefix(item, prefix_keys, prefix_uris, depth_offset)
  if not item or not item._virtual then return item end

  prefix_uris = prefix_uris or {}
  depth_offset = depth_offset or 0

  -- Build full vuri: prefix + item's relative vuri
  local full_vuri
  if #prefix_keys > 0 then
    full_vuri = table.concat(prefix_keys, "/") .. "/" .. item._virtual.uri
  else
    full_vuri = item._virtual.uri
  end

  -- Build full pathkeys
  local full_pathkeys = {}
  for _, k in ipairs(prefix_keys) do
    table.insert(full_pathkeys, k)
  end
  for _, k in ipairs(item._virtual.pathkeys or {}) do
    table.insert(full_pathkeys, k)
  end

  -- Build full path (entity URIs)
  local full_path = {}
  for _, uri in ipairs(prefix_uris) do
    table.insert(full_path, uri)
  end
  for _, uri in ipairs(item._virtual.path or {}) do
    table.insert(full_path, uri)
  end

  -- Compute parent vuri
  local parent_vuri = nil
  if #full_pathkeys > 1 then
    local parent_keys = {}
    for i = 1, #full_pathkeys - 1 do
      table.insert(parent_keys, full_pathkeys[i])
    end
    parent_vuri = table.concat(parent_keys, "/")
  end

  -- Create wrapper with modified _virtual
  local wrapper = neostate.Disposable({}, nil, "PrefixedItem:" .. full_vuri)
  wrapper._virtual = {
    uri = full_vuri,
    depth = (item._virtual.depth or 0) + #prefix_keys + depth_offset,
    pathkeys = full_pathkeys,
    path = full_path,
    parent_vuri = parent_vuri,
    entity_uri = item.uri,
  }

  -- Delegate to original item for entity properties
  setmetatable(wrapper, { __index = item })

  return wrapper
end

---Get the entity URI from the current focus vuri
---@return string? Entity URI
function TreeWindow:_focus_entity_uri()
  local focus_vuri = self.focus:get()
  if not focus_vuri then return nil end

  -- Find the focused item in window and get its entity URI
  local item, _ = self:_find_in_window(focus_vuri)
  if item then
    return item.uri  -- Entity URI via __index delegation
  end

  -- Fallback: if vuri equals root entity key, return root URI
  local root = self.store:get(self.root_uri)
  if root and (root.key == focus_vuri or focus_vuri == self.root_uri) then
    return self.root_uri
  end

  return nil
end

---Check if entity passes filter
---@param entity table
---@param uri string
---@return boolean
function TreeWindow:_passes_filter(entity, uri)
  -- Check user filter
  if self._user_filter then
    local result = self._user_filter(entity, { uri = uri })
    if type(result) == "table" and result.get then
      if not result:get() then return false end
    elseif not result then
      return false
    end
  end

  -- Check search query
  if self.search_query and #self.search_query > 0 then
    if not self:_matches_search(entity, self.search_query) then return false end
  end

  return true
end

---Create an item wrapper for an ancestor node
---@param uri string Entity URI
---@param path string[] Path to root (entity URIs)
---@param level number Level in path (1 = focus)
---@return table Item wrapper
function TreeWindow:_make_ancestor_item(uri, path, level)
  local entity = self.store:get(uri)
  if not entity then return nil end

  -- Build virtual URI from path (reversed, root first)
  local pathkeys = {}
  for i = #path, level, -1 do
    local node = self.store:get(path[i])
    if node then
      table.insert(pathkeys, node.key or path[i])
    end
  end
  local vuri = table.concat(pathkeys, "/")

  -- Build ancestor path (entity URIs, root first, excluding self)
  local ancestor_path = {}
  for i = #path, level + 1, -1 do
    table.insert(ancestor_path, path[i])
  end

  -- Calculate depth (distance from root)
  local depth = #path - level

  -- Compute parent vuri
  local parent_vuri = nil
  if #pathkeys > 1 then
    local parent_keys = {}
    for i = 1, #pathkeys - 1 do
      table.insert(parent_keys, pathkeys[i])
    end
    parent_vuri = table.concat(parent_keys, "/")
  end

  local wrapper = neostate.Disposable({}, nil, "AncestorItem:" .. vuri)
  wrapper._virtual = {
    uri = vuri,
    depth = depth,
    pathkeys = pathkeys,
    path = ancestor_path,
    parent_vuri = parent_vuri,
    entity_uri = uri,
  }

  -- Delegate to entity for properties
  setmetatable(wrapper, { __index = entity })

  return wrapper
end

-- =============================================================================
-- Viewport Management
-- =============================================================================

---Refresh the viewport based on _window_items
function TreeWindow:_refresh_viewport()
  -- Clear current viewport
  while #self.items._items > 0 do
    local item = self.items._items[1]
    self.items:delete(function(w) return w == item end)
  end

  -- Add items from _window_items to viewport
  for _, item in ipairs(self._window_items) do
    if item then
      local wrapper = self:_create_viewport_wrapper(item)
      if wrapper then
        self.items:add(wrapper)
      end
    end
  end

  -- Validate focus is in viewport
  local focus_vuri = self.focus:get()
  if focus_vuri then
    local found = false
    for _, item in ipairs(self.items._items) do
      if item._virtual and item._virtual.uri == focus_vuri then
        found = true
        break
      end
    end
    if not found and #self.items._items > 0 then
      -- Focus not in viewport, set to first item
      local first = self.items._items[1]
      if first and first._virtual then
        self.focus:set(first._virtual.uri)
      end
    end
  elseif #self.items._items > 0 then
    -- No focus, set to first item
    local first = self.items._items[1]
    if first and first._virtual then
      self.focus:set(first._virtual.uri)
    end
  end
end

---Create a viewport wrapper for an item
---@param item table Item from window
---@return table? Viewport wrapper
function TreeWindow:_create_viewport_wrapper(item)
  if not item or not item._virtual then return nil end

  -- Create a thin wrapper that references the item
  local wrapper = neostate.Disposable({}, nil, "ViewportItem:" .. item._virtual.uri)

  -- Delegate to item (which delegates to entity) for properties
  setmetatable(wrapper, { __index = item })

  return wrapper
end

-- =============================================================================
-- Helper functions
-- =============================================================================

---Get parent virtual URI
---@param vuri string
---@return string?
function TreeWindow:_parent_vuri(vuri)
  local last_slash = vuri:match(".*/()")
  if not last_slash then return nil end
  return vuri:sub(1, last_slash - 2)
end

---Find item in window items by vuri
---@param vuri string
---@return table?, number? Item and index
function TreeWindow:_find_in_window(vuri)
  for i, item in ipairs(self._window_items) do
    if item and item._virtual and item._virtual.uri == vuri then
      return item, i
    end
  end
  return nil, nil
end

---Check if vuri exists in window
---@param vuri string
---@return boolean
function TreeWindow:_exists_in_window(vuri)
  local item, _ = self:_find_in_window(vuri)
  return item ~= nil
end

-- =============================================================================
-- Navigation
-- =============================================================================

---Set focus to a specific vuri
---@param vuri string
---@return boolean success
function TreeWindow:focus_on(vuri)
  if not vuri then return false end

  -- If not in current window, rebuild window around this vuri
  if not self:_exists_in_window(vuri) then
    -- Extract entity URI from vuri
    local entity_uri = vuri
    local last_slash = vuri:match(".*/()")
    if last_slash then
      entity_uri = vuri:sub(last_slash)
    end

    -- Check entity exists in store
    if not self.store:get(entity_uri) then
      return false
    end

    -- Set focus and rebuild
    self.focus:set(vuri)
    self:_build_window()
    return true
  end

  self.focus:set(vuri)

  -- Check if we need to shift window (approaching edge within scroll margin)
  local viewport_pos = self:focus_viewport_index()
  if viewport_pos then
    local below_count = #self._window_items - viewport_pos
    if viewport_pos <= self.scroll_margin or below_count < self.scroll_margin then
      self:_build_window()
    end
  end

  return true
end

---Focus on an entity by its entity URI (not vuri)
---Computes the path to root, uncollapses ancestors, and focuses
---@param entity_uri string Entity URI (key in EntityStore)
---@return boolean success
function TreeWindow:focus_entity(entity_uri)
  -- Check if entity is in current window
  for _, item in ipairs(self._window_items) do
    if item.uri == entity_uri then
      return self:focus_on(item._virtual.uri)
    end
  end

  -- Not in window - compute path and rebuild
  local path = self.store:path_to_root(entity_uri, self.edge_types[1])
  if #path == 0 then return false end

  -- Verify entity is descendant of tree root
  local root_idx = nil
  for i, uri in ipairs(path) do
    if uri == self.root_uri then
      root_idx = i
      break
    end
  end
  if not root_idx then return false end

  -- Truncate path at root
  local truncated = {}
  for i = 1, root_idx do
    table.insert(truncated, path[i])
  end

  -- Build ancestor vuris and uncollapse them
  -- Path is [target, parent, grandparent, ..., root]
  -- We need to build vuris from root down: root, root/parent, root/parent/grandparent, ...
  local ancestor_keys = {}
  for i = #truncated, 2, -1 do  -- Skip target at index 1
    local entity = self.store:get(truncated[i])
    table.insert(ancestor_keys, entity and entity.key or truncated[i])
    local ancestor_vuri = table.concat(ancestor_keys, "/")
    local signal = self.collapsed[ancestor_vuri]
    if signal then signal:set(false) end
  end

  -- Build full vuri for target (reverse: root first, then down to entity)
  local keys = {}
  for i = #truncated, 1, -1 do
    local entity = self.store:get(truncated[i])
    table.insert(keys, entity and entity.key or truncated[i])
  end
  local vuri = table.concat(keys, "/")

  -- Focus and rebuild
  self.focus:set(vuri)
  self:_build_window()
  return true
end

---Move focus down
---@return boolean success
function TreeWindow:move_down()
  local focus_vuri = self.focus:get()
  if not focus_vuri then return false end

  local _, focus_idx = self:_find_in_window(focus_vuri)
  if not focus_idx then return false end

  if focus_idx < #self._window_items then
    local next_item = self._window_items[focus_idx + 1]
    if next_item and next_item._virtual then
      self.focus:set(next_item._virtual.uri)

      -- Check if we need to shift window (approaching bottom edge)
      local viewport_pos = self:focus_viewport_index()
      local below_count = #self._window_items - viewport_pos
      if below_count < self.scroll_margin then
        self:_build_window()
      end

      return true
    end
  end

  return false
end

---Move focus up
---@return boolean success
function TreeWindow:move_up()
  local focus_vuri = self.focus:get()
  if not focus_vuri then return false end

  local _, focus_idx = self:_find_in_window(focus_vuri)
  if not focus_idx then return false end

  if focus_idx > 1 then
    local prev_item = self._window_items[focus_idx - 1]
    if prev_item and prev_item._virtual then
      self.focus:set(prev_item._virtual.uri)

      -- Check if we need to shift window (approaching top edge)
      local viewport_pos = self:focus_viewport_index()
      if viewport_pos <= self.scroll_margin then
        self:_build_window()
      end

      return true
    end
  end

  return false
end

---Move into first child
---@return boolean success
function TreeWindow:move_into()
  local focus_vuri = self.focus:get()
  if not focus_vuri then return false end

  local _, focus_idx = self:_find_in_window(focus_vuri)
  if not focus_idx then return false end

  -- In DFS order, first child (if any) is immediately after and has this vuri as prefix
  if focus_idx < #self._window_items then
    local next_item = self._window_items[focus_idx + 1]
    if next_item and next_item._virtual then
      local next_vuri = next_item._virtual.uri
      -- Check if it's a child (starts with focus_vuri/)
      if next_vuri:find(focus_vuri .. "/", 1, true) == 1 then
        self.focus:set(next_vuri)
        self:_refresh_viewport()
        return true
      end
    end
  end

  return false
end

---Move out to parent
---@return boolean success
function TreeWindow:move_out()
  local focus_vuri = self.focus:get()
  if not focus_vuri then return false end

  local parent_vuri = self:_parent_vuri(focus_vuri)
  if not parent_vuri then return false end

  return self:focus_on(parent_vuri)
end

-- =============================================================================
-- Collapse/Expand
-- =============================================================================

---Get or create collapse signal for a vuri
---@param vuri string Virtual URI (used as key for collapse state)
---@param entity_uri string? Entity URI (used for eager check)
---@return Signal
function TreeWindow:_get_collapse_signal(vuri, entity_uri)
  if not self.collapsed[vuri] then
    -- Determine initial collapse state
    local should_collapse = self._default_collapsed

    -- Check entity.eager for auto-expand override
    -- Entities can set eager=true (or eager signal) to auto-expand in tree views
    if should_collapse and entity_uri then
      local entity = self.store:get(entity_uri)
      if entity and entity.eager ~= nil then
        -- Handle both Signal and plain boolean (can't use and/or pattern since false is valid)
        local eager
        if type(entity.eager) == "table" and entity.eager.get then
          eager = entity.eager:get()
        else
          eager = entity.eager
        end
        if eager then
          should_collapse = false  -- Eager entity: start expanded
        end
      end
    end

    self.collapsed[vuri] = neostate.Signal(should_collapse)
    self.collapsed[vuri]:set_parent(self)
  end
  return self.collapsed[vuri]
end

---Fire on_expand hook if not already notified for this vuri
---Wraps callback in neostate.void() for async support (e.g., fetching children via DAP)
---@param vuri string Virtual URI
---@param entity_uri string? Entity URI
---@private
function TreeWindow:_notify_expand(vuri, entity_uri)
  if not self._on_expand then return end
  if self._expanded_notified[vuri] then return end

  self._expanded_notified[vuri] = true
  local entity = entity_uri and self.store:get(entity_uri)
  -- Wrap in void() to support async operations (children() may call settle())
  neostate.void(function()
    self._on_expand(entity, vuri, entity_uri)
  end)()
end

---Fire on_collapse hook and clear expand notification for this vuri
---@param vuri string Virtual URI
---@param entity_uri string? Entity URI
---@private
function TreeWindow:_notify_collapse(vuri, entity_uri)
  -- Clear expand notification so it can fire again if re-expanded
  self._expanded_notified[vuri] = nil

  if not self._on_collapse then return end
  local entity = entity_uri and self.store:get(entity_uri)
  self._on_collapse(entity, vuri, entity_uri)
end

---Check if an entity is collapsed
---@param vuri string Virtual URI
---@param entity_uri string? Entity URI for eager check
---@return boolean
function TreeWindow:is_collapsed(vuri, entity_uri)
  local signal = self.collapsed[vuri]

  if signal then
    return signal:get()
  end

  -- No explicit state - check default behavior
  if self._default_collapsed then
    -- Default is collapsed, but check if entity has eager flag
    if entity_uri then
      local entity = self.store:get(entity_uri)
      if entity and entity.eager ~= nil then
        -- Handle both Signal and plain boolean (can't use and/or pattern since false is valid)
        local eager
        if type(entity.eager) == "table" and entity.eager.get then
          eager = entity.eager:get()
        else
          eager = entity.eager
        end
        if eager then
          return false -- Eager entities are expanded by default
        end
      end
    end
    return true -- Default collapsed
  end

  return false
end

---Toggle collapse state
---@param vuri string? Virtual URI
function TreeWindow:toggle(vuri)
  vuri = vuri or self.focus:get()
  if not vuri then return end

  -- Find item to get entity URI for eager check
  local item, _ = self:_find_in_window(vuri)
  local entity_uri = item and item._virtual and item._virtual.entity_uri or item and item.uri

  local signal = self:_get_collapse_signal(vuri, entity_uri)
  signal:set(not signal:get())
  self:_build_window()
end

---Expand a node
---@param vuri string? Virtual URI
function TreeWindow:expand(vuri)
  vuri = vuri or self.focus:get()
  if not vuri then return end

  -- Find item to get entity URI for eager check
  local item, _ = self:_find_in_window(vuri)
  local entity_uri = item and item._virtual and item._virtual.entity_uri or item and item.uri

  local signal = self:_get_collapse_signal(vuri, entity_uri)
  if signal:get() then
    signal:set(false)
    -- Notify on_expand (idempotent, tracks notified vuris)
    self:_notify_expand(vuri, entity_uri)
    self:_build_window()
  end
end

---Collapse a node
---@param vuri string? Virtual URI
function TreeWindow:collapse(vuri)
  vuri = vuri or self.focus:get()
  if not vuri then return end

  -- Find item to get entity URI for eager check
  local item, _ = self:_find_in_window(vuri)
  local entity_uri = item and item._virtual and item._virtual.entity_uri or item and item.uri

  local signal = self:_get_collapse_signal(vuri, entity_uri)
  if not signal:get() then
    signal:set(true)
    -- Notify on_collapse (also clears expand notification so it can re-fire)
    self:_notify_collapse(vuri, entity_uri)

    -- If focus is under collapsed node, move focus to collapsed node
    local focus_vuri = self.focus:get()
    if focus_vuri and focus_vuri:find(vuri .. "/", 1, true) == 1 then
      self.focus:set(vuri)
    end
    self:_build_window()
  end
end

-- =============================================================================
-- Filter & Search
-- =============================================================================

---Set filter function
---@param fn function?
function TreeWindow:set_filter(fn)
  self._user_filter = fn
  self:_build_window()
end

---Set search query
---@param query string?
function TreeWindow:set_search(query)
  self.search_query = query
  self:_build_window()
end

---Clear search
function TreeWindow:clear_search()
  self.search_query = nil
  self:_build_window()
end

---Check if entity matches search
---@param entity table
---@param query string
---@return boolean
function TreeWindow:_matches_search(entity, query)
  local name = entity.name or entity.key or ""
  return name:lower():find(query:lower(), 1, true) ~= nil
end

-- =============================================================================
-- Utility
-- =============================================================================

---Force refresh
function TreeWindow:refresh()
  self:_build_window()
end

---Get state info
---@return { focus: string?, focus_index: number, viewport_size: number, total_size: number }
function TreeWindow:info()
  return {
    focus = self.focus:get(),
    focus_index = self:focus_viewport_index(),
    viewport_size = #self.items._items,
    total_size = #self._window_items,
  }
end

---Get focus position in viewport
---@return number 1-based index, or 0 if not found
function TreeWindow:focus_viewport_index()
  local focus_vuri = self.focus:get()
  if not focus_vuri then return 0 end

  for i, item in ipairs(self.items._items) do
    if item._virtual and item._virtual.uri == focus_vuri then
      return i
    end
  end

  return 0
end

---Get the focused node wrapper
---Returns the wrapper which delegates to the underlying entity via metatable
---@return table? Focused item wrapper with _virtual metadata and entity properties
function TreeWindow:getFocus()
  local focus_vuri = self.focus:get()
  if not focus_vuri then return nil end

  local item, _ = self:_find_in_window(focus_vuri)
  return item
end

---Subscribe to window rebuild events
---Called after _build_window completes (reactive updates, toggle, expand, etc.)
---@param fn fun() Callback function
---@return fun() Unsubscribe function
function TreeWindow:on_rebuild(fn)
  table.insert(self._on_rebuild_listeners, fn)
  return function()
    for i, listener in ipairs(self._on_rebuild_listeners) do
      if listener == fn then
        table.remove(self._on_rebuild_listeners, i)
        break
      end
    end
  end
end

---Subscribe to next rebuild only (auto-unsubscribes after first call)
---@param fn fun() Callback function
---@return fun() Unsubscribe function (can cancel before rebuild)
function TreeWindow:once_rebuild(fn)
  local unsub
  unsub = self:on_rebuild(function()
    unsub()
    fn()
  end)
  return unsub
end

-- Cleanup on dispose
function TreeWindow:on_dispose(fn)
  -- Delegate to Disposable trait
  local orig_dispose = self.dispose
  self.dispose = function(s)
    -- Stop rebuild timer
    if s._rebuild_timer then
      vim.fn.timer_stop(s._rebuild_timer)
      s._rebuild_timer = nil
    end
    -- Dispose segments
    s:_dispose_segments()
    -- Call original dispose
    if orig_dispose then
      orig_dispose(s)
    end
    -- Call cleanup callback
    if fn then fn() end
  end
end

return TreeWindow
