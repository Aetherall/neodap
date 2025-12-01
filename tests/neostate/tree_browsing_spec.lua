--[[
  Tree Browsing Simulation Tests

  This file simulates tree browsing behavior like a tree view UI:
  - Start with only root visible (everything collapsed)
  - Progressively expand nodes to reveal children
  - Use virtual URIs to expand specific paths in diamond patterns
  - Simulate lazy loading as user navigates the tree

  Run with: make test neostate
  Or: nvim --headless -u tests/helpers/minimal_init.lua -c "PlenaryBustedFile tests/neostate/tree_browsing_spec.lua"
]]

local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")

-- =============================================================================
-- Test Utilities
-- =============================================================================

local function make_entity(uri, props)
  local entity = neostate.Disposable(props or {}, nil, uri)
  entity.uri = uri
  return entity
end

local function make_collapsible(uri, props)
  local entity = make_entity(uri, props)
  entity.collapsed = neostate.Signal(true, uri .. ":collapsed") -- Start collapsed
  entity.collapsed:set_parent(entity)
  return entity
end

---Get names from collection items
local function get_names(collection)
  local names = {}
  for _, item in ipairs(collection._items) do
    table.insert(names, item.name)
  end
  return names
end

---Get virtual URIs from collection items
local function get_virtual_uris(collection)
  local uris = {}
  for _, item in ipairs(collection._items) do
    if item._virtual then
      table.insert(uris, item._virtual.uri)
    end
  end
  return uris
end

---Find item by name in collection
local function find_by_name(collection, name)
  for _, item in ipairs(collection._items) do
    if item.name == name then
      return item
    end
  end
  return nil
end

---Find item by virtual URI in collection
local function find_by_virtual_uri(collection, virtual_uri)
  for _, item in ipairs(collection._items) do
    if item._virtual and item._virtual.uri == virtual_uri then
      return item
    end
  end
  return nil
end

---Find all items matching a pattern in name
local function find_all_by_pattern(collection, pattern)
  local results = {}
  for _, item in ipairs(collection._items) do
    if item.name and item.name:match(pattern) then
      table.insert(results, item)
    end
  end
  return results
end

-- =============================================================================
-- DAP Hierarchy Generator (all nodes start collapsed)
-- =============================================================================

---Generate a DAP-like hierarchy with all nodes collapsed
---@param store table EntityStore
---@param sessions number Number of sessions
---@param threads_per_session number Threads per session
---@param frames_per_thread number Frames per thread
---@param scopes_per_frame number Scopes per frame
---@param vars_per_scope number Variables per scope
---@return table root The debugger root entity
local function generate_dap_hierarchy(store, sessions, threads_per_session, frames_per_thread, scopes_per_frame, vars_per_scope)
  -- Debugger root (not collapsed - always visible)
  local debugger = make_entity("dap:debugger", { name = "Debugger", key = "debugger" })
  store:add(debugger, "debugger")

  for s = 1, sessions do
    local session_uri = "dap:session:" .. s
    local session = make_collapsible(session_uri, {
      name = "Session " .. s,
      key = "session:" .. s,
    })
    store:add(session, "session", { { type = "child", to = "dap:debugger" } })

    for t = 1, threads_per_session do
      local thread_uri = session_uri .. "/thread:" .. t
      local thread = make_collapsible(thread_uri, {
        name = "Thread " .. t,
        key = "thread:" .. t,
      })
      thread.state = neostate.Signal("stopped", thread_uri .. ":state")
      thread.state:set_parent(thread)
      store:add(thread, "thread", { { type = "child", to = session_uri } })

      for f = 1, frames_per_thread do
        local frame_uri = thread_uri .. "/frame:" .. f
        local frame = make_collapsible(frame_uri, {
          name = "Frame " .. f,
          key = "frame:" .. f,
        })
        store:add(frame, "frame", { { type = "child", to = thread_uri } })

        for sc = 1, scopes_per_frame do
          local scope_uri = frame_uri .. "/scope:" .. sc
          local scope = make_collapsible(scope_uri, {
            name = "Scope " .. sc,
            key = "scope:" .. sc,
          })
          store:add(scope, "scope", { { type = "child", to = frame_uri } })

          for v = 1, vars_per_scope do
            local var_uri = scope_uri .. "/var:" .. v
            local var = make_collapsible(var_uri, {
              name = "var_" .. v,
              value = tostring(v * 10),
              key = "var:" .. v,
            })
            store:add(var, "variable", { { type = "child", to = scope_uri } })
          end
        end
      end
    end
  end

  return debugger
end

---Create a BFS collection with collapse/expand support
local function create_tree_view(store, root_uri)
  return store:bfs(root_uri, {
    direction = "in",
    edge_types = { "child" },
    prune = function(entity)
      return entity.collapsed and entity.collapsed:get()
    end,
    prune_watch = function(entity)
      return entity.collapsed
    end,
  })
end

-- =============================================================================
-- Tests
-- =============================================================================

describe("Tree Browsing Simulation", function()
  local store

  before_each(function()
    store = EntityStore.new("TreeBrowsingStore")
  end)

  after_each(function()
    if store then
      store:dispose()
    end
  end)

  -- ===========================================================================
  -- BASIC EXPAND/COLLAPSE
  -- ===========================================================================
  describe("Basic Expand/Collapse", function()
    it("starts with only root and direct children visible", function()
      generate_dap_hierarchy(store, 2, 3, 5, 2, 4)
      local collection = create_tree_view(store, "dap:debugger")

      -- Should see: Debugger + 2 collapsed sessions
      assert.are.equal(3, #collection._items)

      local names = get_names(collection)
      assert.is_true(vim.tbl_contains(names, "Debugger"))
      assert.is_true(vim.tbl_contains(names, "Session 1"))
      assert.is_true(vim.tbl_contains(names, "Session 2"))
    end)

    it("expanding session reveals threads", function()
      generate_dap_hierarchy(store, 2, 3, 5, 2, 4)
      local collection = create_tree_view(store, "dap:debugger")

      -- Initially: Debugger + 2 sessions
      assert.are.equal(3, #collection._items)

      -- Expand Session 1
      local session1 = find_by_name(collection, "Session 1")
      session1.collapsed:set(false)

      -- Should now see: Debugger + 2 sessions + 3 threads
      assert.are.equal(6, #collection._items)

      -- Threads should be visible
      local thread1 = find_by_name(collection, "Thread 1")
      assert.is_not_nil(thread1)
      -- filtered_parent is the URI of the parent
      assert.are.equal("dap:session:1", thread1._virtual.filtered_parent)
    end)

    it("collapsing hides all descendants", function()
      generate_dap_hierarchy(store, 1, 2, 3, 2, 2)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand everything
      for _, item in ipairs(collection._items) do
        if item.collapsed then
          item.collapsed:set(false)
        end
      end

      local expanded_count = #collection._items
      assert.is_true(expanded_count > 3) -- More than debugger + session + threads

      -- Collapse the session
      local session = find_by_name(collection, "Session 1")
      session.collapsed:set(true)

      -- Should be back to just debugger + session
      assert.are.equal(2, #collection._items)
    end)

    it("expand then collapse returns to original state", function()
      generate_dap_hierarchy(store, 2, 2, 2, 2, 2)
      local collection = create_tree_view(store, "dap:debugger")

      local initial_count = #collection._items
      local initial_names = get_names(collection)

      -- Expand Session 1
      local session1 = find_by_name(collection, "Session 1")
      session1.collapsed:set(false)

      -- Expand Thread 1
      local thread1 = find_by_name(collection, "Thread 1")
      thread1.collapsed:set(false)

      -- Now collapse Session 1 (should hide Thread 1 and all its descendants)
      session1.collapsed:set(true)

      -- Should be back to original
      assert.are.equal(initial_count, #collection._items)
      assert.are.same(initial_names, get_names(collection))
    end)
  end)

  -- ===========================================================================
  -- PROGRESSIVE TREE NAVIGATION
  -- ===========================================================================
  describe("Progressive Tree Navigation", function()
    it("simulates user drilling down: debugger -> session -> thread -> frame -> scope -> var", function()
      generate_dap_hierarchy(store, 1, 1, 2, 2, 3)
      local collection = create_tree_view(store, "dap:debugger")

      -- Level 0: Just debugger and session
      assert.are.equal(2, #collection._items)
      print("\n\tLevel 0 (initial): " .. table.concat(get_names(collection), ", "))

      -- Level 1: Expand session -> see thread
      local session = find_by_name(collection, "Session 1")
      session.collapsed:set(false)
      assert.are.equal(3, #collection._items)
      print("\tLevel 1 (session expanded): " .. table.concat(get_names(collection), ", "))

      -- Level 2: Expand thread -> see frames
      local thread = find_by_name(collection, "Thread 1")
      thread.collapsed:set(false)
      assert.are.equal(5, #collection._items) -- +2 frames
      print("\tLevel 2 (thread expanded): " .. table.concat(get_names(collection), ", "))

      -- Level 3: Expand frame 1 -> see scopes
      local frame1 = find_by_name(collection, "Frame 1")
      frame1.collapsed:set(false)
      assert.are.equal(7, #collection._items) -- +2 scopes
      print("\tLevel 3 (frame expanded): " .. table.concat(get_names(collection), ", "))

      -- Level 4: Expand scope 1 -> see variables
      local scope1 = find_by_name(collection, "Scope 1")
      scope1.collapsed:set(false)
      assert.are.equal(10, #collection._items) -- +3 vars
      print("\tLevel 4 (scope expanded): " .. table.concat(get_names(collection), ", "))

      -- Verify the full path is correct for a variable
      local var1 = find_by_name(collection, "var_1")
      assert.is_not_nil(var1)
      assert.are.equal(5, var1._virtual.filtered_depth) -- debugger/session/thread/frame/scope/var
    end)

    it("tracks filtered_path correctly during navigation", function()
      generate_dap_hierarchy(store, 1, 1, 2, 1, 2)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand down to variables
      find_by_name(collection, "Session 1").collapsed:set(false)
      find_by_name(collection, "Thread 1").collapsed:set(false)
      find_by_name(collection, "Frame 1").collapsed:set(false)
      find_by_name(collection, "Scope 1").collapsed:set(false)

      local var1 = find_by_name(collection, "var_1")
      assert.is_not_nil(var1)

      -- Check filtered_path (should include all visible ancestors)
      local filtered_path = var1._virtual.filtered_path
      assert.are.equal(5, #filtered_path) -- debugger, session, thread, frame, scope

      -- Check filtered_pathkeys
      local pathkeys = var1._virtual.filtered_pathkeys
      assert.is_true(vim.tbl_contains(pathkeys, "debugger"))
      assert.is_true(vim.tbl_contains(pathkeys, "session:1"))
      assert.is_true(vim.tbl_contains(pathkeys, "thread:1"))
      assert.is_true(vim.tbl_contains(pathkeys, "frame:1"))
      assert.is_true(vim.tbl_contains(pathkeys, "scope:1"))
    end)

    it("can expand multiple siblings independently", function()
      generate_dap_hierarchy(store, 1, 3, 2, 1, 1)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand session
      find_by_name(collection, "Session 1").collapsed:set(false)

      -- Now we see 3 threads
      local threads = find_all_by_pattern(collection, "^Thread %d$")
      assert.are.equal(3, #threads)

      -- Expand only Thread 1 and Thread 3
      find_by_name(collection, "Thread 1").collapsed:set(false)
      find_by_name(collection, "Thread 3").collapsed:set(false)

      -- Should see frames for Thread 1 and 3, but not Thread 2
      local frames = find_all_by_pattern(collection, "^Frame %d$")
      assert.are.equal(4, #frames) -- 2 frames each for Thread 1 and Thread 3

      -- Verify Thread 2 children are not visible
      local thread2_frames = {}
      for _, item in ipairs(collection._items) do
        if item._virtual and item._virtual.filtered_parent == "thread:2" then
          table.insert(thread2_frames, item)
        end
      end
      assert.are.equal(0, #thread2_frames)
    end)
  end)

  -- ===========================================================================
  -- VIRTUAL URI BASED EXPANSION
  -- ===========================================================================
  describe("Virtual URI Based Expansion", function()
    it("can find and expand by virtual URI", function()
      generate_dap_hierarchy(store, 2, 2, 2, 1, 1)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand Session 1 to get threads
      find_by_name(collection, "Session 1").collapsed:set(false)

      -- Find Thread 1 by its virtual URI (includes root key)
      local thread1 = find_by_virtual_uri(collection, "debugger/session:1/thread:1")
      assert.is_not_nil(thread1)
      assert.are.equal("Thread 1", thread1.name)

      -- Expand it
      thread1.collapsed:set(false)

      -- Verify frames appeared
      local frame1 = find_by_virtual_uri(collection, "debugger/session:1/thread:1/frame:1")
      assert.is_not_nil(frame1)
    end)

    it("virtual URIs are unique even with same entity names", function()
      generate_dap_hierarchy(store, 2, 1, 1, 1, 1)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand both sessions
      find_by_name(collection, "Session 1").collapsed:set(false)
      find_by_name(collection, "Session 2").collapsed:set(false)

      -- Both sessions have a "Thread 1" but different virtual URIs
      local threads = find_all_by_pattern(collection, "^Thread 1$")
      assert.are.equal(2, #threads)

      local virtual_uris = {}
      for _, thread in ipairs(threads) do
        table.insert(virtual_uris, thread._virtual.uri)
      end

      table.sort(virtual_uris)
      -- Virtual URIs include root key (debugger)
      assert.are.same({ "debugger/session:1/thread:1", "debugger/session:2/thread:1" }, virtual_uris)
    end)

    it("expanding via virtual URI affects only that path", function()
      generate_dap_hierarchy(store, 2, 1, 2, 1, 1)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand both sessions
      find_by_name(collection, "Session 1").collapsed:set(false)
      find_by_name(collection, "Session 2").collapsed:set(false)

      -- Expand only the thread in Session 1
      local thread_s1 = find_by_virtual_uri(collection, "debugger/session:1/thread:1")
      thread_s1.collapsed:set(false)

      -- Frames should appear under Session 1's thread
      local frame_s1 = find_by_virtual_uri(collection, "debugger/session:1/thread:1/frame:1")
      assert.is_not_nil(frame_s1)

      -- But Session 2's thread should still be collapsed (no frames visible)
      local frame_s2 = find_by_virtual_uri(collection, "debugger/session:2/thread:1/frame:1")
      assert.is_nil(frame_s2)

      -- Count total frames - should be 2 (only from Session 1)
      local frames = find_all_by_pattern(collection, "^Frame %d$")
      assert.are.equal(2, #frames)
    end)
  end)

  -- ===========================================================================
  -- PATH-SPECIFIC COLLAPSED STATE (Diamond Pattern)
  -- ===========================================================================
  describe("Path-Specific Collapsed State", function()
    --[[
      In a diamond pattern, the same entity appears via multiple paths.
      Each path instance (wrapper) should be able to have its own collapsed state.

      This requires storing collapsed state per virtual URI, not per entity.
      We use an external collapsed_map keyed by virtual URI.
    ]]

    local function create_diamond_with_children(store)
      -- Diamond: root -> A -> shared, root -> B -> shared
      -- shared has children C1, C2
      local root = make_entity("node:root", { name = "root", key = "root" })
      local nodeA = make_collapsible("node:A", { name = "A", key = "A" })
      local nodeB = make_collapsible("node:B", { name = "B", key = "B" })
      local shared = make_collapsible("node:shared", { name = "shared", key = "shared" })
      local child1 = make_entity("node:C1", { name = "C1", key = "C1" })
      local child2 = make_entity("node:C2", { name = "C2", key = "C2" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "node:root" } })
      store:add(nodeB, "node", { { type = "child", to = "node:root" } })
      store:add(shared, "node", {
        { type = "child", to = "node:A" },
        { type = "child", to = "node:B" },
      })
      store:add(child1, "node", { { type = "child", to = "node:shared" } })
      store:add(child2, "node", { { type = "child", to = "node:shared" } })

      return { root = root, A = nodeA, B = nodeB, shared = shared, C1 = child1, C2 = child2 }
    end

    it("same entity via different paths can have independent collapsed states", function()
      local nodes = create_diamond_with_children(store)

      -- External collapsed state map keyed by virtual URI
      local collapsed_map = {}

      -- Helper to build virtual URI from context + entity key
      local function build_virtual_uri(ctx, entity_key)
        if not ctx.pathkeys or #ctx.pathkeys == 0 then
          return entity_key
        end
        return table.concat(ctx.pathkeys, "/") .. "/" .. entity_key
      end

      -- Create tree view with path-specific prune and prune_watch for reactivity
      local collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity, ctx)
          -- Build virtual URI for path-specific collapsed state
          local virtual_uri = build_virtual_uri(ctx, entity.key)
          if collapsed_map[virtual_uri] then
            return true
          end
          -- Fall back to entity's own collapsed state if no path-specific state
          return entity.collapsed and entity.collapsed:get()
        end,
        prune_watch = function(entity)
          -- Need prune_watch for entity's collapsed signal to trigger reactivity
          return entity.collapsed
        end,
      })

      -- Expand A and B to see both instances of 'shared'
      nodes.A.collapsed:set(false)
      nodes.B.collapsed:set(false)

      -- Both 'shared' instances should be visible with their children
      -- root, A, B, shared(via A), shared(via B) = 5 base
      -- But shared is collapsed by default, so no children yet
      nodes.shared.collapsed:set(false) -- Expand shared (affects both paths)

      -- Now we see: root, A, B, shared(A), shared(B), C1(A), C2(A), C1(B), C2(B) = 9
      assert.are.equal(9, #collection._items)

      -- Find the two 'shared' instances by their virtual URIs
      local shared_via_A = find_by_virtual_uri(collection, "root/A/shared")
      local shared_via_B = find_by_virtual_uri(collection, "root/B/shared")
      assert.is_not_nil(shared_via_A)
      assert.is_not_nil(shared_via_B)

      -- Collapse ONLY the 'shared' via path A using path-specific state
      collapsed_map["root/A/shared"] = true

      -- Re-query to see updated state (BFS doesn't auto-update from external map)
      collection:dispose()
      collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity, ctx)
          local virtual_uri = build_virtual_uri(ctx, entity.key)
          if collapsed_map[virtual_uri] then
            return true
          end
          return entity.collapsed and entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      -- Now: root, A, B, shared(A) [collapsed], shared(B), C1(B), C2(B) = 7
      -- shared via A is pruned, so its children are hidden
      -- shared via B is still expanded
      assert.are.equal(7, #collection._items)

      -- Verify children via B are still visible
      local c1_via_B = find_by_virtual_uri(collection, "root/B/shared/C1")
      local c2_via_B = find_by_virtual_uri(collection, "root/B/shared/C2")
      assert.is_not_nil(c1_via_B)
      assert.is_not_nil(c2_via_B)

      -- Verify children via A are NOT visible
      local c1_via_A = find_by_virtual_uri(collection, "root/A/shared/C1")
      local c2_via_A = find_by_virtual_uri(collection, "root/A/shared/C2")
      assert.is_nil(c1_via_A)
      assert.is_nil(c2_via_A)
    end)

    it("path-specific state with reactive prune_watch using Signal map", function()
      local nodes = create_diamond_with_children(store)

      -- Helper to build virtual URI from context + entity key
      local function build_virtual_uri(ctx, entity_key)
        if not ctx.pathkeys or #ctx.pathkeys == 0 then
          return entity_key
        end
        return table.concat(ctx.pathkeys, "/") .. "/" .. entity_key
      end

      -- Signal-based collapsed state per virtual URI
      local collapsed_signals = {}

      local function get_collapsed_signal(virtual_uri)
        if not collapsed_signals[virtual_uri] then
          collapsed_signals[virtual_uri] = neostate.Signal(false, "collapsed:" .. virtual_uri)
        end
        return collapsed_signals[virtual_uri]
      end

      -- Pre-create the signal we'll use for path-specific collapse
      local collapsed_A = get_collapsed_signal("root/A/shared")

      -- Expand A and B first
      nodes.A.collapsed:set(false)
      nodes.B.collapsed:set(false)
      nodes.shared.collapsed:set(false)

      -- Create tree view with path-specific reactive prune
      -- Note: prune_watch only receives entity (not ctx), so we use entity's
      -- own collapsed signal for reactivity, and check path-specific signals in prune
      local collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity, ctx)
          local virtual_uri = build_virtual_uri(ctx, entity.key)
          local signal = collapsed_signals[virtual_uri]
          if signal then
            return signal:get()
          end
          return entity.collapsed and entity.collapsed:get()
        end,
        prune_watch = function(entity)
          -- prune_watch only receives entity, not ctx
          -- Return entity's collapsed signal for base reactivity
          -- Path-specific signals need to be watched separately
          return entity.collapsed
        end,
      })

      -- All expanded: 9 items
      assert.are.equal(9, #collection._items)

      -- For path-specific reactivity with external signals, we need to re-query
      -- This demonstrates the limitation: prune_watch can't watch path-specific signals
      -- because it doesn't receive path context

      -- Set collapsed signal for shared via A and re-query
      collapsed_A:set(true)

      -- Re-query to get updated state (path-specific signals aren't auto-watched)
      collection:dispose()
      collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity, ctx)
          local virtual_uri = build_virtual_uri(ctx, entity.key)
          local signal = collapsed_signals[virtual_uri]
          if signal then
            return signal:get()
          end
          return entity.collapsed and entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      -- root, A, B, shared(A)[pruned], shared(B), C1(B), C2(B) = 7
      assert.are.equal(7, #collection._items)

      -- Verify path B children still visible
      assert.is_not_nil(find_by_virtual_uri(collection, "root/B/shared/C1"))

      -- Verify path A children gone
      assert.is_nil(find_by_virtual_uri(collection, "root/A/shared/C1"))

      -- Uncollapse path A and re-query
      collapsed_A:set(false)

      collection:dispose()
      collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity, ctx)
          local virtual_uri = build_virtual_uri(ctx, entity.key)
          local signal = collapsed_signals[virtual_uri]
          if signal then
            return signal:get()
          end
          return entity.collapsed and entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      -- All 9 items should be back
      assert.are.equal(9, #collection._items)
    end)

    it("wrapper stores path-specific metadata independently", function()
      local nodes = create_diamond_with_children(store)
      nodes.A.collapsed:set(false)
      nodes.B.collapsed:set(false)
      nodes.shared.collapsed:set(false)

      local collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity)
          return entity.collapsed and entity.collapsed:get()
        end,
      })

      -- Find both 'shared' wrappers
      local shared_wrappers = find_all_by_pattern(collection, "^shared$")
      assert.are.equal(2, #shared_wrappers)

      -- Each wrapper has its own _virtual with different paths
      local paths = {}
      for _, wrapper in ipairs(shared_wrappers) do
        table.insert(paths, table.concat(wrapper._virtual.path, "/"))
      end
      table.sort(paths)

      assert.are.same({ "node:root/node:A", "node:root/node:B" }, paths)

      -- Wrappers are different objects even though they reference same entity
      assert.are_not.equal(shared_wrappers[1], shared_wrappers[2])
      assert.are_not.equal(shared_wrappers[1]._virtual, shared_wrappers[2]._virtual)

      -- But they proxy to the same underlying entity
      assert.are.equal(shared_wrappers[1].name, shared_wrappers[2].name)
      assert.are.equal(shared_wrappers[1].uri, shared_wrappers[2].uri)
    end)

    it("reactive updates using ctx.uri when entity collapsed signal changes", function()
      local nodes = create_diamond_with_children(store)

      -- Track which ctx.uri values are seen during prune evaluation
      local seen_uris = {}

      -- Create tree view that uses ctx.uri in prune function
      -- When entity.collapsed changes, prune is re-evaluated with fresh ctx.uri
      local collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity, ctx)
          -- Record that we saw this ctx.uri (for verification)
          if ctx.uri then
            seen_uris[ctx.uri] = true
          end
          -- Use entity's collapsed signal (which prune_watch can observe)
          return entity.collapsed and entity.collapsed:get()
        end,
        prune_watch = function(entity)
          -- Watch entity's collapsed signal for reactivity
          return entity.collapsed
        end,
      })

      -- Initially: root, A (collapsed), B (collapsed) = 3 items
      -- (A and B are collapsed so their children aren't visible)
      assert.are.equal(3, #collection._items)

      -- Verify ctx.uri was seen for root, A, B
      assert.is_true(seen_uris["root"])
      assert.is_true(seen_uris["root/A"])
      assert.is_true(seen_uris["root/B"])

      -- Expand A - should reactively reveal 'shared' via path A
      nodes.A.collapsed:set(false)

      -- Now: root, A, B, shared(A) = 4 items
      -- (shared is collapsed so C1/C2 not visible)
      assert.are.equal(4, #collection._items)

      -- Verify 'shared' via A path was seen
      assert.is_true(seen_uris["root/A/shared"])

      -- Find shared via A
      local shared_via_A = find_by_virtual_uri(collection, "root/A/shared")
      assert.is_not_nil(shared_via_A)
      assert.are.equal("shared", shared_via_A.name)

      -- Expand B - should reactively reveal 'shared' via path B
      nodes.B.collapsed:set(false)

      -- Now: root, A, B, shared(A), shared(B) = 5 items
      assert.are.equal(5, #collection._items)

      -- Verify 'shared' via B path was seen
      assert.is_true(seen_uris["root/B/shared"])

      -- Find shared via B
      local shared_via_B = find_by_virtual_uri(collection, "root/B/shared")
      assert.is_not_nil(shared_via_B)
      assert.are.equal("shared", shared_via_B.name)

      -- Both share the same underlying entity but have different ctx.uri
      assert.are.equal(shared_via_A.uri, shared_via_B.uri) -- Same entity URI
      assert.are_not.equal(shared_via_A._virtual.uri, shared_via_B._virtual.uri) -- Different virtual URIs

      -- Expand shared - should reactively reveal children via BOTH paths
      nodes.shared.collapsed:set(false)

      -- Now: root, A, B, shared(A), shared(B), C1(A), C2(A), C1(B), C2(B) = 9 items
      assert.are.equal(9, #collection._items)

      -- Verify children via both paths were seen
      assert.is_true(seen_uris["root/A/shared/C1"])
      assert.is_true(seen_uris["root/A/shared/C2"])
      assert.is_true(seen_uris["root/B/shared/C1"])
      assert.is_true(seen_uris["root/B/shared/C2"])

      -- Collapse shared - should reactively hide children via BOTH paths
      nodes.shared.collapsed:set(true)

      -- Back to: root, A, B, shared(A), shared(B) = 5 items
      assert.are.equal(5, #collection._items)

      -- Children should be gone
      assert.is_nil(find_by_virtual_uri(collection, "root/A/shared/C1"))
      assert.is_nil(find_by_virtual_uri(collection, "root/B/shared/C1"))

      -- Collapse A - should reactively hide shared via A path only
      nodes.A.collapsed:set(true)

      -- Now: root, A, B, shared(B) = 4 items
      assert.are.equal(4, #collection._items)

      -- shared via A should be gone, but shared via B still present
      assert.is_nil(find_by_virtual_uri(collection, "root/A/shared"))
      assert.is_not_nil(find_by_virtual_uri(collection, "root/B/shared"))

      -- Expand shared again - children only appear via B path
      nodes.shared.collapsed:set(false)

      -- Now: root, A, B, shared(B), C1(B), C2(B) = 6 items
      assert.are.equal(6, #collection._items)

      -- Children only via B path
      assert.is_not_nil(find_by_virtual_uri(collection, "root/B/shared/C1"))
      assert.is_nil(find_by_virtual_uri(collection, "root/A/shared/C1"))
    end)
  end)

  -- ===========================================================================
  -- EXPAND ALL / COLLAPSE ALL
  -- ===========================================================================
  describe("Expand All / Collapse All", function()
    it("expand all reveals entire tree", function()
      generate_dap_hierarchy(store, 1, 2, 2, 2, 2)
      local collection = create_tree_view(store, "dap:debugger")

      -- Count total entities (should match when fully expanded)
      -- 1 debugger + 1 session + 2 threads + 4 frames + 8 scopes + 16 vars = 32
      local expected_total = 1 + 1 + 2 + 4 + 8 + 16

      local initial_count = #collection._items
      assert.are.equal(2, initial_count) -- debugger + session

      -- Expand all (iteratively, as new items appear)
      local expanded = true
      while expanded do
        expanded = false
        for _, item in ipairs(collection._items) do
          if item.collapsed and item.collapsed:get() then
            item.collapsed:set(false)
            expanded = true
          end
        end
      end

      assert.are.equal(expected_total, #collection._items)
      print("\n\tFully expanded: " .. #collection._items .. " items")
    end)

    it("collapse all returns to initial state", function()
      generate_dap_hierarchy(store, 2, 2, 2, 1, 2)
      local collection = create_tree_view(store, "dap:debugger")

      local initial_count = #collection._items

      -- Expand everything
      local expanded = true
      while expanded do
        expanded = false
        for _, item in ipairs(collection._items) do
          if item.collapsed and item.collapsed:get() then
            item.collapsed:set(false)
            expanded = true
          end
        end
      end

      local expanded_count = #collection._items
      assert.is_true(expanded_count > initial_count)

      -- Collapse all sessions (top level)
      for _, item in ipairs(collection._items) do
        if item.name and item.name:match("^Session") then
          item.collapsed:set(true)
        end
      end

      -- Should be back to initial
      assert.are.equal(initial_count, #collection._items)
    end)

    it("expand to specific depth", function()
      generate_dap_hierarchy(store, 1, 2, 3, 2, 2)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand to depth 2 (show sessions and threads)
      local target_depth = 2
      for _, item in ipairs(collection._items) do
        if item._virtual and item._virtual.filtered_depth < target_depth then
          if item.collapsed then
            item.collapsed:set(false)
          end
        end
      end

      -- Should see: debugger, session, 2 threads
      assert.are.equal(4, #collection._items)

      -- No frames should be visible
      local frames = find_all_by_pattern(collection, "^Frame")
      assert.are.equal(0, #frames)
    end)
  end)

  -- ===========================================================================
  -- LAZY LOADING SIMULATION
  -- ===========================================================================
  describe("Lazy Loading Simulation", function()
    it("simulates loading children on demand", function()
      -- Start with minimal structure
      local debugger = make_entity("dap:debugger", { name = "Debugger", key = "debugger" })
      store:add(debugger, "debugger")

      local session = make_collapsible("dap:session:1", { name = "Session 1", key = "session:1" })
      store:add(session, "session", { { type = "child", to = "dap:debugger" } })

      local collection = create_tree_view(store, "dap:debugger")
      assert.are.equal(2, #collection._items)

      -- Simulate "loading" threads when session is expanded
      session.collapsed:set(false)

      -- "Load" threads dynamically
      for i = 1, 3 do
        local thread = make_collapsible("dap:session:1/thread:" .. i, {
          name = "Thread " .. i,
          key = "thread:" .. i,
        })
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
      end

      -- Threads should appear immediately due to reactivity
      assert.are.equal(5, #collection._items)

      local threads = find_all_by_pattern(collection, "^Thread")
      assert.are.equal(3, #threads)
    end)

    it("lazy load respects collapsed state", function()
      local debugger = make_entity("dap:debugger", { name = "Debugger", key = "debugger" })
      store:add(debugger, "debugger")

      local session = make_collapsible("dap:session:1", { name = "Session 1", key = "session:1" })
      store:add(session, "session", { { type = "child", to = "dap:debugger" } })

      local collection = create_tree_view(store, "dap:debugger")

      -- Session is collapsed, add threads
      for i = 1, 3 do
        local thread = make_collapsible("dap:session:1/thread:" .. i, {
          name = "Thread " .. i,
          key = "thread:" .. i,
        })
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
      end

      -- Threads should NOT appear because session is collapsed
      assert.are.equal(2, #collection._items)

      -- Expand session -> threads appear
      session.collapsed:set(false)
      assert.are.equal(5, #collection._items)
    end)

    it("dynamic children inherit correct paths", function()
      local debugger = make_entity("dap:debugger", { name = "Debugger", key = "debugger" })
      store:add(debugger, "debugger")

      local session = make_collapsible("dap:session:1", { name = "Session 1", key = "session:1" })
      session.collapsed:set(false) -- Start expanded
      store:add(session, "session", { { type = "child", to = "dap:debugger" } })

      local collection = create_tree_view(store, "dap:debugger")

      -- Add thread dynamically
      local thread = make_collapsible("dap:session:1/thread:1", {
        name = "Thread 1",
        key = "thread:1",
      })
      store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })

      local thread_item = find_by_name(collection, "Thread 1")
      assert.is_not_nil(thread_item)
      -- Virtual URI includes root key
      assert.are.equal("debugger/session:1/thread:1", thread_item._virtual.uri)
      assert.are.equal(2, thread_item._virtual.depth)
    end)
  end)

  -- ===========================================================================
  -- TREE STATE PERSISTENCE
  -- ===========================================================================
  describe("Tree State Persistence", function()
    it("expanded state survives entity updates", function()
      generate_dap_hierarchy(store, 1, 2, 2, 1, 1)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand session and first thread
      find_by_name(collection, "Session 1").collapsed:set(false)
      find_by_name(collection, "Thread 1").collapsed:set(false)

      local count_before = #collection._items

      -- Add new thread dynamically
      local new_thread = make_collapsible("dap:session:1/thread:3", {
        name = "Thread 3",
        key = "thread:3",
      })
      store:add(new_thread, "thread", { { type = "child", to = "dap:session:1" } })

      -- Count should increase by 1 (new thread)
      assert.are.equal(count_before + 1, #collection._items)

      -- Original expanded items should still be visible
      local thread1 = find_by_name(collection, "Thread 1")
      assert.is_false(thread1.collapsed:get())

      local frames = find_all_by_pattern(collection, "^Frame")
      assert.are.equal(2, #frames) -- Still 2 frames from Thread 1
    end)

    it("can record and restore expansion state", function()
      generate_dap_hierarchy(store, 1, 2, 2, 1, 1)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand some items
      find_by_name(collection, "Session 1").collapsed:set(false)
      find_by_name(collection, "Thread 1").collapsed:set(false)

      -- Record expanded virtual URIs
      local expanded_uris = {}
      for _, item in ipairs(collection._items) do
        if item.collapsed and not item.collapsed:get() then
          table.insert(expanded_uris, item._virtual.uri)
        end
      end

      -- Collapse everything
      for _, item in ipairs(collection._items) do
        if item.collapsed then
          item.collapsed:set(true)
        end
      end

      assert.are.equal(2, #collection._items)

      -- Restore expansion state
      for _, uri in ipairs(expanded_uris) do
        local item = find_by_virtual_uri(collection, uri)
        if item and item.collapsed then
          item.collapsed:set(false)
        end
      end

      -- Should have same items visible again
      local frames = find_all_by_pattern(collection, "^Frame")
      assert.are.equal(2, #frames)
    end)
  end)

  -- ===========================================================================
  -- NAVIGATION HELPERS
  -- ===========================================================================
  describe("Navigation Helpers", function()
    it("can get parent from filtered_parent", function()
      generate_dap_hierarchy(store, 1, 1, 2, 1, 1)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand to frames
      find_by_name(collection, "Session 1").collapsed:set(false)
      find_by_name(collection, "Thread 1").collapsed:set(false)

      local frame1 = find_by_name(collection, "Frame 1")
      -- filtered_parent is the full URI of the parent entity
      assert.are.equal("dap:session:1/thread:1", frame1._virtual.filtered_parent)

      -- Can navigate up using filtered_parent to find parent item
      local parent_uri = frame1._virtual.filtered_parent
      local thread = nil
      for _, item in ipairs(collection._items) do
        if item.uri == parent_uri then
          thread = item
          break
        end
      end
      assert.is_not_nil(thread)
      assert.are.equal("Thread 1", thread.name)
    end)

    it("can get all siblings at same level", function()
      generate_dap_hierarchy(store, 1, 1, 3, 1, 1)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand to show frames
      find_by_name(collection, "Session 1").collapsed:set(false)
      find_by_name(collection, "Thread 1").collapsed:set(false)

      -- Find Frame 2
      local frame2 = find_by_name(collection, "Frame 2")
      local parent_key = frame2._virtual.filtered_parent

      -- Get all items with same parent
      local siblings = {}
      for _, item in ipairs(collection._items) do
        if item._virtual and item._virtual.filtered_parent == parent_key then
          table.insert(siblings, item.name)
        end
      end

      table.sort(siblings)
      assert.are.same({ "Frame 1", "Frame 2", "Frame 3" }, siblings)
    end)

    it("can determine if item has children", function()
      generate_dap_hierarchy(store, 1, 1, 1, 1, 2)
      local collection = create_tree_view(store, "dap:debugger")

      -- Expand everything
      local expanded = true
      while expanded do
        expanded = false
        for _, item in ipairs(collection._items) do
          if item.collapsed and item.collapsed:get() then
            item.collapsed:set(false)
            expanded = true
          end
        end
      end

      -- Variables don't have children (leaf nodes)
      local var1 = find_by_name(collection, "var_1")
      assert.is_not_nil(var1)

      -- Check if any item has this var as parent
      local has_children = false
      local var1_key = var1._virtual.uri:match("var:1$") and "var:1" or var1.key
      for _, item in ipairs(collection._items) do
        if item._virtual and item._virtual.filtered_parent == var1_key then
          has_children = true
          break
        end
      end

      assert.is_false(has_children)
    end)
  end)

  -- ===========================================================================
  -- EDGE CASES
  -- ===========================================================================
  describe("Edge Cases", function()
    it("empty tree shows only root", function()
      local debugger = make_entity("dap:debugger", { name = "Debugger", key = "debugger" })
      store:add(debugger, "debugger")

      local collection = create_tree_view(store, "dap:debugger")
      assert.are.equal(1, #collection._items)
    end)

    it("single deep path", function()
      local debugger = make_entity("dap:debugger", { name = "Debugger", key = "debugger" })
      store:add(debugger, "debugger")

      -- Create single deep chain
      local prev_uri = "dap:debugger"
      for i = 1, 5 do
        local uri = "dap:level:" .. i
        local node = make_collapsible(uri, { name = "Level " .. i, key = "level:" .. i })
        store:add(node, "node", { { type = "child", to = prev_uri } })
        prev_uri = uri
      end

      local collection = create_tree_view(store, "dap:debugger")

      -- Only debugger and Level 1 visible
      assert.are.equal(2, #collection._items)

      -- Expand one by one
      for i = 1, 5 do
        local level = find_by_name(collection, "Level " .. i)
        if level and level.collapsed then
          level.collapsed:set(false)
        end
      end

      -- All 6 items visible (debugger + 5 levels)
      assert.are.equal(6, #collection._items)

      -- Deepest item should have depth 5
      local level5 = find_by_name(collection, "Level 5")
      assert.are.equal(5, level5._virtual.filtered_depth)
    end)

    it("rapid expand/collapse doesn't cause issues", function()
      generate_dap_hierarchy(store, 1, 2, 2, 1, 1)
      local collection = create_tree_view(store, "dap:debugger")

      local session = find_by_name(collection, "Session 1")

      -- Rapidly toggle
      for _ = 1, 10 do
        session.collapsed:set(false)
        session.collapsed:set(true)
      end

      -- Should be back to collapsed state
      assert.are.equal(2, #collection._items)

      -- Final expand should work
      session.collapsed:set(false)
      assert.are.equal(4, #collection._items)
    end)

    it("handles multiple collections on same store", function()
      generate_dap_hierarchy(store, 2, 2, 2, 1, 1)

      -- Create two independent tree views
      local collection1 = create_tree_view(store, "dap:debugger")
      local collection2 = create_tree_view(store, "dap:debugger")

      -- Both start the same
      assert.are.equal(#collection1._items, #collection2._items)

      -- Expand in collection1 affects both (same underlying data)
      find_by_name(collection1, "Session 1").collapsed:set(false)

      -- Both collections see the change
      assert.are.equal(#collection1._items, #collection2._items)
      assert.are.equal(5, #collection1._items) -- debugger + 2 sessions + 2 threads
    end)
  end)
end)
