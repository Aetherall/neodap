-- =============================================================================
-- Path-Aware Traversal Scenarios
-- =============================================================================
--
-- This test file covers realistic, "scenaristic" situations for path-aware
-- BFS/DFS traversal with reactivity. Unlike unit tests, these tests simulate
-- real-world usage patterns.
--
-- =============================================================================
-- SCENARIOS TO COVER:
-- =============================================================================
--
-- 1. DIAMOND PATTERNS
--    - Same entity reachable via multiple paths
--    - Collapse one path, other path remains
--    - Uncollapse restores the path
--    - Filter based on path (e.g., only show via certain ancestors)
--
-- 2. CYCLES
--    - Circular references (A -> B -> C -> A)
--    - Self-referential nodes
--    - Cycle detection prevents infinite loops
--    - Same entity appears once per unique path prefix
--
-- 3. DEEP TREES
--    - Long ancestor chains
--    - Collapse at different depths
--    - Path context accumulates correctly
--    - filtered_path tracks visible ancestors through deep hierarchy
--
-- 4. WIDE TREES
--    - Many siblings at same level
--    - Collapse/expand individual branches
--    - Order preservation across siblings
--    - Reactive additions to wide levels
--
-- 5. DAP-LIKE REACTIVE SCENARIOS
--    - Session -> Threads -> Stack Frames -> Scopes -> Variables
--    - Thread collapse/expand (prune_watch with Signal)
--    - Thread state changes (running/stopped) affecting visibility
--    - New thread appears, gets frames reactively
--    - Frame selected, scopes load lazily
--    - Variable expansion (tree within tree)
--    - Multi-session debugging (same frame type, different paths)
--
-- 6. REACTIVE EDGE OPERATIONS
--    - Add edge creates new path variants
--    - Remove edge removes affected paths
--    - Reparenting (move entity to different parent)
--
-- 7. REACTIVE ENTITY OPERATIONS
--    - Entity removal cascades to all paths containing it
--    - Entity property change triggers filter re-evaluation
--    - New entity added to existing paths
--
-- 8. SIGNAL-DRIVEN FILTER/PRUNE
--    - Filter based on Signal value
--    - Signal changes, collection updates reactively
--    - Prune based on entity's internal Signal (e.g., collapsed state)
--    - Multiple entities sharing same collapse signal
--
-- =============================================================================

local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")

-- Helper: Create a simple entity with optional properties
local function make_entity(uri, props)
  local entity = neostate.Disposable({ uri = uri }, nil, uri)
  if props then
    for k, v in pairs(props) do
      entity[k] = v
    end
  end
  return entity
end

-- Helper: Create entity with a collapse signal
local function make_collapsible(uri, props)
  local entity = make_entity(uri, props)
  entity.collapsed = neostate.Signal(false, uri .. ":collapsed")
  entity.collapsed:set_parent(entity)
  return entity
end

describe("Path-Aware Scenarios", function()
  local store

  before_each(function()
    store = EntityStore.new("TestStore")
  end)

  after_each(function()
    store:dispose()
  end)

  -- ===========================================================================
  -- 1. DIAMOND PATTERNS
  -- ===========================================================================
  describe("Diamond Patterns", function()
    --[[
        root
       /    \
      A      B
       \    /
        leaf
    ]]
    local root, nodeA, nodeB, leaf

    local function setup_diamond()
      root = make_collapsible("dap:root", { name = "root" })
      nodeA = make_collapsible("dap:A", { name = "A" })
      nodeB = make_collapsible("dap:B", { name = "B" })
      leaf = make_collapsible("dap:leaf", { name = "leaf" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:root" } })
      store:add(leaf, "node", {
        { type = "child", to = "dap:A" },
        { type = "child", to = "dap:B" },
      })
    end

    it("collapse one path in diamond, other path remains", function()
      setup_diamond()

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity)
          return entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      -- Initially: root, A, B, leaf (via A), leaf (via B) = 5 items
      -- But leaf appears twice (two paths)
      local leaf_count = 0
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          leaf_count = leaf_count + 1
        end
      end
      assert.are.equal(2, leaf_count, "leaf should appear twice (via A and via B)")

      -- Collapse A
      nodeA.collapsed:set(true)

      -- Now leaf via A should be gone, but leaf via B remains
      leaf_count = 0
      local leaf_paths = {}
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          leaf_count = leaf_count + 1
          table.insert(leaf_paths, item._virtual.path)
        end
      end
      assert.are.equal(1, leaf_count, "leaf should appear once (only via B)")
      assert.are.same({ "dap:root", "dap:B" }, leaf_paths[1])
    end)

    it("uncollapse restores the collapsed path", function()
      setup_diamond()

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity)
          return entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      -- Collapse A
      nodeA.collapsed:set(true)

      local leaf_count = 0
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then leaf_count = leaf_count + 1 end
      end
      assert.are.equal(1, leaf_count)

      -- Uncollapse A
      nodeA.collapsed:set(false)

      -- Leaf should appear twice again
      leaf_count = 0
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then leaf_count = leaf_count + 1 end
      end
      assert.are.equal(2, leaf_count, "leaf should appear twice again after uncollapse")
    end)

    it("filter by path - only show leaf via A, not via B", function()
      setup_diamond()

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        filter = function(entity, ctx)
          -- Only include leaf if path contains A
          if entity.uri == "dap:leaf" then
            for _, ancestor in ipairs(ctx.path) do
              if ancestor == "dap:A" then return true end
            end
            return false
          end
          return true
        end,
      })

      -- Find all leaves
      local leaf_items = {}
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          table.insert(leaf_items, item)
        end
      end

      assert.are.equal(1, #leaf_items, "only one leaf (via A)")
      assert.are.same({ "dap:root", "dap:A" }, leaf_items[1]._virtual.path)
    end)

    it("both paths update when leaf properties change", function()
      setup_diamond()

      -- Add a reactive property to leaf
      leaf.status = neostate.Signal("pending", "leaf:status")
      leaf.status:set_parent(leaf)

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Both leaf wrappers should see the same status via metatable
      local statuses = {}
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          table.insert(statuses, item.status:get())
        end
      end
      assert.are.same({ "pending", "pending" }, statuses)

      -- Change leaf status
      leaf.status:set("complete")

      -- Both wrappers see the update
      statuses = {}
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          table.insert(statuses, item.status:get())
        end
      end
      assert.are.same({ "complete", "complete" }, statuses)
    end)
  end)

  -- ===========================================================================
  -- 2. CYCLES
  -- ===========================================================================
  describe("Cycles", function()
    --[[
      A -> B -> C -> A (cycle)
    ]]

    it("cycle detection with path-based tracking", function()
      -- Create: A -> B -> C with C also linking back to A (cycle)
      -- With direction="in", edge "to=X" means X is the target
      -- So B->A means "B is child of A" when traversing direction="in" from A
      local nodeA = make_entity("dap:A", { name = "A" })
      local nodeB = make_entity("dap:B", { name = "B" })
      local nodeC = make_entity("dap:C", { name = "C" })

      store:add(nodeA, "node")
      store:add(nodeB, "node", { { type = "next", to = "dap:A" } })  -- B is child of A
      store:add(nodeC, "node", { { type = "next", to = "dap:B" } })  -- C is child of B
      -- Create cycle: C also links to A, making C also a direct child of A
      store:add_edge("dap:C", "next", "dap:A")

      local collection = store:bfs("dap:A", {
        direction = "in",
        edge_types = { "next" },
      })

      -- C appears twice: via A->B->C and via A->C (direct)
      -- But A should NOT reappear under C (cycle broken)
      local uris = {}
      local a_count = 0
      for _, item in ipairs(collection._items) do
        table.insert(uris, item.uri)
        if item.uri == "dap:A" then a_count = a_count + 1 end
      end

      -- A appears only once (at root), cycle is broken
      assert.are.equal(1, a_count, "A should appear only once (cycle broken)")
      -- Total: A, B, C (via B), C (via A directly) = 4 items
      assert.are.equal(4, #collection._items)
    end)

    it("same entity appears with different path prefixes before cycle", function()
      --[[
        root -> A -> shared
        root -> B -> shared -> C -> shared (cycle at C->shared)
      ]]
      local root = make_entity("dap:root")
      local nodeA = make_entity("dap:A")
      local nodeB = make_entity("dap:B")
      local shared = make_entity("dap:shared")
      local nodeC = make_entity("dap:C")

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:root" } })
      store:add(shared, "node", {
        { type = "child", to = "dap:A" },
        { type = "child", to = "dap:B" },
      })
      store:add(nodeC, "node", { { type = "child", to = "dap:shared" } })
      -- Create cycle: shared links back from C (C is parent of shared)
      store:add_edge("dap:shared", "child", "dap:C")

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- shared should appear twice (via A and via B)
      -- C should appear twice (under each shared)
      -- But shared should NOT appear again under C (cycle broken)
      local shared_count = 0
      local c_count = 0
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:shared" then shared_count = shared_count + 1 end
        if item.uri == "dap:C" then c_count = c_count + 1 end
      end

      assert.are.equal(2, shared_count, "shared appears via A and B")
      assert.are.equal(2, c_count, "C appears under both shared instances")
    end)

    it("self-referential node handled correctly", function()
      -- A -> A (self-reference)
      local nodeA = make_entity("dap:A")
      store:add(nodeA, "node")
      store:add_edge("dap:A", "self", "dap:A")

      local collection = store:bfs("dap:A", {
        direction = "in",
        edge_types = { "self" },
      })

      -- A should appear only once (self-reference broken immediately)
      assert.are.equal(1, #collection._items)
      assert.are.equal("dap:A", collection._items[1].uri)
    end)

    it("mutual reference (A -> B, B -> A) handled correctly", function()
      local nodeA = make_entity("dap:A")
      local nodeB = make_entity("dap:B")

      store:add(nodeA, "node")
      store:add(nodeB, "node", { { type = "link", to = "dap:A" } })
      store:add_edge("dap:A", "link", "dap:B")

      local collection = store:bfs("dap:A", {
        direction = "in",
        edge_types = { "link" },
      })

      -- A, then B, but A should not reappear under B
      assert.are.equal(2, #collection._items)

      local uris = {}
      for _, item in ipairs(collection._items) do
        table.insert(uris, item.uri)
      end
      assert.are.same({ "dap:A", "dap:B" }, uris)
    end)
  end)

  -- ===========================================================================
  -- 3. DEEP TREES
  -- ===========================================================================
  describe("Deep Trees", function()
    --[[
      root -> L1 -> L2 -> L3 -> L4 -> L5
    ]]
    local nodes

    local function setup_deep_tree(depth)
      nodes = {}
      for i = 0, depth do
        local name = i == 0 and "root" or ("L" .. i)
        nodes[i] = make_collapsible("dap:" .. name, { name = name, level = i })
      end

      store:add(nodes[0], "node")
      for i = 1, depth do
        store:add(nodes[i], "node", { { type = "child", to = "dap:" .. nodes[i - 1].name } })
      end
    end

    it("path accumulates correctly through deep hierarchy", function()
      setup_deep_tree(5)

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Find L5 (deepest)
      local l5 = nil
      for _, item in ipairs(collection._items) do
        if item.name == "L5" then
          l5 = item
          break
        end
      end

      assert.is_not_nil(l5)
      assert.are.equal(5, l5._virtual.depth)
      assert.are.same(
        { "dap:root", "dap:L1", "dap:L2", "dap:L3", "dap:L4" },
        l5._virtual.path
      )
    end)

    it("collapse at mid-depth removes all descendants", function()
      setup_deep_tree(5)

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity)
          return entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      -- Initially all 6 nodes
      assert.are.equal(6, #collection._items)

      -- Collapse L2
      nodes[2].collapsed:set(true)

      -- Should have root, L1, L2 only (L3, L4, L5 removed)
      local names = {}
      for _, item in ipairs(collection._items) do
        table.insert(names, item.name)
      end
      assert.are.same({ "root", "L1", "L2" }, names)
    end)

    it("filtered_path tracks only visible ancestors", function()
      setup_deep_tree(5)

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        filter = function(entity)
          -- Only show even levels (root=0, L2, L4)
          return entity.level % 2 == 0
        end,
      })

      -- Filter doesn't stop traversal, so all entities are visited
      -- but only even levels are in collection: root, L2, L4
      local names = {}
      for _, item in ipairs(collection._items) do
        table.insert(names, item.name)
      end
      assert.are.same({ "root", "L2", "L4" }, names)

      -- Find L4
      local l4 = nil
      for _, item in ipairs(collection._items) do
        if item.name == "L4" then
          l4 = item
          break
        end
      end

      assert.is_not_nil(l4)
      -- Full path includes all ancestors
      assert.are.same(
        { "dap:root", "dap:L1", "dap:L2", "dap:L3" },
        l4._virtual.path
      )
      -- Filtered path only includes visible ancestors (root, L2)
      assert.are.same(
        { "dap:root", "dap:L2" },
        l4._virtual.filtered_path
      )
    end)

    it("expand at mid-depth restores descendants reactively", function()
      setup_deep_tree(5)

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity)
          return entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      -- Collapse L2
      nodes[2].collapsed:set(true)
      assert.are.equal(3, #collection._items)

      -- Expand L2
      nodes[2].collapsed:set(false)

      -- All 6 nodes should be back
      assert.are.equal(6, #collection._items)

      -- Verify L5 is back with correct path
      local l5 = nil
      for _, item in ipairs(collection._items) do
        if item.name == "L5" then
          l5 = item
          break
        end
      end
      assert.is_not_nil(l5)
      assert.are.equal(5, l5._virtual.depth)
    end)
  end)

  -- ===========================================================================
  -- 4. WIDE TREES
  -- ===========================================================================
  describe("Wide Trees", function()
    --[[
           root
      /  /  |  \  \
     A  B   C   D  E
    ]]
    local root, siblings

    local function setup_wide_tree()
      root = make_collapsible("dap:root", { name = "root" })
      siblings = {}
      local names = { "A", "B", "C", "D", "E" }

      store:add(root, "node")
      for _, name in ipairs(names) do
        local node = make_collapsible("dap:" .. name, { name = name })
        siblings[name] = node
        store:add(node, "node", { { type = "child", to = "dap:root" } })
      end
    end

    it("all siblings appear with same parent path", function()
      setup_wide_tree()

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- All siblings should have the same path: { "dap:root" }
      for _, item in ipairs(collection._items) do
        if item.name ~= "root" then
          assert.are.same({ "dap:root" }, item._virtual.path)
          assert.are.equal("dap:root", item._virtual.parent)
          assert.are.equal(1, item._virtual.depth)
        end
      end
    end)

    it("collapse one sibling, others unaffected", function()
      setup_wide_tree()
      -- Add children to each sibling
      for name, sibling in pairs(siblings) do
        local child = make_entity("dap:" .. name .. "_child", { name = name .. "_child" })
        store:add(child, "node", { { type = "child", to = "dap:" .. name } })
      end

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity)
          return entity.collapsed and entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      -- Initially: root + 5 siblings + 5 children = 11
      assert.are.equal(11, #collection._items)

      -- Collapse sibling C
      siblings["C"].collapsed:set(true)

      -- C_child should be gone, but others remain
      -- root + 5 siblings + 4 children = 10
      assert.are.equal(10, #collection._items)

      -- Verify C_child is gone
      local has_c_child = false
      for _, item in ipairs(collection._items) do
        if item.name == "C_child" then has_c_child = true end
      end
      assert.is_false(has_c_child)

      -- Verify other children still present
      local has_a_child = false
      for _, item in ipairs(collection._items) do
        if item.name == "A_child" then has_a_child = true end
      end
      assert.is_true(has_a_child)
    end)

    it("order preserved across wide level", function()
      setup_wide_tree()

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Extract sibling names in order (excluding root)
      local sibling_names = {}
      for _, item in ipairs(collection._items) do
        if item.name ~= "root" then
          table.insert(sibling_names, item.name)
        end
      end

      -- Should be in order A, B, C, D, E (BFS order from store)
      assert.are.same({ "A", "B", "C", "D", "E" }, sibling_names)
    end)

    it("reactive addition to wide level", function()
      setup_wide_tree()

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Initially 6 items (root + 5 siblings)
      assert.are.equal(6, #collection._items)

      -- Add a new sibling F
      local nodeF = make_entity("dap:F", { name = "F" })
      store:add(nodeF, "node", { { type = "child", to = "dap:root" } })

      -- Should now have 7 items
      assert.are.equal(7, #collection._items)

      -- F should have correct path
      local f_item = nil
      for _, item in ipairs(collection._items) do
        if item.name == "F" then f_item = item end
      end
      assert.is_not_nil(f_item)
      assert.are.same({ "dap:root" }, f_item._virtual.path)
    end)
  end)

  -- ===========================================================================
  -- 5. DAP-LIKE REACTIVE SCENARIOS
  -- ===========================================================================
  describe("DAP-Like Scenarios", function()
    --[[
      Debugger
        -> Session
          -> Thread (with collapsed signal, state signal)
            -> StackFrame
              -> Scope
                -> Variable (can have children)
    ]]

    -- Helper to create DAP-like entities
    local function make_session(id)
      return make_collapsible("dap:session:" .. id, {
        name = "Session " .. id,
        key = "session:" .. id,
      })
    end

    local function make_thread(id, state)
      local thread = make_collapsible("dap:thread:" .. id, {
        name = "Thread " .. id,
        key = "thread:" .. id,
      })
      thread.state = neostate.Signal(state or "stopped", "thread:" .. id .. ":state")
      thread.state:set_parent(thread)
      return thread
    end

    local function make_frame(id, name)
      return make_collapsible("dap:frame:" .. id, {
        name = name or ("Frame " .. id),
        key = "frame:" .. id,
      })
    end

    local function make_scope(id, name)
      return make_collapsible("dap:scope:" .. id, {
        name = name or ("Scope " .. id),
        key = "scope:" .. id,
      })
    end

    local function make_variable(id, name, value)
      return make_collapsible("dap:var:" .. id, {
        name = name or ("var_" .. id),
        value = value or "undefined",
        key = "var:" .. id,
      })
    end

    describe("Thread collapse/expand", function()
      it("collapsed thread hides its stack frames", function()
        local session = make_session(1)
        local thread = make_thread(1, "stopped")
        local frame1 = make_frame(1, "main")
        local frame2 = make_frame(2, "helper")

        store:add(session, "session")
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(frame1, "frame", { { type = "child", to = "dap:thread:1" } })
        store:add(frame2, "frame", { { type = "child", to = "dap:thread:1" } })

        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
          prune = function(entity)
            return entity.collapsed:get()
          end,
          prune_watch = function(entity)
            return entity.collapsed
          end,
        })

        -- Initially: session, thread, frame1, frame2
        assert.are.equal(4, #collection._items)

        -- Collapse thread
        thread.collapsed:set(true)

        -- Frames should be gone
        assert.are.equal(2, #collection._items)
        local names = {}
        for _, item in ipairs(collection._items) do
          table.insert(names, item.name)
        end
        assert.are.same({ "Session 1", "Thread 1" }, names)
      end)

      it("expanding thread shows stack frames reactively", function()
        local session = make_session(1)
        local thread = make_thread(1, "stopped")
        thread.collapsed:set(true) -- Start collapsed
        local frame1 = make_frame(1, "main")

        store:add(session, "session")
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(frame1, "frame", { { type = "child", to = "dap:thread:1" } })

        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
          prune = function(entity)
            return entity.collapsed:get()
          end,
          prune_watch = function(entity)
            return entity.collapsed
          end,
        })

        -- Initially: session, thread (frame hidden)
        assert.are.equal(2, #collection._items)

        -- Expand thread
        thread.collapsed:set(false)

        -- Frame should appear
        assert.are.equal(3, #collection._items)
      end)

      it("collapse signal change updates collection", function()
        local session = make_session(1)
        local thread = make_thread(1, "stopped")
        local frame = make_frame(1, "main")

        store:add(session, "session")
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(frame, "frame", { { type = "child", to = "dap:thread:1" } })

        local updates = 0
        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
          prune = function(entity)
            return entity.collapsed:get()
          end,
          prune_watch = function(entity)
            return entity.collapsed
          end,
        })

        -- Track collection changes
        collection:on_removed(function()
          updates = updates + 1
        end)

        -- Collapse and uncollapse
        thread.collapsed:set(true)
        thread.collapsed:set(false)

        -- Should have triggered removals
        assert.is_true(updates > 0)
      end)
    end)

    describe("Thread state changes", function()
      it("running thread filtered out, stopped thread visible", function()
        local session = make_session(1)
        local running = make_thread(1, "running")
        local stopped = make_thread(2, "stopped")

        store:add(session, "session")
        store:add(running, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(stopped, "thread", { { type = "child", to = "dap:session:1" } })

        -- Use both filter (visibility) and prune (stop traversal) for running threads
        local function is_running_thread(entity)
          return entity.state and entity.state:get() == "running"
        end

        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
          filter = function(entity)
            return not is_running_thread(entity)
          end,
          prune = function(entity)
            return is_running_thread(entity)
          end,
        })

        -- Only session and stopped thread (running thread filtered + pruned)
        local names = {}
        for _, item in ipairs(collection._items) do
          table.insert(names, item.name)
        end
        assert.are.same({ "Session 1", "Thread 2" }, names)
      end)

      it("thread stops, becomes visible reactively", function()
        local session = make_session(1)
        local thread = make_thread(1, "running")
        local frame = make_frame(1, "main")

        store:add(session, "session")
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(frame, "frame", { { type = "child", to = "dap:thread:1" } })

        -- Use both filter (visibility) and prune (stop traversal)
        local function is_running_thread(entity)
          return entity.state and entity.state:get() == "running"
        end

        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
          filter = function(entity)
            return not is_running_thread(entity)
          end,
          filter_watch = function(entity)
            return entity.state
          end,
          prune = function(entity)
            return is_running_thread(entity)
          end,
          prune_watch = function(entity)
            return entity.state
          end,
        })

        -- Initially only session (thread is running, filtered + pruned)
        assert.are.equal(1, #collection._items)

        -- Thread stops
        thread.state:set("stopped")

        -- Thread and frame should appear
        assert.are.equal(3, #collection._items)
      end)

      it("thread resumes, becomes hidden reactively", function()
        local session = make_session(1)
        local thread = make_thread(1, "stopped")
        local frame = make_frame(1, "main")

        store:add(session, "session")
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(frame, "frame", { { type = "child", to = "dap:thread:1" } })

        -- Use both filter (visibility) and prune (stop traversal)
        local function is_running_thread(entity)
          return entity.state and entity.state:get() == "running"
        end

        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
          filter = function(entity)
            return not is_running_thread(entity)
          end,
          filter_watch = function(entity)
            return entity.state
          end,
          prune = function(entity)
            return is_running_thread(entity)
          end,
          prune_watch = function(entity)
            return entity.state
          end,
        })

        -- Initially session, thread, frame (thread is stopped)
        assert.are.equal(3, #collection._items)

        -- Thread resumes
        thread.state:set("running")

        -- Thread and frame should be hidden (filter removes thread, prune removes frame)
        assert.are.equal(1, #collection._items)
      end)
    end)

    describe("Multi-session debugging", function()
      it("same frame structure appears under different sessions", function()
        local session1 = make_session(1)
        local session2 = make_session(2)
        local thread1 = make_thread(1, "stopped")
        local thread2 = make_thread(2, "stopped")
        -- Shared frame type, different instances
        local frame1 = make_frame(1, "main")
        local frame2 = make_frame(2, "main")

        store:add(session1, "session")
        store:add(session2, "session")
        store:add(thread1, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(thread2, "thread", { { type = "child", to = "dap:session:2" } })
        store:add(frame1, "frame", { { type = "child", to = "dap:thread:1" } })
        store:add(frame2, "frame", { { type = "child", to = "dap:thread:2" } })

        -- Create root to contain both sessions
        local debugger = make_entity("dap:debugger", { name = "Debugger" })
        store:add(debugger, "debugger")
        store:add_edge("dap:session:1", "child", "dap:debugger")
        store:add_edge("dap:session:2", "child", "dap:debugger")

        local collection = store:bfs("dap:debugger", {
          direction = "in",
          edge_types = { "child" },
        })

        -- Debugger, 2 sessions, 2 threads, 2 frames = 7
        assert.are.equal(7, #collection._items)

        -- Check frame paths are different
        local frame_paths = {}
        for _, item in ipairs(collection._items) do
          if item.name == "main" then
            table.insert(frame_paths, item._virtual.path)
          end
        end
        assert.are.equal(2, #frame_paths)
        -- Paths should be different (different sessions/threads)
        assert.are_not.same(frame_paths[1], frame_paths[2])
      end)

      it("collapse thread in session 1, session 2 unaffected", function()
        local session1 = make_session(1)
        local session2 = make_session(2)
        local thread1 = make_thread(1, "stopped")
        local thread2 = make_thread(2, "stopped")
        local frame1 = make_frame(1, "main")
        local frame2 = make_frame(2, "main")

        store:add(session1, "session")
        store:add(session2, "session")
        store:add(thread1, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(thread2, "thread", { { type = "child", to = "dap:session:2" } })
        store:add(frame1, "frame", { { type = "child", to = "dap:thread:1" } })
        store:add(frame2, "frame", { { type = "child", to = "dap:thread:2" } })

        local debugger = make_entity("dap:debugger", { name = "Debugger" })
        store:add(debugger, "debugger")
        store:add_edge("dap:session:1", "child", "dap:debugger")
        store:add_edge("dap:session:2", "child", "dap:debugger")

        local collection = store:bfs("dap:debugger", {
          direction = "in",
          edge_types = { "child" },
          prune = function(entity)
            return entity.collapsed and entity.collapsed:get()
          end,
          prune_watch = function(entity)
            return entity.collapsed
          end,
        })

        assert.are.equal(7, #collection._items)

        -- Collapse thread1
        thread1.collapsed:set(true)

        -- frame1 hidden, but frame2 still visible
        assert.are.equal(6, #collection._items)

        -- Verify frame2 still present
        local has_frame2 = false
        for _, item in ipairs(collection._items) do
          if item.uri == "dap:frame:2" then has_frame2 = true end
        end
        assert.is_true(has_frame2)
      end)

      it("frame paths include session in ancestry", function()
        local session = make_session(1)
        local thread = make_thread(1, "stopped")
        local frame = make_frame(1, "main")

        store:add(session, "session")
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(frame, "frame", { { type = "child", to = "dap:thread:1" } })

        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
        })

        -- Find frame
        local frame_item = nil
        for _, item in ipairs(collection._items) do
          if item.name == "main" then frame_item = item end
        end

        assert.is_not_nil(frame_item)
        assert.are.same({ "dap:session:1", "dap:thread:1" }, frame_item._virtual.path)
        assert.are.equal("session:1/thread:1/frame:1", frame_item._virtual.uri)
      end)
    end)

    describe("Lazy loading simulation", function()
      it("scopes appear when frame is expanded", function()
        local session = make_session(1)
        local thread = make_thread(1, "stopped")
        local frame = make_frame(1, "main")
        frame.collapsed:set(true) -- Start collapsed

        store:add(session, "session")
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(frame, "frame", { { type = "child", to = "dap:thread:1" } })

        -- Scopes exist but frame is collapsed
        local locals = make_scope(1, "Locals")
        local globals = make_scope(2, "Globals")
        store:add(locals, "scope", { { type = "child", to = "dap:frame:1" } })
        store:add(globals, "scope", { { type = "child", to = "dap:frame:1" } })

        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
          prune = function(entity)
            return entity.collapsed and entity.collapsed:get()
          end,
          prune_watch = function(entity)
            return entity.collapsed
          end,
        })

        -- Scopes hidden (frame collapsed)
        assert.are.equal(3, #collection._items)

        -- Expand frame
        frame.collapsed:set(false)

        -- Scopes appear
        assert.are.equal(5, #collection._items)
      end)

      it("variables appear when scope is expanded", function()
        local session = make_session(1)
        local thread = make_thread(1, "stopped")
        local frame = make_frame(1, "main")
        local scope = make_scope(1, "Locals")
        scope.collapsed:set(true)

        store:add(session, "session")
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(frame, "frame", { { type = "child", to = "dap:thread:1" } })
        store:add(scope, "scope", { { type = "child", to = "dap:frame:1" } })

        -- Variables
        local var1 = make_variable(1, "x", "42")
        local var2 = make_variable(2, "y", "hello")
        store:add(var1, "variable", { { type = "child", to = "dap:scope:1" } })
        store:add(var2, "variable", { { type = "child", to = "dap:scope:1" } })

        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
          prune = function(entity)
            return entity.collapsed and entity.collapsed:get()
          end,
          prune_watch = function(entity)
            return entity.collapsed
          end,
        })

        -- Variables hidden
        assert.are.equal(4, #collection._items)

        -- Expand scope
        scope.collapsed:set(false)

        -- Variables appear
        assert.are.equal(6, #collection._items)
      end)

      it("nested variable expansion (tree within tree)", function()
        local session = make_session(1)
        local thread = make_thread(1, "stopped")
        local frame = make_frame(1, "main")
        local scope = make_scope(1, "Locals")

        store:add(session, "session")
        store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
        store:add(frame, "frame", { { type = "child", to = "dap:thread:1" } })
        store:add(scope, "scope", { { type = "child", to = "dap:frame:1" } })

        -- Object variable with children
        local obj = make_variable(1, "user", "{...}")
        obj.collapsed:set(true)
        local prop1 = make_variable(2, "name", '"Alice"')
        local prop2 = make_variable(3, "age", "30")

        store:add(obj, "variable", { { type = "child", to = "dap:scope:1" } })
        store:add(prop1, "variable", { { type = "child", to = "dap:var:1" } })
        store:add(prop2, "variable", { { type = "child", to = "dap:var:1" } })

        local collection = store:bfs("dap:session:1", {
          direction = "in",
          edge_types = { "child" },
          prune = function(entity)
            return entity.collapsed and entity.collapsed:get()
          end,
          prune_watch = function(entity)
            return entity.collapsed
          end,
        })

        -- Object children hidden
        assert.are.equal(5, #collection._items) -- session, thread, frame, scope, obj

        -- Expand object
        obj.collapsed:set(false)

        -- Properties appear
        assert.are.equal(7, #collection._items)

        -- Verify property paths include object
        local name_item = nil
        for _, item in ipairs(collection._items) do
          if item.name == "name" then name_item = item end
        end
        assert.is_not_nil(name_item)
        assert.are.equal(5, name_item._virtual.depth)
      end)
    end)
  end)

  -- ===========================================================================
  -- 6. REACTIVE EDGE OPERATIONS
  -- ===========================================================================
  describe("Reactive Edge Operations", function()
    it("add edge creates new path to existing entity", function()
      -- Start with: root -> A -> B
      local root = make_entity("dap:root", { name = "root" })
      local nodeA = make_entity("dap:A", { name = "A" })
      local nodeB = make_entity("dap:B", { name = "B" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:A" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Initially: root, A, B = 3 items
      assert.are.equal(3, #collection._items)

      -- Now add edge: root -> B (direct)
      store:add_edge("dap:B", "child", "dap:root")

      -- B should now appear twice (via A and directly from root)
      assert.are.equal(4, #collection._items)

      -- Collect B's paths
      local b_paths = {}
      for _, item in ipairs(collection._items) do
        if item.name == "B" then
          table.insert(b_paths, item._virtual.path)
        end
      end
      assert.are.equal(2, #b_paths)
    end)

    it("add edge to entity in diamond creates additional path variant", function()
      -- Diamond: root -> A -> leaf, root -> B -> leaf
      local root = make_entity("dap:root", { name = "root", key = "root" })
      local nodeA = make_entity("dap:A", { name = "A", key = "A" })
      local nodeB = make_entity("dap:B", { name = "B", key = "B" })
      local leaf = make_entity("dap:leaf", { name = "leaf", key = "leaf" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:root" } })
      store:add(leaf, "node", { { type = "child", to = "dap:A" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Initially: root, A, B, leaf(via A) = 4 items
      assert.are.equal(4, #collection._items)

      -- Add second path to leaf via B
      store:add_edge("dap:leaf", "child", "dap:B")

      -- Now leaf appears twice
      assert.are.equal(5, #collection._items)

      -- Verify both paths exist
      local leaf_virtual_uris = {}
      for _, item in ipairs(collection._items) do
        if item.name == "leaf" then
          table.insert(leaf_virtual_uris, item._virtual.uri)
        end
      end
      assert.are.equal(2, #leaf_virtual_uris)
      -- One should be root/A/leaf, other root/B/leaf (root is included because it has a key)
      table.sort(leaf_virtual_uris)
      assert.are.same({ "root/A/leaf", "root/B/leaf" }, leaf_virtual_uris)
    end)

    it("remove edge removes paths through that edge", function()
      -- Diamond setup
      local root = make_entity("dap:root", { name = "root", key = "root" })
      local nodeA = make_entity("dap:A", { name = "A", key = "A" })
      local nodeB = make_entity("dap:B", { name = "B", key = "B" })
      local leaf = make_entity("dap:leaf", { name = "leaf", key = "leaf" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:root" } })
      store:add(leaf, "node", {
        { type = "child", to = "dap:A" },
        { type = "child", to = "dap:B" },
      })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Diamond: root, A, B, leaf(A), leaf(B) = 5
      assert.are.equal(5, #collection._items)

      -- Remove edge A -> leaf
      store:remove_edge("dap:leaf", "child", "dap:A")

      -- Leaf via A should be gone
      assert.are.equal(4, #collection._items)

      -- Only one leaf path remains (via B)
      local leaf_paths = {}
      for _, item in ipairs(collection._items) do
        if item.name == "leaf" then
          table.insert(leaf_paths, item._virtual.path)
        end
      end
      assert.are.equal(1, #leaf_paths)
      assert.are.same({ "dap:root", "dap:B" }, leaf_paths[1])
    end)

    it("reparenting: remove old edge, add new edge", function()
      -- Initial: root -> A -> C
      --                  B (no children)
      local root = make_entity("dap:root", { name = "root", key = "root" })
      local nodeA = make_entity("dap:A", { name = "A", key = "A" })
      local nodeB = make_entity("dap:B", { name = "B", key = "B" })
      local nodeC = make_entity("dap:C", { name = "C", key = "C" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeC, "node", { { type = "child", to = "dap:A" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Initially: root, A, B, C = 4
      assert.are.equal(4, #collection._items)

      -- Find C's initial path
      local initial_c_path = nil
      for _, item in ipairs(collection._items) do
        if item.name == "C" then
          initial_c_path = item._virtual.path
        end
      end
      assert.are.same({ "dap:root", "dap:A" }, initial_c_path)

      -- Reparent C from A to B
      store:remove_edge("dap:C", "child", "dap:A")
      store:add_edge("dap:C", "child", "dap:B")

      -- Still 4 items
      assert.are.equal(4, #collection._items)

      -- C's path should now be via B
      local new_c_path = nil
      for _, item in ipairs(collection._items) do
        if item.name == "C" then
          new_c_path = item._virtual.path
        end
      end
      assert.are.same({ "dap:root", "dap:B" }, new_c_path)
    end)
  end)

  -- ===========================================================================
  -- 7. REACTIVE ENTITY OPERATIONS
  -- ===========================================================================
  describe("Reactive Entity Operations", function()
    it("entity removal cascades to all paths containing it", function()
      -- Diamond: root -> A -> leaf, root -> B -> leaf
      local root = make_entity("dap:root", { name = "root", key = "root" })
      local nodeA = make_entity("dap:A", { name = "A", key = "A" })
      local nodeB = make_entity("dap:B", { name = "B", key = "B" })
      local leaf = make_entity("dap:leaf", { name = "leaf", key = "leaf" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:root" } })
      store:add(leaf, "node", {
        { type = "child", to = "dap:A" },
        { type = "child", to = "dap:B" },
      })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Diamond: root, A, B, leaf(A), leaf(B) = 5
      assert.are.equal(5, #collection._items)

      -- Remove leaf entity entirely
      store:dispose_entity("dap:leaf")

      -- Both leaf paths should be gone
      assert.are.equal(3, #collection._items)

      -- Verify no leaf remains
      local has_leaf = false
      for _, item in ipairs(collection._items) do
        if item.name == "leaf" then has_leaf = true end
      end
      assert.is_false(has_leaf)
    end)

    it("entity in middle of path removed, descendants removed too", function()
      -- Chain: root -> A -> B -> C
      local root = make_entity("dap:root", { name = "root", key = "root" })
      local nodeA = make_entity("dap:A", { name = "A", key = "A" })
      local nodeB = make_entity("dap:B", { name = "B", key = "B" })
      local nodeC = make_entity("dap:C", { name = "C", key = "C" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:A" } })
      store:add(nodeC, "node", { { type = "child", to = "dap:B" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Initially: root, A, B, C = 4
      assert.are.equal(4, #collection._items)

      -- Remove B (middle entity)
      store:dispose_entity("dap:B")

      -- B and C (descendant) should be gone
      assert.are.equal(2, #collection._items)

      -- Only root and A remain
      local names = {}
      for _, item in ipairs(collection._items) do
        table.insert(names, item.name)
      end
      table.sort(names)
      assert.are.same({ "A", "root" }, names)
    end)

    it("new entity added, paths extend to include it", function()
      -- Initial: root -> A
      local root = make_entity("dap:root", { name = "root", key = "root" })
      local nodeA = make_entity("dap:A", { name = "A", key = "A" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Initially: root, A = 2
      assert.are.equal(2, #collection._items)

      -- Add new entity B as child of A
      local nodeB = make_entity("dap:B", { name = "B", key = "B" })
      store:add(nodeB, "node", { { type = "child", to = "dap:A" } })

      -- Now: root, A, B = 3
      assert.are.equal(3, #collection._items)

      -- B should have correct path
      local b_item = nil
      for _, item in ipairs(collection._items) do
        if item.name == "B" then b_item = item end
      end
      assert.is_not_nil(b_item)
      assert.are.same({ "dap:root", "dap:A" }, b_item._virtual.path)
      -- virtual_uri includes root because root has a key
      assert.are.equal("root/A/B", b_item._virtual.uri)
    end)
  end)

  -- ===========================================================================
  -- 8. SIGNAL-DRIVEN FILTER/PRUNE
  -- ===========================================================================
  describe("Signal-Driven Filter/Prune", function()
    it("filter based on external Signal value", function()
      -- External signal controls visibility filter
      local showHidden = neostate.Signal(false, "showHidden")

      local root = make_entity("dap:root", { name = "root" })
      local nodeA = make_entity("dap:A", { name = "A", hidden = false })
      local nodeB = make_entity("dap:B", { name = "B", hidden = true })
      local nodeC = make_entity("dap:C", { name = "C", hidden = false })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeC, "node", { { type = "child", to = "dap:root" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        filter = function(entity)
          if entity.hidden then
            return showHidden:get()
          end
          return true
        end,
        filter_watch = function()
          return showHidden
        end,
      })

      -- Hidden item B filtered out initially
      assert.are.equal(3, #collection._items) -- root, A, C

      -- Toggle showHidden
      showHidden:set(true)

      -- Now B appears
      assert.are.equal(4, #collection._items)

      -- Toggle back
      showHidden:set(false)

      -- B hidden again
      assert.are.equal(3, #collection._items)
    end)

    it("signal changes, filtered items appear/disappear", function()
      -- Entity's own state signal controls filter
      local root = make_entity("dap:root", { name = "root" })
      local nodeA = make_entity("dap:A", { name = "A" })
      nodeA.active = neostate.Signal(true, "A:active")
      nodeA.active:set_parent(nodeA)

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        filter = function(entity)
          if entity.active then
            return entity.active:get()
          end
          return true
        end,
        filter_watch = function(entity)
          return entity.active
        end,
      })

      -- Initially visible
      assert.are.equal(2, #collection._items)

      -- Deactivate
      nodeA.active:set(false)
      assert.are.equal(1, #collection._items) -- only root

      -- Reactivate
      nodeA.active:set(true)
      assert.are.equal(2, #collection._items)
    end)

    it("prune based on entity's internal collapsed Signal", function()
      -- This is similar to DAP scenarios but testing prune_watch specifically
      local root = make_entity("dap:root", { name = "root" })
      local nodeA = make_collapsible("dap:A", { name = "A" })
      local nodeB = make_entity("dap:B", { name = "B" })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:A" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity)
          return entity.collapsed and entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      -- All visible
      assert.are.equal(3, #collection._items)

      -- Collapse A
      nodeA.collapsed:set(true)

      -- B should be gone (A is pruned)
      assert.are.equal(2, #collection._items)

      -- Uncollapse
      nodeA.collapsed:set(false)

      -- B returns
      assert.are.equal(3, #collection._items)
    end)

    it("multiple entities sharing same signal update together", function()
      -- Multiple entities use same signal for filter
      local globalShow = neostate.Signal(true, "globalShow")

      local root = make_entity("dap:root", { name = "root" })
      local nodeA = make_entity("dap:A", { name = "A", usesGlobal = true })
      local nodeB = make_entity("dap:B", { name = "B", usesGlobal = true })
      local nodeC = make_entity("dap:C", { name = "C", usesGlobal = false })

      store:add(root, "node")
      store:add(nodeA, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeB, "node", { { type = "child", to = "dap:root" } })
      store:add(nodeC, "node", { { type = "child", to = "dap:root" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "child" },
        filter = function(entity)
          if entity.usesGlobal then
            return globalShow:get()
          end
          return true
        end,
        filter_watch = function(entity)
          if entity.usesGlobal then
            return globalShow
          end
          return nil
        end,
      })

      -- All visible
      assert.are.equal(4, #collection._items)

      -- Toggle global show off
      globalShow:set(false)

      -- A and B hidden, C remains
      assert.are.equal(2, #collection._items) -- root + C

      -- Verify C is still there
      local has_c = false
      for _, item in ipairs(collection._items) do
        if item.name == "C" then has_c = true end
      end
      assert.is_true(has_c)

      -- Toggle back on
      globalShow:set(true)

      -- All visible again
      assert.are.equal(4, #collection._items)
    end)
  end)
end)
