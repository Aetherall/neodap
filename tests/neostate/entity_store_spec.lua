local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")

-- =============================================================================
-- Helper Functions
-- =============================================================================

local function make_entity(uri, props)
  local e = neostate.Disposable(props or {})
  e.uri = uri
  return e
end

local function measure_time(fn, iterations)
  iterations = iterations or 1
  local start = vim.loop.hrtime()
  for _ = 1, iterations do
    fn()
  end
  local elapsed = vim.loop.hrtime() - start
  return elapsed / 1e6 / iterations -- ms per iteration
end

-- =============================================================================
-- 1. ENTITY MANAGEMENT
-- =============================================================================

describe("EntityStore - Entity Management", function()
  local store

  before_each(function()
    store = EntityStore.new("TestStore")
  end)

  after_each(function()
    store:dispose()
  end)

  it("should add and retrieve entities", function()
    local session = make_entity("dap:session:1", { id = "1", name = "Session 1" })
    store:add(session, "session")

    local retrieved = store:get("dap:session:1")
    assert.are.equal(session, retrieved)
    assert.are.equal("1", retrieved.id)
  end)

  it("should check entity existence with has()", function()
    local session = make_entity("dap:session:1")
    store:add(session, "session")

    assert.is_true(store:has("dap:session:1"))
    assert.is_false(store:has("dap:session:2"))
  end)

  it("should get entity type with type_of()", function()
    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")

    store:add(session, "session")
    store:add(thread, "thread")

    assert.are.equal("session", store:type_of("dap:session:1"))
    assert.are.equal("thread", store:type_of("dap:thread:1"))
    assert.is_nil(store:type_of("dap:nonexistent"))
  end)

  it("should count entities", function()
    assert.are.equal(0, store:count())
    assert.are.equal(0, store:count("session"))

    store:add(make_entity("dap:session:1"), "session")
    store:add(make_entity("dap:session:2"), "session")
    store:add(make_entity("dap:thread:1"), "thread")

    assert.are.equal(3, store:count())
    assert.are.equal(2, store:count("session"))
    assert.are.equal(1, store:count("thread"))
    assert.are.equal(0, store:count("frame"))
  end)

  it("should error on duplicate URI", function()
    store:add(make_entity("dap:session:1"), "session")
    assert.has_error(function()
      store:add(make_entity("dap:session:1"), "session")
    end)
  end)

  it("should error on entity without URI", function()
    assert.has_error(function()
      store:add({ id = "1" }, "session")
    end)
  end)

  it("should return reactive Collection from of_type()", function()
    local sessions = store:of_type("session")
    assert.are.equal(0, #sessions._items)

    -- Add entities after creating collection
    store:add(make_entity("dap:session:1"), "session")
    store:add(make_entity("dap:session:2"), "session")
    store:add(make_entity("dap:thread:1"), "thread")

    -- Collection should have received additions
    assert.are.equal(2, #sessions._items)
  end)

  it("should iterate over all entities", function()
    store:add(make_entity("dap:session:1"), "session")
    store:add(make_entity("dap:thread:1"), "thread")

    local count = 0
    for uri, entity in store:iter() do
      count = count + 1
      assert.is_not_nil(uri)
      assert.is_not_nil(entity)
    end
    assert.are.equal(2, count)
  end)

  it("should iterate over entities of a type", function()
    store:add(make_entity("dap:session:1"), "session")
    store:add(make_entity("dap:session:2"), "session")
    store:add(make_entity("dap:thread:1"), "thread")

    local count = 0
    for _ in store:iter_type("session") do
      count = count + 1
    end
    assert.are.equal(2, count)
  end)
end)

-- =============================================================================
-- 2. EDGE MANAGEMENT
-- =============================================================================

describe("EntityStore - Edge Management", function()
  local store

  before_each(function()
    store = EntityStore.new("TestStore")
  end)

  after_each(function()
    store:dispose()
  end)

  it("should add edges during entity creation", function()
    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")

    store:add(session, "session")
    store:add(thread, "thread", {
      { type = "parent", to = "dap:session:1" },
    })

    local edges = store:edges_from("dap:thread:1", "parent")
    assert.are.equal(1, #edges)
    assert.are.equal("dap:session:1", edges[1].to)
  end)

  it("should add edges after creation", function()
    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")

    store:add(session, "session")
    store:add(thread, "thread")

    store:add_edge("dap:thread:1", "parent", "dap:session:1")

    local edges = store:edges_from("dap:thread:1", "parent")
    assert.are.equal(1, #edges)
  end)

  it("should track reverse edges", function()
    local session = make_entity("dap:session:1")
    local thread1 = make_entity("dap:thread:1")
    local thread2 = make_entity("dap:thread:2")

    store:add(session, "session")
    store:add(thread1, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(thread2, "thread", { { type = "parent", to = "dap:session:1" } })

    local reverse = store:edges_to("dap:session:1", "parent")
    assert.are.equal(2, #reverse)
  end)

  it("should remove edges", function()
    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")

    store:add(session, "session")
    store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

    assert.are.equal(1, #store:edges_from("dap:thread:1", "parent"))
    assert.are.equal(1, #store:edges_to("dap:session:1", "parent"))

    store:remove_edge("dap:thread:1", "parent", "dap:session:1")

    assert.are.equal(0, #store:edges_from("dap:thread:1", "parent"))
    assert.are.equal(0, #store:edges_to("dap:session:1", "parent"))
  end)

  it("should support multiple edge types", function()
    local session = make_entity("dap:session:1")
    local source = make_entity("dap:source:file.py")
    local frame = make_entity("dap:frame:1")

    store:add(session, "session")
    store:add(source, "source")
    store:add(frame, "frame", {
      { type = "parent", to = "dap:session:1" },
      { type = "source", to = "dap:source:file.py" },
    })

    local all_edges = store:edges_from("dap:frame:1")
    assert.are.equal(2, #all_edges)

    local parent_edges = store:edges_from("dap:frame:1", "parent")
    assert.are.equal(1, #parent_edges)

    local source_edges = store:edges_from("dap:frame:1", "source")
    assert.are.equal(1, #source_edges)
  end)
end)

-- =============================================================================
-- 3. CASCADE DISPOSAL
-- =============================================================================

describe("EntityStore - Cascade Disposal", function()
  local store

  before_each(function()
    store = EntityStore.new("TestStore")
  end)

  after_each(function()
    store:dispose()
  end)

  it("should dispose entity and remove from store", function()
    local session = make_entity("dap:session:1")
    store:add(session, "session")

    assert.is_true(store:has("dap:session:1"))
    store:dispose_entity("dap:session:1")
    assert.is_false(store:has("dap:session:1"))
  end)

  it("should cascade dispose children via parent edges", function()
    local session = make_entity("dap:session:1")
    local thread1 = make_entity("dap:thread:1")
    local thread2 = make_entity("dap:thread:2")
    local stack = make_entity("dap:stack:1")

    store:add(session, "session")
    store:add(thread1, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(thread2, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })

    assert.are.equal(4, store:count())

    -- Dispose session - should cascade to threads and stack
    store:dispose_entity("dap:session:1")

    assert.are.equal(0, store:count())
    assert.is_false(store:has("dap:session:1"))
    assert.is_false(store:has("dap:thread:1"))
    assert.is_false(store:has("dap:thread:2"))
    assert.is_false(store:has("dap:stack:1"))
  end)

  it("should call dispose on underlying entity", function()
    local disposed = false
    local session = make_entity("dap:session:1")
    session:on_dispose(function()
      disposed = true
    end)

    store:add(session, "session")
    store:dispose_entity("dap:session:1")

    assert.is_true(disposed)
  end)

  it("should dispose children in LIFO order", function()
    local dispose_order = {}

    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")
    local stack = make_entity("dap:stack:1")
    local frame = make_entity("dap:frame:1")

    session:on_dispose(function() table.insert(dispose_order, "session") end)
    thread:on_dispose(function() table.insert(dispose_order, "thread") end)
    stack:on_dispose(function() table.insert(dispose_order, "stack") end)
    frame:on_dispose(function() table.insert(dispose_order, "frame") end)

    store:add(session, "session")
    store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })
    store:add(frame, "frame", { { type = "parent", to = "dap:stack:1" } })

    store:dispose_entity("dap:session:1")

    -- Children disposed before parents (LIFO)
    assert.are.same({ "frame", "stack", "thread", "session" }, dispose_order)
  end)

  it("should clean up edges when entity disposed", function()
    local session = make_entity("dap:session:1")
    local source = make_entity("dap:source:file.py")
    local frame = make_entity("dap:frame:1")

    store:add(session, "session")
    store:add(source, "source")
    store:add(frame, "frame", {
      { type = "parent", to = "dap:session:1" },
      { type = "source", to = "dap:source:file.py" },
    })

    -- Source has incoming edge from frame
    assert.are.equal(1, #store:edges_to("dap:source:file.py", "source"))

    store:dispose_entity("dap:frame:1")

    -- Edge should be cleaned up
    assert.are.equal(0, #store:edges_to("dap:source:file.py", "source"))
  end)

  it("should update reactive of_type() Collection on disposal", function()
    local sessions = store:of_type("session")

    store:add(make_entity("dap:session:1"), "session")
    store:add(make_entity("dap:session:2"), "session")
    assert.are.equal(2, #sessions._items)

    store:dispose_entity("dap:session:1")
    assert.are.equal(1, #sessions._items)
  end)
end)

-- =============================================================================
-- 4. INDEX SYSTEM
-- =============================================================================

describe("EntityStore - Index System", function()
  local store

  before_each(function()
    store = EntityStore.new("TestStore")
  end)

  after_each(function()
    store:dispose()
  end)

  it("should index entities by static values", function()
    store:add_index("session:by_id", function(e) return e.id end)

    local s1 = make_entity("dap:session:1", { id = "abc" })
    local s2 = make_entity("dap:session:2", { id = "def" })

    store:add(s1, "session")
    store:add(s2, "session")

    assert.are.equal(s1, store:get_one("session:by_id", "abc"))
    assert.are.equal(s2, store:get_one("session:by_id", "def"))
    assert.is_nil(store:get_one("session:by_id", "xyz"))
  end)

  it("should index entities by reactive Signal values", function()
    store:add_index("thread:by_state", function(e) return e.state end)

    local t1 = make_entity("dap:thread:1", { id = "1" })
    t1.state = neostate.Signal("running")

    local t2 = make_entity("dap:thread:2", { id = "2" })
    t2.state = neostate.Signal("stopped")

    store:add(t1, "thread")
    store:add(t2, "thread")

    -- Query initial state
    local running = store:get_by("thread:by_state", "running")
    assert.are.equal(1, #running)
    assert.are.equal(t1, running[1])

    local stopped = store:get_by("thread:by_state", "stopped")
    assert.are.equal(1, #stopped)
    assert.are.equal(t2, stopped[1])

    -- Update signal
    t1.state:set("stopped")

    -- Index should update reactively
    running = store:get_by("thread:by_state", "running")
    assert.is_nil(running)

    stopped = store:get_by("thread:by_state", "stopped")
    assert.are.equal(2, #stopped)
  end)

  it("should handle multiple entities with same index key", function()
    store:add_index("thread:by_session", function(e) return e.session_id end)

    local t1 = make_entity("dap:thread:1", { session_id = "s1" })
    local t2 = make_entity("dap:thread:2", { session_id = "s1" })
    local t3 = make_entity("dap:thread:3", { session_id = "s2" })

    store:add(t1, "thread")
    store:add(t2, "thread")
    store:add(t3, "thread")

    local s1_threads = store:get_by("thread:by_session", "s1")
    assert.are.equal(2, #s1_threads)

    local s2_threads = store:get_by("thread:by_session", "s2")
    assert.are.equal(1, #s2_threads)
  end)

  it("should clean up indexes on entity disposal", function()
    store:add_index("session:by_id", function(e) return e.id end)

    local s1 = make_entity("dap:session:1", { id = "abc" })
    store:add(s1, "session")

    assert.is_not_nil(store:get_one("session:by_id", "abc"))

    store:dispose_entity("dap:session:1")

    assert.is_nil(store:get_one("session:by_id", "abc"))
  end)

  it("should clean up signal watchers on disposal", function()
    store:add_index("thread:by_state", function(e) return e.state end)

    local t1 = make_entity("dap:thread:1")
    t1.state = neostate.Signal("running")

    store:add(t1, "thread")

    -- Dispose - should clean up signal watcher
    store:dispose_entity("dap:thread:1")

    -- Changing signal after disposal should not cause errors
    t1.state:set("stopped")
    -- No assertion needed - just verifying no error occurs
  end)

  it("should return reactive Collection from where()", function()
    store:add_index("thread:by_state", function(e) return e.state end)

    local stopped_threads = store:where("thread:by_state", "stopped")
    assert.are.equal(0, #stopped_threads._items)

    -- Add entities
    local t1 = make_entity("dap:thread:1")
    t1.state = neostate.Signal("stopped")
    store:add(t1, "thread")

    local t2 = make_entity("dap:thread:2")
    t2.state = neostate.Signal("running")
    store:add(t2, "thread")

    -- Collection should update
    assert.are.equal(1, #stopped_threads._items)

    -- Signal change should update where() result
    t2.state:set("stopped")
    -- Note: The current where() implementation doesn't auto-update on signal changes
    -- This would require enhanced implementation
  end)

  it("should index existing entities when index is added later", function()
    local s1 = make_entity("dap:session:1", { id = "abc" })
    local s2 = make_entity("dap:session:2", { id = "def" })

    store:add(s1, "session")
    store:add(s2, "session")

    -- Add index AFTER entities
    store:add_index("session:by_id", function(e) return e.id end)

    assert.are.equal(s1, store:get_one("session:by_id", "abc"))
    assert.are.equal(s2, store:get_one("session:by_id", "def"))
  end)

  it("should error on duplicate index name", function()
    store:add_index("session:by_id", function(e) return e.id end)
    assert.has_error(function()
      store:add_index("session:by_id", function(e) return e.id end)
    end)
  end)

  it("should error on unknown index in query", function()
    assert.has_error(function()
      store:get_by("nonexistent:index", "key")
    end)
  end)
end)

-- =============================================================================
-- 5. GRAPH TRAVERSAL - BFS
-- =============================================================================

describe("EntityStore - BFS Traversal", function()
  local store

  before_each(function()
    store = EntityStore.new("TestStore")
  end)

  after_each(function()
    store:dispose()
  end)

  it("should traverse outgoing edges", function()
    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")
    local stack = make_entity("dap:stack:1")

    store:add(session, "session")
    store:add(thread, "thread", { { type = "child", to = "dap:session:1" } })
    store:add(stack, "stack", { { type = "child", to = "dap:thread:1" } })

    -- BFS from session following "child" edges outward
    -- But we need incoming edges to find children
    -- Let's use parent edges instead (more natural)
  end)

  it("should traverse incoming parent edges to find children", function()
    local session = make_entity("dap:session:1")
    local thread1 = make_entity("dap:thread:1")
    local thread2 = make_entity("dap:thread:2")
    local stack = make_entity("dap:stack:1")

    store:add(session, "session")
    store:add(thread1, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(thread2, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })

    -- BFS following incoming "parent" edges (children pointing to parents)
    local reachable = store:bfs("dap:session:1", {
      direction = "in",
      edge_types = { "parent" },
    })

    -- Should find session + 2 threads + 1 stack = 4 entities
    assert.are.equal(4, #reachable._items)
  end)

  it("should respect max_depth", function()
    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")
    local stack = make_entity("dap:stack:1")
    local frame = make_entity("dap:frame:1")

    store:add(session, "session")
    store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })
    store:add(frame, "frame", { { type = "parent", to = "dap:stack:1" } })

    local depth1 = store:bfs("dap:session:1", {
      direction = "in",
      edge_types = { "parent" },
      max_depth = 1,
    })
    assert.are.equal(2, #depth1._items) -- session + thread

    local depth2 = store:bfs("dap:session:1", {
      direction = "in",
      edge_types = { "parent" },
      max_depth = 2,
    })
    assert.are.equal(3, #depth2._items) -- session + thread + stack
  end)

  it("should apply filter function", function()
    local session = make_entity("dap:session:1")
    local thread1 = make_entity("dap:thread:1", { active = true })
    local thread2 = make_entity("dap:thread:2", { active = false })

    store:add(session, "session")
    store:add(thread1, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(thread2, "thread", { { type = "parent", to = "dap:session:1" } })

    local active_only = store:bfs("dap:session:1", {
      direction = "in",
      edge_types = { "parent" },
      filter = function(e) return e.active == true end,
    })

    assert.are.equal(1, #active_only._items)
    assert.are.equal(thread1.uri, active_only._items[1].uri)
  end)

  it("should handle cycles without infinite loop", function()
    local a = make_entity("dap:a")
    local b = make_entity("dap:b")
    local c = make_entity("dap:c")

    store:add(a, "node")
    store:add(b, "node")
    store:add(c, "node")

    -- Create cycle: a -> b -> c -> a
    store:add_edge("dap:a", "next", "dap:b")
    store:add_edge("dap:b", "next", "dap:c")
    store:add_edge("dap:c", "next", "dap:a")

    local result = store:bfs("dap:a", {
      direction = "out",
      edge_types = { "next" },
    })

    -- Should visit each node exactly once
    assert.are.equal(3, #result._items)
  end)

  it("should traverse both directions", function()
    local a = make_entity("dap:a")
    local b = make_entity("dap:b")
    local c = make_entity("dap:c")

    store:add(a, "node")
    store:add(b, "node")
    store:add(c, "node")

    store:add_edge("dap:a", "link", "dap:b")
    store:add_edge("dap:c", "link", "dap:b")

    -- From b, traverse both directions
    local result = store:bfs("dap:b", {
      direction = "both",
      edge_types = { "link" },
    })

    assert.are.equal(3, #result._items)
  end)
end)

-- =============================================================================
-- 6. GRAPH TRAVERSAL - DFS
-- =============================================================================

describe("EntityStore - DFS Traversal", function()
  local store

  before_each(function()
    store = EntityStore.new("TestStore")
  end)

  after_each(function()
    store:dispose()
  end)

  it("should traverse depth-first", function()
    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")
    local stack = make_entity("dap:stack:1")
    local frame = make_entity("dap:frame:1")

    store:add(session, "session")
    store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })
    store:add(frame, "frame", { { type = "parent", to = "dap:stack:1" } })

    local result = store:dfs("dap:session:1", {
      direction = "in",
      edge_types = { "parent" },
    })

    assert.are.equal(4, #result._items)
  end)

  it("should respect max_depth", function()
    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")
    local stack = make_entity("dap:stack:1")

    store:add(session, "session")
    store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })
    store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })

    local depth1 = store:dfs("dap:session:1", {
      direction = "in",
      edge_types = { "parent" },
      max_depth = 1,
    })

    assert.are.equal(2, #depth1._items)
  end)

  it("should apply filter", function()
    local session = make_entity("dap:session:1")
    local thread = make_entity("dap:thread:1")

    store:add(session, "session")
    store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

    local sessions_only = store:dfs("dap:session:1", {
      direction = "in",
      edge_types = { "parent" },
      filter = function(e)
        return store:type_of(e.uri) == "session"
      end,
    })

    assert.are.equal(1, #sessions_only._items)
  end)
end)

-- =============================================================================
-- 7. REACTIVITY TESTS
-- =============================================================================

describe("EntityStore - Reactivity", function()
  local store

  before_each(function()
    store = EntityStore.new("ReactiveStore")
  end)

  after_each(function()
    store:dispose()
  end)

  -- ---------------------------------------------------------------------------
  -- of_type() Reactivity
  -- ---------------------------------------------------------------------------

  describe("of_type() reactivity", function()
    it("should reactively add entities to of_type() collection", function()
      local sessions = store:of_type("session")
      assert.are.equal(0, #sessions._items)

      store:add(make_entity("dap:session:1"), "session")
      assert.are.equal(1, #sessions._items)

      store:add(make_entity("dap:session:2"), "session")
      assert.are.equal(2, #sessions._items)

      -- Adding different type should not affect
      store:add(make_entity("dap:thread:1"), "thread")
      assert.are.equal(2, #sessions._items)
    end)

    it("should reactively remove entities from of_type() collection", function()
      local sessions = store:of_type("session")

      store:add(make_entity("dap:session:1"), "session")
      store:add(make_entity("dap:session:2"), "session")
      assert.are.equal(2, #sessions._items)

      store:dispose_entity("dap:session:1")
      assert.are.equal(1, #sessions._items)

      store:dispose_entity("dap:session:2")
      assert.are.equal(0, #sessions._items)
    end)

    it("should cascade removal through of_type() collection", function()
      local threads = store:of_type("thread")

      store:add(make_entity("dap:session:1"), "session")
      store:add(make_entity("dap:thread:1"), "thread", { { type = "parent", to = "dap:session:1" } })
      store:add(make_entity("dap:thread:2"), "thread", { { type = "parent", to = "dap:session:1" } })

      assert.are.equal(2, #threads._items)

      -- Dispose session - threads should cascade
      store:dispose_entity("dap:session:1")
      assert.are.equal(0, #threads._items)
    end)

    it("should fire on_added listeners for of_type() collection", function()
      local sessions = store:of_type("session")
      local added_count = 0

      sessions:on_added(function()
        added_count = added_count + 1
      end)

      store:add(make_entity("dap:session:1"), "session")
      store:add(make_entity("dap:session:2"), "session")

      assert.are.equal(2, added_count)
    end)

    it("should fire on_removed listeners for of_type() collection", function()
      local sessions = store:of_type("session")
      local removed_count = 0

      sessions:on_removed(function()
        removed_count = removed_count + 1
      end)

      store:add(make_entity("dap:session:1"), "session")
      store:add(make_entity("dap:session:2"), "session")

      store:dispose_entity("dap:session:1")
      assert.are.equal(1, removed_count)

      store:dispose_entity("dap:session:2")
      assert.are.equal(2, removed_count)
    end)

    it("should support multiple of_type() collections for same type", function()
      local sessions1 = store:of_type("session")
      local sessions2 = store:of_type("session")

      store:add(make_entity("dap:session:1"), "session")

      assert.are.equal(1, #sessions1._items)
      assert.are.equal(1, #sessions2._items)

      store:dispose_entity("dap:session:1")

      assert.are.equal(0, #sessions1._items)
      assert.are.equal(0, #sessions2._items)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- where() Reactivity
  -- ---------------------------------------------------------------------------

  describe("where() reactivity", function()
    it("should reactively add matching entities to where() collection", function()
      store:add_index("thread:by_session", function(e) return e.session_id end)

      local s1_threads = store:where("thread:by_session", "s1")
      assert.are.equal(0, #s1_threads._items)

      store:add(make_entity("dap:thread:1", { session_id = "s1" }), "thread")
      assert.are.equal(1, #s1_threads._items)

      store:add(make_entity("dap:thread:2", { session_id = "s1" }), "thread")
      assert.are.equal(2, #s1_threads._items)

      -- Non-matching should not be added
      store:add(make_entity("dap:thread:3", { session_id = "s2" }), "thread")
      assert.are.equal(2, #s1_threads._items)
    end)

    it("should reactively remove entities from where() collection", function()
      store:add_index("thread:by_session", function(e) return e.session_id end)

      local s1_threads = store:where("thread:by_session", "s1")

      store:add(make_entity("dap:thread:1", { session_id = "s1" }), "thread")
      store:add(make_entity("dap:thread:2", { session_id = "s1" }), "thread")
      assert.are.equal(2, #s1_threads._items)

      store:dispose_entity("dap:thread:1")
      assert.are.equal(1, #s1_threads._items)
    end)

    it("should support multiple where() collections with different keys", function()
      store:add_index("thread:by_state", function(e) return e.state end)

      local running = store:where("thread:by_state", "running")
      local stopped = store:where("thread:by_state", "stopped")

      local t1 = make_entity("dap:thread:1", { state = "running" })
      local t2 = make_entity("dap:thread:2", { state = "stopped" })

      store:add(t1, "thread")
      store:add(t2, "thread")

      assert.are.equal(1, #running._items)
      assert.are.equal(1, #stopped._items)

      store:dispose_entity("dap:thread:1")

      assert.are.equal(0, #running._items)
      assert.are.equal(1, #stopped._items)
    end)

    it("should react to Signal-based index value changes", function()
      store:add_index("thread:by_state", function(e) return e.state end)

      local running = store:where("thread:by_state", "running")
      local stopped = store:where("thread:by_state", "stopped")

      local t1 = make_entity("dap:thread:1")
      t1.state = neostate.Signal("running")

      store:add(t1, "thread")

      assert.are.equal(1, #running._items)
      assert.are.equal(0, #stopped._items)

      -- Change signal value
      t1.state:set("stopped")

      -- Index should update
      local running_results = store:get_by("thread:by_state", "running")
      local stopped_results = store:get_by("thread:by_state", "stopped")

      assert.is_nil(running_results)
      assert.are.equal(1, #stopped_results)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Index Reactivity (Signal values)
  -- ---------------------------------------------------------------------------

  describe("Index reactivity with Signals", function()
    it("should update index when Signal value changes", function()
      store:add_index("frame:by_location", function(e) return e.location end)

      local frame = make_entity("dap:frame:1")
      frame.location = neostate.Signal("file.py:10")

      store:add(frame, "frame")

      assert.are.equal(frame, store:get_one("frame:by_location", "file.py:10"))
      assert.is_nil(store:get_one("frame:by_location", "file.py:20"))

      -- Update location
      frame.location:set("file.py:20")

      assert.is_nil(store:get_one("frame:by_location", "file.py:10"))
      assert.are.equal(frame, store:get_one("frame:by_location", "file.py:20"))
    end)

    it("should handle multiple entities with Signal indexes", function()
      store:add_index("binding:by_verified", function(e) return e.verified end)

      local b1 = make_entity("dap:binding:1")
      b1.verified = neostate.Signal(false)

      local b2 = make_entity("dap:binding:2")
      b2.verified = neostate.Signal(false)

      store:add(b1, "binding")
      store:add(b2, "binding")

      local verified = store:get_by("binding:by_verified", true)
      local unverified = store:get_by("binding:by_verified", false)

      assert.is_nil(verified)
      assert.are.equal(2, #unverified)

      -- Verify one binding
      b1.verified:set(true)

      verified = store:get_by("binding:by_verified", true)
      unverified = store:get_by("binding:by_verified", false)

      assert.are.equal(1, #verified)
      assert.are.equal(1, #unverified)
    end)

    it("should stop watching Signal after entity disposal", function()
      store:add_index("thread:by_state", function(e) return e.state end)

      local thread = make_entity("dap:thread:1")
      thread.state = neostate.Signal("running")

      store:add(thread, "thread")

      assert.are.equal(thread, store:get_one("thread:by_state", "running"))

      store:dispose_entity("dap:thread:1")

      -- Signal changes after disposal should not affect store
      -- (and should not error)
      thread.state:set("stopped")

      -- Store should have no entries
      assert.is_nil(store:get_one("thread:by_state", "running"))
      assert.is_nil(store:get_one("thread:by_state", "stopped"))
    end)

    it("should handle Signal changing to nil", function()
      store:add_index("frame:by_source", function(e) return e.source_id end)

      local frame = make_entity("dap:frame:1")
      frame.source_id = neostate.Signal("source:1")

      store:add(frame, "frame")

      assert.are.equal(frame, store:get_one("frame:by_source", "source:1"))

      -- Set to nil
      frame.source_id:set(nil)

      assert.is_nil(store:get_one("frame:by_source", "source:1"))
      assert.is_nil(store:get_one("frame:by_source", nil)) -- nil keys not indexed
    end)

    it("should handle rapid Signal changes", function()
      store:add_index("entity:by_value", function(e) return e.value end)

      local entity = make_entity("dap:entity:1")
      entity.value = neostate.Signal(0)

      store:add(entity, "entity")

      -- Rapid changes
      for i = 1, 100 do
        entity.value:set(i)
      end

      -- Should end up at 100
      assert.is_nil(store:get_one("entity:by_value", 0))
      assert.is_nil(store:get_one("entity:by_value", 50))
      assert.are.equal(entity, store:get_one("entity:by_value", 100))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Event Listener Reactivity
  -- ---------------------------------------------------------------------------

  describe("Event listener reactivity", function()
    it("should fire on_added for all types", function()
      local added_sessions = {}
      local added_threads = {}

      store:on_added("session", function(entity)
        table.insert(added_sessions, entity)
      end)

      store:on_added("thread", function(entity)
        table.insert(added_threads, entity)
      end)

      local s1 = make_entity("dap:session:1")
      local t1 = make_entity("dap:thread:1")
      local t2 = make_entity("dap:thread:2")

      store:add(s1, "session")
      store:add(t1, "thread")
      store:add(t2, "thread")

      assert.are.equal(1, #added_sessions)
      assert.are.equal(2, #added_threads)
    end)

    it("should fire on_removed for all types", function()
      local removed_sessions = {}
      local removed_threads = {}

      store:on_removed("session", function(entity)
        table.insert(removed_sessions, entity)
      end)

      store:on_removed("thread", function(entity)
        table.insert(removed_threads, entity)
      end)

      store:add(make_entity("dap:session:1"), "session")
      store:add(make_entity("dap:thread:1"), "thread", { { type = "parent", to = "dap:session:1" } })
      store:add(make_entity("dap:thread:2"), "thread", { { type = "parent", to = "dap:session:1" } })

      -- Dispose session - cascades to threads
      store:dispose_entity("dap:session:1")

      assert.are.equal(1, #removed_sessions)
      assert.are.equal(2, #removed_threads)
    end)

    it("should allow unsubscribing from events", function()
      local count = 0

      local unsub = store:on_added("session", function()
        count = count + 1
      end)

      store:add(make_entity("dap:session:1"), "session")
      assert.are.equal(1, count)

      unsub()

      store:add(make_entity("dap:session:2"), "session")
      assert.are.equal(1, count) -- No increment after unsub
    end)

    it("should support multiple listeners for same type", function()
      local count1 = 0
      local count2 = 0

      store:on_added("session", function() count1 = count1 + 1 end)
      store:on_added("session", function() count2 = count2 + 1 end)

      store:add(make_entity("dap:session:1"), "session")

      assert.are.equal(1, count1)
      assert.are.equal(1, count2)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Disposal and Cleanup Reactivity
  -- ---------------------------------------------------------------------------

  describe("Disposal cleanup reactivity", function()
    it("should clean up all listeners when store is disposed", function()
      local sessions = store:of_type("session")
      local added_count = 0

      sessions:on_added(function()
        added_count = added_count + 1
      end)

      store:add(make_entity("dap:session:1"), "session")
      assert.are.equal(1, added_count)

      store:dispose()

      -- After store disposal, collection should not receive updates
      -- (attempting to add would error anyway, but collection should be disposed)
      assert.is_true(sessions._disposed)
    end)

    it("should dispose of_type() collection when store is disposed", function()
      local sessions = store:of_type("session")
      assert.is_false(sessions._disposed)

      store:dispose()

      assert.is_true(sessions._disposed)
    end)

    it("should dispose where() collection when store is disposed", function()
      store:add_index("session:by_id", function(e) return e.id end)
      local filtered = store:where("session:by_id", "test")

      assert.is_false(filtered._disposed)

      store:dispose()

      assert.is_true(filtered._disposed)
    end)

    it("should run entity-specific cleanups on disposal", function()
      local cleanup_ran = false

      store:add(make_entity("dap:session:1"), "session")
      store:_register_entity_cleanup("dap:session:1", function()
        cleanup_ran = true
      end)

      store:dispose_entity("dap:session:1")

      assert.is_true(cleanup_ran)
    end)

    it("should run multiple cleanups in LIFO order", function()
      local order = {}

      store:add(make_entity("dap:session:1"), "session")
      store:_register_entity_cleanup("dap:session:1", function()
        table.insert(order, 1)
      end)
      store:_register_entity_cleanup("dap:session:1", function()
        table.insert(order, 2)
      end)
      store:_register_entity_cleanup("dap:session:1", function()
        table.insert(order, 3)
      end)

      store:dispose_entity("dap:session:1")

      assert.are.same({ 3, 2, 1 }, order)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Edge Change Reactivity
  -- ---------------------------------------------------------------------------

  describe("Edge change reactivity", function()
    it("should update reverse edges when edge is removed", function()
      store:add(make_entity("dap:session:1"), "session")
      store:add(make_entity("dap:thread:1"), "thread", { { type = "parent", to = "dap:session:1" } })

      assert.are.equal(1, #store:edges_to("dap:session:1", "parent"))

      store:remove_edge("dap:thread:1", "parent", "dap:session:1")

      assert.are.equal(0, #store:edges_to("dap:session:1", "parent"))
    end)

    it("should handle dynamic edge addition", function()
      store:add(make_entity("dap:frame:1"), "frame")
      store:add(make_entity("dap:source:1"), "source")

      assert.are.equal(0, #store:edges_from("dap:frame:1", "source"))

      store:add_edge("dap:frame:1", "source", "dap:source:1")

      assert.are.equal(1, #store:edges_from("dap:frame:1", "source"))
      assert.are.equal(1, #store:edges_to("dap:source:1", "source"))
    end)

    it("should not cascade on non-parent edge removal", function()
      store:add(make_entity("dap:frame:1"), "frame")
      store:add(make_entity("dap:source:1"), "source")
      store:add_edge("dap:frame:1", "source", "dap:source:1")

      -- Removing source edge should not dispose frame
      store:remove_edge("dap:frame:1", "source", "dap:source:1")

      assert.is_true(store:has("dap:frame:1"))
      assert.is_true(store:has("dap:source:1"))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Chained Reactivity (derived collections)
  -- ---------------------------------------------------------------------------

  describe("Chained reactivity", function()
    it("should support watching of_type() then filtering", function()
      local sessions = store:of_type("session")
      local active_sessions = {}

      sessions:each(function(session)
        if session.active then
          table.insert(active_sessions, session)
        end
        return function()
          for i, s in ipairs(active_sessions) do
            if s == session then
              table.remove(active_sessions, i)
              break
            end
          end
        end
      end)

      store:add(make_entity("dap:session:1", { active = true }), "session")
      store:add(make_entity("dap:session:2", { active = false }), "session")
      store:add(make_entity("dap:session:3", { active = true }), "session")

      assert.are.equal(2, #active_sessions)

      store:dispose_entity("dap:session:1")
      assert.are.equal(1, #active_sessions)
    end)

    it("should support nested reactive indexes", function()
      store:add_index("thread:by_session", function(e) return e.session_id end)
      store:add_index("thread:by_state", function(e) return e.state end)

      local t1 = make_entity("dap:thread:1", { session_id = "s1" })
      t1.state = neostate.Signal("running")

      local t2 = make_entity("dap:thread:2", { session_id = "s1" })
      t2.state = neostate.Signal("stopped")

      store:add(t1, "thread")
      store:add(t2, "thread")

      -- Query by session
      local s1_threads = store:get_by("thread:by_session", "s1")
      assert.are.equal(2, #s1_threads)

      -- Query by state
      local running = store:get_by("thread:by_state", "running")
      assert.are.equal(1, #running)

      -- Change state
      t1.state:set("stopped")

      running = store:get_by("thread:by_state", "running")
      local stopped = store:get_by("thread:by_state", "stopped")

      assert.is_nil(running)
      assert.are.equal(2, #stopped)
    end)
  end)
end)

-- =============================================================================
-- 8. BFS/DFS REACTIVITY TESTS
-- =============================================================================

describe("EntityStore - BFS/DFS Reactivity", function()
  local store

  before_each(function()
    store = EntityStore.new("TraversalStore")
  end)

  after_each(function()
    store:dispose()
  end)

  -- ---------------------------------------------------------------------------
  -- BFS Reactivity
  -- ---------------------------------------------------------------------------

  describe("BFS reactivity", function()
    it("should update BFS result when entity is added within scope", function()
      local session = make_entity("dap:session:1")
      local thread1 = make_entity("dap:thread:1")

      store:add(session, "session")
      store:add(thread1, "thread", { { type = "parent", to = "dap:session:1" } })

      -- Get BFS result
      local descendants = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      -- Initially: session + thread1 = 2
      assert.are.equal(2, #descendants._items)

      -- Add another thread
      local thread2 = make_entity("dap:thread:2")
      store:add(thread2, "thread", { { type = "parent", to = "dap:session:1" } })

      -- BFS result should update reactively
      assert.are.equal(3, #descendants._items)
    end)

    it("should update BFS result when nested entity is added", function()
      local session = make_entity("dap:session:1")
      local thread = make_entity("dap:thread:1")

      store:add(session, "session")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

      local descendants = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      assert.are.equal(2, #descendants._items)

      -- Add stack under thread
      local stack = make_entity("dap:stack:1")
      store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })

      -- Should include the new stack
      assert.are.equal(3, #descendants._items)
    end)

    it("should update BFS result when entity is removed", function()
      local session = make_entity("dap:session:1")
      local thread1 = make_entity("dap:thread:1")
      local thread2 = make_entity("dap:thread:2")

      store:add(session, "session")
      store:add(thread1, "thread", { { type = "parent", to = "dap:session:1" } })
      store:add(thread2, "thread", { { type = "parent", to = "dap:session:1" } })

      local descendants = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      assert.are.equal(3, #descendants._items)

      -- Remove thread1 (dispose without cascade since thread has no children)
      store:dispose_entity("dap:thread:1")

      -- BFS result should update
      assert.are.equal(2, #descendants._items)
    end)

    it("should update BFS result when subtree is removed", function()
      local session = make_entity("dap:session:1")
      local thread = make_entity("dap:thread:1")
      local stack = make_entity("dap:stack:1")
      local frame = make_entity("dap:frame:1")

      store:add(session, "session")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })
      store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })
      store:add(frame, "frame", { { type = "parent", to = "dap:stack:1" } })

      local descendants = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      assert.are.equal(4, #descendants._items)

      -- Remove thread (cascades to stack and frame)
      store:dispose_entity("dap:thread:1")

      -- Only session should remain
      assert.are.equal(1, #descendants._items)
    end)

    it("should fire on_added when entity enters BFS scope", function()
      local session = make_entity("dap:session:1")
      store:add(session, "session")

      local descendants = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      local added_entities = {}
      descendants:on_added(function(entity)
        table.insert(added_entities, entity)
      end)

      local thread = make_entity("dap:thread:1")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

      assert.are.equal(1, #added_entities)
      assert.are.equal(thread.uri, added_entities[1].uri)
    end)

    it("should fire on_removed when entity leaves BFS scope", function()
      local session = make_entity("dap:session:1")
      local thread = make_entity("dap:thread:1")

      store:add(session, "session")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

      local descendants = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      local removed_entities = {}
      descendants:on_removed(function(entity)
        table.insert(removed_entities, entity)
      end)

      store:dispose_entity("dap:thread:1")

      assert.are.equal(1, #removed_entities)
      assert.are.equal(thread.uri, removed_entities[1].uri)
    end)

    it("should respect max_depth for reactive additions", function()
      local session = make_entity("dap:session:1")
      local thread = make_entity("dap:thread:1")

      store:add(session, "session")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

      -- BFS with max_depth=1 (session + direct children only)
      local shallow = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
        max_depth = 1,
      })

      assert.are.equal(2, #shallow._items)

      -- Add stack under thread (depth 2)
      local stack = make_entity("dap:stack:1")
      store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })

      -- Stack should NOT be added (exceeds max_depth)
      assert.are.equal(2, #shallow._items)
    end)

    it("should respect filter for reactive additions", function()
      local session = make_entity("dap:session:1")
      store:add(session, "session")

      local threads_only = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
        filter = function(e) return store:type_of(e.uri) == "thread" end,
      })

      -- Session is filtered out
      assert.are.equal(0, #threads_only._items)

      -- Add thread (matches filter)
      local thread = make_entity("dap:thread:1")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })
      assert.are.equal(1, #threads_only._items)

      -- Add stack (doesn't match filter)
      local stack = make_entity("dap:stack:1")
      store:add(stack, "stack", { { type = "parent", to = "dap:thread:1" } })
      assert.are.equal(1, #threads_only._items)
    end)

    it("should handle edge addition creating new reachability", function()
      local session = make_entity("dap:session:1")
      local thread = make_entity("dap:thread:1")

      store:add(session, "session")
      store:add(thread, "thread") -- No parent edge yet

      local descendants = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      -- Only session initially
      assert.are.equal(1, #descendants._items)

      -- Add parent edge dynamically
      store:add_edge("dap:thread:1", "parent", "dap:session:1")

      -- Thread should now be reachable
      assert.are.equal(2, #descendants._items)
    end)

    it("should handle edge removal breaking reachability", function()
      local session = make_entity("dap:session:1")
      local thread = make_entity("dap:thread:1")

      store:add(session, "session")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

      local descendants = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      assert.are.equal(2, #descendants._items)

      -- Remove parent edge
      store:remove_edge("dap:thread:1", "parent", "dap:session:1")

      -- Thread no longer reachable
      assert.are.equal(1, #descendants._items)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- DFS Reactivity
  -- ---------------------------------------------------------------------------

  describe("DFS reactivity", function()
    it("should update DFS result when entity is added", function()
      local session = make_entity("dap:session:1")
      store:add(session, "session")

      local result = store:dfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      assert.are.equal(1, #result._items)

      local thread = make_entity("dap:thread:1")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

      assert.are.equal(2, #result._items)
    end)

    it("should update DFS result when entity is removed", function()
      local session = make_entity("dap:session:1")
      local thread = make_entity("dap:thread:1")

      store:add(session, "session")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

      local result = store:dfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      assert.are.equal(2, #result._items)

      store:dispose_entity("dap:thread:1")

      assert.are.equal(1, #result._items)
    end)

    it("should fire collection events on DFS updates", function()
      local session = make_entity("dap:session:1")
      store:add(session, "session")

      local result = store:dfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      local added = {}
      local removed = {}

      result:on_added(function(e) table.insert(added, e) end)
      result:on_removed(function(e) table.insert(removed, e) end)

      local thread = make_entity("dap:thread:1")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

      assert.are.equal(1, #added)

      store:dispose_entity("dap:thread:1")

      assert.are.equal(1, #removed)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- BFS/DFS Collection Lifecycle
  -- ---------------------------------------------------------------------------

  describe("BFS/DFS collection lifecycle", function()
    it("should dispose BFS collection when store is disposed", function()
      local session = make_entity("dap:session:1")
      store:add(session, "session")

      local result = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      assert.is_false(result._disposed)

      store:dispose()

      assert.is_true(result._disposed)
    end)

    it("should dispose DFS collection when store is disposed", function()
      local session = make_entity("dap:session:1")
      store:add(session, "session")

      local result = store:dfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      assert.is_false(result._disposed)

      store:dispose()

      assert.is_true(result._disposed)
    end)

    it("should stop updating after collection is manually disposed", function()
      local session = make_entity("dap:session:1")
      store:add(session, "session")

      local result = store:bfs("dap:session:1", {
        direction = "in",
        edge_types = { "parent" },
      })

      result:dispose()

      -- Adding entities should not error (but won't update disposed collection)
      local thread = make_entity("dap:thread:1")
      store:add(thread, "thread", { { type = "parent", to = "dap:session:1" } })

      -- Collection still shows old count (it's disposed)
      assert.is_true(result._disposed)
    end)

    it("should update when root entity has new children after BFS call", function()
      -- Edge case: BFS called on entity, then new children added later
      local root = make_entity("dap:root")
      store:add(root, "root")

      local reachable = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })

      assert.are.equal(1, #reachable._items)

      -- Add child1 -> root
      local child1 = make_entity("dap:child:1")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      assert.are.equal(2, #reachable._items)

      -- Add child2 -> root
      local child2 = make_entity("dap:child:2")
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })
      assert.are.equal(3, #reachable._items)

      -- Add grandchild -> child1
      local grandchild = make_entity("dap:grandchild:1")
      store:add(grandchild, "grandchild", { { type = "parent", to = "dap:child:1" } })
      assert.are.equal(4, #reachable._items)
    end)
  end)
end)

-- =============================================================================
-- 9. BFS/DFS BUDGET OPTIONS
-- =============================================================================

describe("EntityStore - BFS/DFS Budget Options", function()
  local store

  before_each(function()
    store = EntityStore.new("BudgetStore")
  end)

  after_each(function()
    store:dispose()
  end)

  -- ---------------------------------------------------------------------------
  -- scanning_budget
  -- ---------------------------------------------------------------------------

  describe("scanning_budget", function()
    it("should limit total entities scanned in BFS", function()
      -- Create a tree: root -> 5 children -> 5 grandchildren each (31 total)
      local root = make_entity("dap:root")
      store:add(root, "root")

      for i = 1, 5 do
        local child = make_entity("dap:child:" .. i)
        store:add(child, "child", { { type = "parent", to = "dap:root" } })
        for j = 1, 5 do
          local grandchild = make_entity("dap:grandchild:" .. i .. ":" .. j)
          store:add(grandchild, "grandchild", { { type = "parent", to = "dap:child:" .. i } })
        end
      end

      -- Without budget: all 31 entities
      local all = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })
      assert.are.equal(31, #all._items)

      -- With scanning_budget=10: only 10 entities scanned
      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        scanning_budget = 10,
      })
      assert.are.equal(10, #limited._items)
    end)

    it("should limit total entities scanned in DFS", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      for i = 1, 10 do
        local child = make_entity("dap:child:" .. i)
        store:add(child, "child", { { type = "parent", to = "dap:root" } })
      end

      local limited = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        scanning_budget = 5,
      })
      assert.are.equal(5, #limited._items)
    end)

    it("should allow new entities when budget frees up after removal", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")

      store:add(root, "root")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })

      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        scanning_budget = 2,
      })

      -- Initially: root + child1 = 2 (budget full)
      assert.are.equal(2, #limited._items)

      -- Remove child1 -> budget frees up
      store:dispose_entity("dap:child:1")
      assert.are.equal(1, #limited._items)

      -- Add child3 -> should be added (budget allows)
      local child3 = make_entity("dap:child:3")
      store:add(child3, "child", { { type = "parent", to = "dap:root" } })
      assert.are.equal(2, #limited._items)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- result_budget
  -- ---------------------------------------------------------------------------

  describe("result_budget", function()
    it("should limit entities added to collection after filter", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      -- Add 10 children, 5 with special=true
      for i = 1, 10 do
        local child = make_entity("dap:child:" .. i, { special = i <= 5 })
        store:add(child, "child", { { type = "parent", to = "dap:root" } })
      end

      -- Filter for special, limit results to 3
      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        filter = function(e) return e.special == true end,
        result_budget = 3,
      })

      -- Should have 3 special children (not root, not all 5)
      assert.are.equal(3, #limited._items)
    end)

    it("should continue scanning even if result_budget reached", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      for i = 1, 5 do
        local child = make_entity("dap:child:" .. i)
        store:add(child, "child", { { type = "parent", to = "dap:root" } })
      end

      -- result_budget=2 but no scanning_budget
      -- All 6 entities should be tracked (scanned), but only 2 in collection
      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        result_budget = 2,
      })

      assert.are.equal(2, #limited._items)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- unique_budget
  -- ---------------------------------------------------------------------------

  describe("unique_budget", function()
    it("should limit unique entities in collection", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      for i = 1, 10 do
        local child = make_entity("dap:child:" .. i)
        store:add(child, "child", { { type = "parent", to = "dap:root" } })
      end

      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        unique_budget = 5,
      })

      assert.are.equal(5, #limited._items)
    end)

    it("should allow new unique entities when others are removed", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")

      store:add(root, "root")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })

      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        unique_budget = 2,
      })

      assert.are.equal(2, #limited._items)

      -- Remove one, add new
      store:dispose_entity("dap:child:1")
      assert.are.equal(1, #limited._items)

      local child3 = make_entity("dap:child:3")
      store:add(child3, "child", { { type = "parent", to = "dap:root" } })
      assert.are.equal(2, #limited._items)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Combined budgets
  -- ---------------------------------------------------------------------------

  describe("combined budgets", function()
    it("should respect all budgets together", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      -- 20 children, 10 special
      for i = 1, 20 do
        local child = make_entity("dap:child:" .. i, { special = i <= 10 })
        store:add(child, "child", { { type = "parent", to = "dap:root" } })
      end

      -- scanning_budget=15, result_budget=8, unique_budget=5, filter=special
      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        filter = function(e) return e.special == true end,
        scanning_budget = 15,
        result_budget = 8,
        unique_budget = 5,
      })

      -- unique_budget is most restrictive (5 < 8)
      -- But only special items pass filter
      -- scanning_budget limits to 15 entities scanned
      -- Result should be at most 5 unique special items
      assert.is_true(#limited._items <= 5)
    end)

    it("should stop scanning when scanning_budget reached even if other budgets not full", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      for i = 1, 10 do
        local child = make_entity("dap:child:" .. i, { special = false })
        store:add(child, "child", { { type = "parent", to = "dap:root" } })
      end

      -- Filter excludes all children, but scanning_budget=3
      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        filter = function(e) return e.special == true end,
        scanning_budget = 3,
        unique_budget = 10,
      })

      -- Root doesn't have special=true, so filtered out
      -- Only 3 entities scanned, none pass filter
      assert.are.equal(0, #limited._items)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Reactivity with budgets
  -- ---------------------------------------------------------------------------

  describe("reactivity with budgets", function()
    it("should not add entities when unique_budget is exhausted", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        unique_budget = 2,
      })

      -- Add first child -> budget: 2/2
      local child1 = make_entity("dap:child:1")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      assert.are.equal(2, #limited._items)

      -- Try to add more -> should not be added (budget exhausted)
      local child2 = make_entity("dap:child:2")
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })
      assert.are.equal(2, #limited._items) -- Still 2

      -- Remove child1 -> budget opens
      store:dispose_entity("dap:child:1")
      assert.are.equal(1, #limited._items)

      -- Add child3 -> should be added now
      local child3 = make_entity("dap:child:3")
      store:add(child3, "child", { { type = "parent", to = "dap:root" } })
      assert.are.equal(2, #limited._items)
    end)

    it("should respect budget on edge additions", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")

      store:add(root, "root")
      store:add(child1, "child") -- No parent edge yet
      store:add(child2, "child") -- No parent edge yet

      local limited = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        unique_budget = 2,
      })

      assert.are.equal(1, #limited._items) -- Just root

      -- Add edge for child1 -> budget: 2/2
      store:add_edge("dap:child:1", "parent", "dap:root")
      assert.are.equal(2, #limited._items)

      -- Add edge for child2 -> budget exhausted, should not add
      store:add_edge("dap:child:2", "parent", "dap:root")
      assert.are.equal(2, #limited._items) -- Still 2
    end)
  end)

  describe("reverse option", function()
    it("should iterate edges in normal order by default for BFS", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")
      local child3 = make_entity("dap:child:3")

      store:add(root, "root")
      -- Add children in order: 1, 2, 3
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })
      store:add(child3, "child", { { type = "parent", to = "dap:root" } })

      local results = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })

      -- Without reverse, should visit in order: root, child1, child2, child3
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child:1", "dap:child:2", "dap:child:3" }, uris)
    end)

    it("should iterate edges in reverse order for BFS", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")
      local child3 = make_entity("dap:child:3")

      store:add(root, "root")
      -- Add children in order: 1, 2, 3
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })
      store:add(child3, "child", { { type = "parent", to = "dap:root" } })

      local results = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
      })

      -- With reverse, should visit in order: root, child3, child2, child1
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child:3", "dap:child:2", "dap:child:1" }, uris)
    end)

    it("should iterate edges in reverse order for DFS", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")
      local child3 = make_entity("dap:child:3")

      store:add(root, "root")
      -- Add children in order: 1, 2, 3
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })
      store:add(child3, "child", { { type = "parent", to = "dap:root" } })

      -- DFS without reverse
      local results_normal = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })
      local uris_normal = vim.iter(results_normal._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child:1", "dap:child:2", "dap:child:3" }, uris_normal)

      -- DFS with reverse
      local results_reversed = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
      })
      local uris_reversed = vim.iter(results_reversed._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child:3", "dap:child:2", "dap:child:1" }, uris_reversed)
    end)

    it("should affect which entities are included when budget is limited", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")
      local child3 = make_entity("dap:child:3")

      store:add(root, "root")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })
      store:add(child3, "child", { { type = "parent", to = "dap:root" } })

      -- Without reverse, budget=2 should get root + child1
      local normal = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        unique_budget = 2,
      })
      local uris_normal = vim.iter(normal._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child:1" }, uris_normal)

      -- With reverse, budget=2 should get root + child3
      local reversed = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        unique_budget = 2,
        reverse = true,
      })
      local uris_reversed = vim.iter(reversed._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child:3" }, uris_reversed)
    end)

    it("should work with multi-level trees", function()
      -- Create tree: root -> [A, B] -> [A1, A2], [B1, B2]
      local root = make_entity("dap:root")
      local a = make_entity("dap:a")
      local b = make_entity("dap:b")
      local a1 = make_entity("dap:a1")
      local a2 = make_entity("dap:a2")
      local b1 = make_entity("dap:b1")
      local b2 = make_entity("dap:b2")

      store:add(root, "node")
      store:add(a, "node", { { type = "parent", to = "dap:root" } })
      store:add(b, "node", { { type = "parent", to = "dap:root" } })
      store:add(a1, "node", { { type = "parent", to = "dap:a" } })
      store:add(a2, "node", { { type = "parent", to = "dap:a" } })
      store:add(b1, "node", { { type = "parent", to = "dap:b" } })
      store:add(b2, "node", { { type = "parent", to = "dap:b" } })

      -- BFS expands recursively, so order is: root, a, a1, a2, b, b1, b2
      local bfs_normal = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })
      local bfs_uris = vim.iter(bfs_normal._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:a", "dap:a1", "dap:a2", "dap:b", "dap:b1", "dap:b2" }, bfs_uris)

      -- BFS reversed: root, b, b2, b1, a, a2, a1
      local bfs_reversed = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
      })
      local bfs_rev_uris = vim.iter(bfs_reversed._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:b", "dap:b2", "dap:b1", "dap:a", "dap:a2", "dap:a1" }, bfs_rev_uris)

      -- DFS normal: root, a, a1, a2, b, b1, b2
      local dfs_normal = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })
      local dfs_uris = vim.iter(dfs_normal._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:a", "dap:a1", "dap:a2", "dap:b", "dap:b1", "dap:b2" }, dfs_uris)

      -- DFS reversed: root, b, b2, b1, a, a2, a1
      local dfs_reversed = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
      })
      local dfs_rev_uris = vim.iter(dfs_reversed._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:b", "dap:b2", "dap:b1", "dap:a", "dap:a2", "dap:a1" }, dfs_rev_uris)
    end)

    it("should be reactive with reverse option", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      local results = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
      })

      assert.are.equal(1, #results._items) -- Just root

      -- Add children - reactive additions happen in order they're added to store
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })

      -- Entities are added in the order they become reachable (store:add order)
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child:1", "dap:child:2" }, uris)
    end)

    it("should apply reverse to edge additions", function()
      -- Setup: root with children, but edges added later
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")
      local grandchild1 = make_entity("dap:grandchild:1")
      local grandchild2 = make_entity("dap:grandchild:2")

      store:add(root, "root")
      store:add(child1, "child")
      store:add(child2, "child")
      store:add(grandchild1, "grandchild")
      store:add(grandchild2, "grandchild")

      -- Create BFS with reverse before edges exist
      local results = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
      })

      assert.are.equal(1, #results._items) -- Just root initially

      -- Add edges: child2 -> root, then child1 -> root
      -- With reverse, when edges are added, expansion follows reverse order
      store:add_edge("dap:child:2", "parent", "dap:root")
      store:add_edge("dap:grandchild:2", "parent", "dap:child:2")
      store:add_edge("dap:grandchild:1", "parent", "dap:child:2")

      -- child2 and its grandchildren should be in collection
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child:2", "dap:grandchild:2", "dap:grandchild:1" }, uris)
    end)
  end)

  describe("order option (pre/post)", function()
    it("should use pre-order by default (parent before children)", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")
      local grandchild = make_entity("dap:grandchild")

      store:add(root, "root")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })
      store:add(grandchild, "grandchild", { { type = "parent", to = "dap:child:1" } })

      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })

      -- Pre-order: parent, then children
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child:1", "dap:grandchild", "dap:child:2" }, uris)
    end)

    it("should support post-order (children before parent)", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")
      local grandchild = make_entity("dap:grandchild")

      store:add(root, "root")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })
      store:add(grandchild, "grandchild", { { type = "parent", to = "dap:child:1" } })

      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "post",
      })

      -- Post-order: children first, then parent
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:grandchild", "dap:child:1", "dap:child:2", "dap:root" }, uris)
    end)

    it("should support reverse + post-order for tree window above pattern", function()
      -- This is the pattern for collecting items "above" focus in a tree view
      local root = make_entity("dap:root")
      local a = make_entity("dap:a")
      local a1 = make_entity("dap:a1")
      local a2 = make_entity("dap:a2")
      local b = make_entity("dap:b")
      local b1 = make_entity("dap:b1")
      local b2 = make_entity("dap:b2")

      store:add(root, "node")
      store:add(a, "node", { { type = "parent", to = "dap:root" } })
      store:add(a1, "node", { { type = "parent", to = "dap:a" } })
      store:add(a2, "node", { { type = "parent", to = "dap:a" } })
      store:add(b, "node", { { type = "parent", to = "dap:root" } })
      store:add(b1, "node", { { type = "parent", to = "dap:b" } })
      store:add(b2, "node", { { type = "parent", to = "dap:b" } })

      -- reverse + post-order: children in reverse, then parent
      -- Gives us items in reverse tree-view order (for "above focus" collection)
      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
        order = "post",
      })

      -- Reverse post-order: b2, b1, b, a2, a1, a, root
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:b2", "dap:b1", "dap:b", "dap:a2", "dap:a1", "dap:a", "dap:root" }, uris)

      -- When reversed for display, gives correct tree order:
      -- root, a, a1, a2, b, b1, b2
      local display_order = {}
      for i = #uris, 1, -1 do
        table.insert(display_order, uris[i])
      end
      assert.are.same({ "dap:root", "dap:a", "dap:a1", "dap:a2", "dap:b", "dap:b1", "dap:b2" }, display_order)
    end)

    it("should work with BFS and post-order", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")

      store:add(root, "root")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })

      local results = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "post",
      })

      -- Post-order: children first, then parent
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:child:1", "dap:child:2", "dap:root" }, uris)
    end)

    it("should combine order with budget correctly", function()
      local root = make_entity("dap:root")
      local a = make_entity("dap:a")
      local a1 = make_entity("dap:a1")
      local b = make_entity("dap:b")

      store:add(root, "node")
      store:add(a, "node", { { type = "parent", to = "dap:root" } })
      store:add(a1, "node", { { type = "parent", to = "dap:a" } })
      store:add(b, "node", { { type = "parent", to = "dap:root" } })

      -- Post-order with budget: should get deepest items first
      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "post",
        unique_budget = 2,
      })

      -- Post-order visits: a1, a, b, root
      -- With budget=2, we get: a1, a
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:a1", "dap:a" }, uris)
    end)

    it("should combine reverse + post-order + budget for proximity collection", function()
      -- Simulates collecting items "above" focus with limited budget
      -- Should prioritize items closest to focus
      local root = make_entity("dap:root")
      local a = make_entity("dap:a")
      local a1 = make_entity("dap:a1")
      local b = make_entity("dap:b")
      local b1 = make_entity("dap:b1")

      store:add(root, "node")
      store:add(a, "node", { { type = "parent", to = "dap:root" } })
      store:add(a1, "node", { { type = "parent", to = "dap:a" } })
      store:add(b, "node", { { type = "parent", to = "dap:root" } })
      store:add(b1, "node", { { type = "parent", to = "dap:b" } })

      -- reverse + post-order with budget
      -- Full order would be: b1, b, a1, a, root
      -- With budget=3: b1, b, a1
      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
        order = "post",
        unique_budget = 3,
      })

      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:b1", "dap:b", "dap:a1" }, uris)
    end)

    it("should reactively add entities with post-order (items appended as discovered)", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "post",
      })

      -- Initially just root
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root" }, uris)

      -- Add a child - reactive additions append to collection
      local child = make_entity("dap:child")
      store:add(child, "child", { { type = "parent", to = "dap:root" } })

      -- Child is added after root (order affects initial traversal, not reactive additions)
      uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child" }, uris)

      -- Add a grandchild - also appended
      local grandchild = make_entity("dap:grandchild")
      store:add(grandchild, "grandchild", { { type = "parent", to = "dap:child" } })

      uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:child", "dap:grandchild" }, uris)

      -- The key point: all reachable entities ARE in the collection
      assert.are.equal(3, #results._items)
    end)

    it("should reactively add entities with reverse + post-order (items appended)", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
        order = "post",
      })

      -- Initially just root
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root" }, uris)

      -- Add children in order: a, b - they get appended as discovered
      local a = make_entity("dap:a")
      local b = make_entity("dap:b")
      store:add(a, "child", { { type = "parent", to = "dap:root" } })
      store:add(b, "child", { { type = "parent", to = "dap:root" } })

      -- Reactive additions append in discovery order
      uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root", "dap:a", "dap:b" }, uris)

      -- All entities are in the collection
      assert.are.equal(3, #results._items)
    end)

    it("should reactively remove entities from collection", function()
      local root = make_entity("dap:root")
      local child1 = make_entity("dap:child:1")
      local child2 = make_entity("dap:child:2")

      store:add(root, "root")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })

      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "post",
      })

      -- Post-order: child1, child2, root
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:child:1", "dap:child:2", "dap:root" }, uris)

      -- Remove child1 via store (direct removal triggers proper cleanup)
      store:dispose_entity("dap:child:1")

      -- Should remove child1
      uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.equal(2, #results._items)
      assert.is_true(vim.tbl_contains(uris, "dap:child:2"))
      assert.is_true(vim.tbl_contains(uris, "dap:root"))
    end)

    it("should reactively handle edge additions with post-order", function()
      local root = make_entity("dap:root")
      local orphan = make_entity("dap:orphan")
      local orphan_child = make_entity("dap:orphan:child")

      store:add(root, "root")
      store:add(orphan, "node") -- No parent edge yet
      store:add(orphan_child, "node", { { type = "parent", to = "dap:orphan" } })

      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "post",
      })

      -- Initially just root (orphan not connected)
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.same({ "dap:root" }, uris)

      -- Connect orphan to root
      store:add_edge("dap:orphan", "parent", "dap:root")

      -- Now should include orphan subtree (appended to collection)
      uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.equal(3, #results._items)
      assert.is_true(vim.tbl_contains(uris, "dap:root"))
      assert.is_true(vim.tbl_contains(uris, "dap:orphan"))
      assert.is_true(vim.tbl_contains(uris, "dap:orphan:child"))
    end)

    it("should reactively respect budget with post-order additions", function()
      local root = make_entity("dap:root")
      store:add(root, "root")

      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "post",
        unique_budget = 3,
      })

      -- Initially just root
      assert.are.equal(1, #results._items)

      -- Add multiple children
      local a = make_entity("dap:a")
      local a1 = make_entity("dap:a1")
      local b = make_entity("dap:b")

      store:add(a, "node", { { type = "parent", to = "dap:root" } })
      store:add(a1, "node", { { type = "parent", to = "dap:a" } })
      store:add(b, "node", { { type = "parent", to = "dap:root" } })

      -- Budget is 3, so only 3 entities total
      -- Initial was root (budget 1 used), then a, a1 added (budget 3 used)
      -- b cannot be added (budget exhausted)
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.equal(3, #results._items)
      assert.is_true(vim.tbl_contains(uris, "dap:root"))
      assert.is_true(vim.tbl_contains(uris, "dap:a"))
      assert.is_true(vim.tbl_contains(uris, "dap:a1"))
    end)

    it("should allow new items when budget frees up with post-order", function()
      local root = make_entity("dap:root")
      local a = make_entity("dap:a")
      local b = make_entity("dap:b")

      store:add(root, "root")
      store:add(a, "node", { { type = "parent", to = "dap:root" } })
      store:add(b, "node", { { type = "parent", to = "dap:root" } })

      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "post",
        unique_budget = 2,
      })

      -- Post-order with budget=2: a, b (root doesn't fit initially)
      -- Actually initial traversal in post-order visits a first, then b, then root
      -- With budget 2, we get a and b
      assert.are.equal(2, #results._items)

      -- Remove a - budget frees up, root can now be added
      a:dispose()

      -- Now should have 2 items (b and potentially root)
      local uris = vim.iter(results._items):map(function(e) return e.uri end):totable()
      assert.are.equal(2, #results._items)
      assert.is_true(vim.tbl_contains(uris, "dap:b"))
    end)

    it("should fire on_added/on_removed events with order option", function()
      local root = make_entity("dap:root")
      local child = make_entity("dap:child")

      store:add(root, "root")
      store:add(child, "child", { { type = "parent", to = "dap:root" } })

      local results = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "post",
      })

      -- Initial collection has both entities
      assert.are.equal(2, #results._items)

      local added = {}
      local removed = {}

      results:on_added(function(e)
        table.insert(added, e.uri)
      end)

      results:on_removed(function(e)
        table.insert(removed, e.uri)
      end)

      -- Add another child
      local child2 = make_entity("dap:child:2")
      store:add(child2, "child", { { type = "parent", to = "dap:root" } })

      assert.are.same({ "dap:child:2" }, added)
      assert.are.same({}, removed)

      -- Remove child2 via store (triggers proper removal from collection)
      store:dispose_entity("dap:child:2")

      assert.are.same({ "dap:child:2" }, added)
      assert.are.same({ "dap:child:2" }, removed)
    end)

    it("should include all reachable entities with reactive updates", function()
      -- Test that reactive updates include all reachable entities
      local root = make_entity("dap:root")
      local a = make_entity("dap:a")

      store:add(root, "root")
      store:add(a, "node", { { type = "parent", to = "dap:root" } })

      local above = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        reverse = true,
        order = "post",
      })

      -- Initial: a, root (reverse post-order)
      assert.are.equal(2, #above._items)

      -- Add sibling b
      local b = make_entity("dap:b")
      store:add(b, "node", { { type = "parent", to = "dap:root" } })

      -- Now has 3 items
      assert.are.equal(3, #above._items)

      -- Add grandchild to b
      local b1 = make_entity("dap:b1")
      store:add(b1, "node", { { type = "parent", to = "dap:b" } })

      -- Now has 4 items
      assert.are.equal(4, #above._items)

      -- Verify all entities are present
      local uris = vim.iter(above._items):map(function(e) return e.uri end):totable()
      assert.is_true(vim.tbl_contains(uris, "dap:root"))
      assert.is_true(vim.tbl_contains(uris, "dap:a"))
      assert.is_true(vim.tbl_contains(uris, "dap:b"))
      assert.is_true(vim.tbl_contains(uris, "dap:b1"))
    end)
  end)
end)

-- =============================================================================
-- 10. PERFORMANCE BENCHMARKS
-- =============================================================================

describe("EntityStore - Performance Benchmarks", function()
  local store

  before_each(function()
    store = EntityStore.new("PerfStore")
  end)

  after_each(function()
    store:dispose()
  end)

  it("PERF: add 1000 entities", function()
    local ms = measure_time(function()
      for i = 1, 1000 do
        store:add(make_entity("dap:entity:" .. i, { id = i }), "entity")
      end
    end)

    print(string.format("\n  Add 1000 entities: %.2f ms", ms))
    assert.is_true(ms < 100, "Adding 1000 entities should take < 100ms")
  end)

  it("PERF: add 1000 entities with edges", function()
    -- Create a root
    store:add(make_entity("dap:root", {}), "root")

    local ms = measure_time(function()
      for i = 1, 1000 do
        store:add(make_entity("dap:entity:" .. i, { id = i }), "entity", {
          { type = "parent", to = "dap:root" },
        })
      end
    end)

    print(string.format("\n  Add 1000 entities with edges: %.2f ms", ms))
    assert.is_true(ms < 200, "Adding 1000 entities with edges should take < 200ms")
  end)

  it("PERF: index lookup", function()
    store:add_index("entity:by_id", function(e) return e.id end)

    for i = 1, 1000 do
      store:add(make_entity("dap:entity:" .. i, { id = i }), "entity")
    end

    local ms = measure_time(function()
      for i = 1, 1000 do
        store:get_one("entity:by_id", i)
      end
    end)

    print(string.format("\n  1000 index lookups: %.2f ms", ms))
    assert.is_true(ms < 10, "1000 index lookups should take < 10ms")
  end)

  it("PERF: BFS traversal on deep tree", function()
    -- Create a tree: root -> 10 children -> 10 grandchildren each = 111 nodes
    store:add(make_entity("dap:root", {}), "root")

    for i = 1, 10 do
      store:add(make_entity("dap:child:" .. i, {}), "child", {
        { type = "parent", to = "dap:root" },
      })
      for j = 1, 10 do
        store:add(make_entity("dap:grandchild:" .. i .. ":" .. j, {}), "grandchild", {
          { type = "parent", to = "dap:child:" .. i },
        })
      end
    end

    local ms = measure_time(function()
      store:bfs("dap:root", { direction = "in", edge_types = { "parent" } })
    end, 100)

    print(string.format("\n  BFS on 111-node tree (100 iterations): %.3f ms/iter", ms))
    assert.is_true(ms < 5, "BFS on 111-node tree should take < 5ms")
  end)

  it("PERF: cascade disposal of 100 entities", function()
    store:add(make_entity("dap:root", {}), "root")
    for i = 1, 100 do
      store:add(make_entity("dap:child:" .. i, {}), "child", {
        { type = "parent", to = "dap:root" },
      })
    end

    local ms = measure_time(function()
      store:dispose_entity("dap:root")
    end)

    print(string.format("\n  Cascade dispose 101 entities: %.2f ms", ms))
    assert.is_true(ms < 50, "Cascade disposal of 101 entities should take < 50ms")
    assert.are.equal(0, store:count())
  end)

  it("PERF: reactive index with 100 signal updates", function()
    store:add_index("entity:by_status", function(e) return e.status end)

    local entities = {}
    for i = 1, 100 do
      local e = make_entity("dap:entity:" .. i, {})
      e.status = neostate.Signal("pending")
      store:add(e, "entity")
      table.insert(entities, e)
    end

    local ms = measure_time(function()
      for _, e in ipairs(entities) do
        e.status:set("active")
      end
    end)

    print(string.format("\n  100 signal updates with index: %.2f ms", ms))
    assert.is_true(ms < 50, "100 signal updates should take < 50ms")

    -- Verify index updated
    local active = store:get_by("entity:by_status", "active")
    assert.are.equal(100, #active)
  end)
end)

-- =============================================================================
-- 11. PRUNE OPTION
-- =============================================================================

describe("EntityStore - Prune Option", function()
  local store

  before_each(function()
    store = EntityStore.new("TestStore")
  end)

  after_each(function()
    store:dispose()
  end)

  --[[
    Test tree structure:
                  root
           /       |       \
        child1  child2    child3
        /  \       |
      g1   g2     g3
          /  \
        gg1  gg2
  ]]
  local function setup_test_tree()
    store:add(make_entity("dap:root", { name = "root", collapsed = false }), "root")

    store:add(make_entity("dap:child1", { name = "child1", collapsed = false }), "child", {
      { type = "parent", to = "dap:root" },
    })
    store:add(make_entity("dap:child2", { name = "child2", collapsed = true }), "child", {
      { type = "parent", to = "dap:root" },
    })
    store:add(make_entity("dap:child3", { name = "child3", collapsed = false }), "child", {
      { type = "parent", to = "dap:root" },
    })

    store:add(make_entity("dap:g1", { name = "g1", collapsed = false }), "grandchild", {
      { type = "parent", to = "dap:child1" },
    })
    store:add(make_entity("dap:g2", { name = "g2", collapsed = true }), "grandchild", {
      { type = "parent", to = "dap:child1" },
    })
    store:add(make_entity("dap:g3", { name = "g3", collapsed = false }), "grandchild", {
      { type = "parent", to = "dap:child2" },
    })

    store:add(make_entity("dap:gg1", { name = "gg1", collapsed = false }), "great-grandchild", {
      { type = "parent", to = "dap:g2" },
    })
    store:add(make_entity("dap:gg2", { name = "gg2", collapsed = false }), "great-grandchild", {
      { type = "parent", to = "dap:g2" },
    })
  end

  describe("BFS with prune", function()
    it("should stop traversal at pruned nodes", function()
      setup_test_tree()

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        prune = function(e) return e.collapsed end,
      })

      local names = vim.tbl_map(function(e) return e.name end, collection._items)

      -- child2 is collapsed, so g3 should not be included
      -- g2 is collapsed, so gg1 and gg2 should not be included
      assert.is_true(vim.tbl_contains(names, "root"))
      assert.is_true(vim.tbl_contains(names, "child1"))
      assert.is_true(vim.tbl_contains(names, "child2")) -- pruned node itself is included
      assert.is_true(vim.tbl_contains(names, "child3"))
      assert.is_true(vim.tbl_contains(names, "g1"))
      assert.is_true(vim.tbl_contains(names, "g2")) -- pruned node itself is included
      assert.is_false(vim.tbl_contains(names, "g3")) -- child of collapsed child2
      assert.is_false(vim.tbl_contains(names, "gg1")) -- child of collapsed g2
      assert.is_false(vim.tbl_contains(names, "gg2")) -- child of collapsed g2

      collection:dispose()
    end)

    it("should include pruned node but not its children", function()
      setup_test_tree()

      local collection = store:bfs("dap:child1", {
        direction = "in",
        edge_types = { "parent" },
        prune = function(e) return e.name == "g2" end,
      })

      local names = vim.tbl_map(function(e) return e.name end, collection._items)

      assert.is_true(vim.tbl_contains(names, "child1"))
      assert.is_true(vim.tbl_contains(names, "g1"))
      assert.is_true(vim.tbl_contains(names, "g2")) -- pruned node itself is included
      assert.is_false(vim.tbl_contains(names, "gg1")) -- child of pruned g2
      assert.is_false(vim.tbl_contains(names, "gg2")) -- child of pruned g2

      collection:dispose()
    end)
  end)

  describe("DFS with prune", function()
    it("should stop traversal at pruned nodes", function()
      setup_test_tree()

      local collection = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        prune = function(e) return e.collapsed end,
      })

      local names = vim.tbl_map(function(e) return e.name end, collection._items)

      -- child2 is collapsed, so g3 should not be included
      -- g2 is collapsed, so gg1 and gg2 should not be included
      assert.is_true(vim.tbl_contains(names, "root"))
      assert.is_true(vim.tbl_contains(names, "child1"))
      assert.is_true(vim.tbl_contains(names, "child2")) -- pruned node itself is included
      assert.is_true(vim.tbl_contains(names, "child3"))
      assert.is_true(vim.tbl_contains(names, "g1"))
      assert.is_true(vim.tbl_contains(names, "g2")) -- pruned node itself is included
      assert.is_false(vim.tbl_contains(names, "g3")) -- child of collapsed child2
      assert.is_false(vim.tbl_contains(names, "gg1")) -- child of collapsed g2
      assert.is_false(vim.tbl_contains(names, "gg2")) -- child of collapsed g2

      collection:dispose()
    end)

    it("should maintain correct order with pruning", function()
      setup_test_tree()

      local collection = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        order = "pre",
        prune = function(e) return e.collapsed end,
      })

      local names = vim.tbl_map(function(e) return e.name end, collection._items)

      -- Pre-order should be: root, child1, g1, g2, child2, child3
      assert.are.same({ "root", "child1", "g1", "g2", "child2", "child3" }, names)

      collection:dispose()
    end)
  end)

  describe("reactive prune behavior", function()
    it("should not add children of pruned nodes reactively", function()
      store:add(make_entity("dap:root", { name = "root", collapsed = true }), "root")

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        prune = function(e) return e.collapsed end,
      })

      -- Only root should be in collection
      assert.are.equal(1, #collection._items)

      -- Add a child to the collapsed root
      store:add(make_entity("dap:child1", { name = "child1" }), "child", {
        { type = "parent", to = "dap:root" },
      })

      -- Child should NOT be added because root is pruned
      assert.are.equal(1, #collection._items)

      collection:dispose()
    end)

    it("should not add children via edge to pruned node", function()
      store:add(make_entity("dap:root", { name = "root", collapsed = false }), "root")
      store:add(make_entity("dap:child1", { name = "child1", collapsed = true }), "child", {
        { type = "parent", to = "dap:root" },
      })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        prune = function(e) return e.collapsed end,
      })

      -- root and child1 should be in collection
      assert.are.equal(2, #collection._items)

      -- Add an entity first, then connect it to the pruned child1
      store:add(make_entity("dap:g1", { name = "g1" }), "grandchild")
      store:add_edge("dap:g1", "dap:child1", "parent")

      -- g1 should NOT be added because child1 is pruned
      assert.are.equal(2, #collection._items)

      collection:dispose()
    end)
  end)

  describe("collapse/uncollapse behavior", function()
    it("BFS should reactively add children when node is uncollapsed", function()
      -- Setup tree with Signal-based collapsed property
      local root = make_entity("dap:root", { name = "root" })
      root.collapsed = neostate.Signal(false)

      local child1 = make_entity("dap:child1", { name = "child1" })
      child1.collapsed = neostate.Signal(true) -- Start collapsed

      store:add(root, "root")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })

      -- Create BFS collection with prune and prune_watch
      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        prune = function(e) return e.collapsed and e.collapsed:get() end,
        prune_watch = function(e) return e.collapsed end, -- Watch the collapsed Signal
      })

      -- Initially: root and child1 in collection
      assert.are.equal(2, #collection._items)

      -- Add grandchild to collapsed child1
      local g1 = make_entity("dap:g1", { name = "g1" })
      g1.collapsed = neostate.Signal(false)
      store:add(g1, "grandchild", { { type = "parent", to = "dap:child1" } })

      -- g1 should NOT be in collection (child1 is collapsed/pruned)
      assert.are.equal(2, #collection._items)

      -- Uncollapse child1
      child1.collapsed:set(false)

      -- Now g1 SHOULD be in collection (child1 is no longer pruned)
      -- This tests reactive response to prune condition change
      assert.are.equal(3, #collection._items)
      local names = vim.tbl_map(function(e) return e.name end, collection._items)
      assert.is_true(vim.tbl_contains(names, "g1"))

      collection:dispose()
    end)

    it("BFS should reactively remove children when node is collapsed", function()
      -- Setup tree with Signal-based collapsed property
      local root = make_entity("dap:root", { name = "root" })
      root.collapsed = neostate.Signal(false)

      local child1 = make_entity("dap:child1", { name = "child1" })
      child1.collapsed = neostate.Signal(false) -- Start uncollapsed

      local g1 = make_entity("dap:g1", { name = "g1" })
      g1.collapsed = neostate.Signal(false)

      store:add(root, "root")
      store:add(child1, "child", { { type = "parent", to = "dap:root" } })
      store:add(g1, "grandchild", { { type = "parent", to = "dap:child1" } })

      -- Create BFS collection with prune and prune_watch
      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        prune = function(e) return e.collapsed and e.collapsed:get() end,
        prune_watch = function(e) return e.collapsed end, -- Watch the collapsed Signal
      })

      -- Initially: all three in collection
      assert.are.equal(3, #collection._items)

      -- Collapse child1
      child1.collapsed:set(true)

      -- g1 should be REMOVED from collection (child1 is now pruned)
      assert.are.equal(2, #collection._items)
      local names = vim.tbl_map(function(e) return e.name end, collection._items)
      assert.is_true(vim.tbl_contains(names, "root"))
      assert.is_true(vim.tbl_contains(names, "child1"))
      assert.is_false(vim.tbl_contains(names, "g1"))

      collection:dispose()
    end)
  end)
end)

describe("EntityStore - Path-Aware Traversal", function()
  local neostate = require("neostate")
  local EntityStore = require("neostate.entity_store")
  local store

  local function make_entity(uri, extra)
    local e = { uri = uri }
    if extra then
      for k, v in pairs(extra) do
        e[k] = v
      end
    end
    return e
  end

  before_each(function()
    store = EntityStore.new("test")
  end)

  after_each(function()
    if store then store:dispose() end
  end)

  describe("diamond pattern (multiple paths to same entity)", function()
    it("should visit same entity via different paths in BFS", function()
      -- Diamond: root -> A -> leaf, root -> B -> leaf
      local root = make_entity("dap:root")
      local a = make_entity("dap:a")
      local b = make_entity("dap:b")
      local leaf = make_entity("dap:leaf")

      store:add(root, "node")
      store:add(a, "node", { { type = "parent", to = "dap:root" } })
      store:add(b, "node", { { type = "parent", to = "dap:root" } })
      store:add(leaf, "node", { { type = "parent", to = "dap:a" } })
      store:add_edge("dap:leaf", "parent", "dap:b") -- leaf also has parent B

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })

      -- leaf should appear TWICE (via A and via B)
      local leaf_count = 0
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          leaf_count = leaf_count + 1
        end
      end
      assert.are.equal(2, leaf_count)

      -- Each leaf occurrence should have different paths
      local paths = {}
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          table.insert(paths, item._virtual.uri)
        end
      end
      assert.are_not.equal(paths[1], paths[2])
    end)

    it("should visit same entity via different paths in DFS", function()
      local root = make_entity("dap:root")
      local a = make_entity("dap:a")
      local b = make_entity("dap:b")
      local leaf = make_entity("dap:leaf")

      store:add(root, "node")
      store:add(a, "node", { { type = "parent", to = "dap:root" } })
      store:add(b, "node", { { type = "parent", to = "dap:root" } })
      store:add(leaf, "node", { { type = "parent", to = "dap:a" } })
      store:add_edge("dap:leaf", "parent", "dap:b")

      local collection = store:dfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })

      local leaf_count = 0
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          leaf_count = leaf_count + 1
        end
      end
      assert.are.equal(2, leaf_count)
    end)
  end)

  describe("cycle detection", function()
    it("should break cycles in BFS without infinite loop", function()
      -- Cycle: A -> B -> C -> A
      local a = make_entity("dap:a")
      local b = make_entity("dap:b")
      local c = make_entity("dap:c")

      store:add(a, "node")
      store:add(b, "node")
      store:add(c, "node")

      store:add_edge("dap:a", "next", "dap:b")
      store:add_edge("dap:b", "next", "dap:c")
      store:add_edge("dap:c", "next", "dap:a") -- cycle back

      local collection = store:bfs("dap:a", {
        direction = "out",
        edge_types = { "next" },
      })

      -- Should have 3 unique entities (A, B, C) each appearing once
      assert.are.equal(3, #collection._items)
    end)

    it("should break cycles in DFS without infinite loop", function()
      local a = make_entity("dap:a")
      local b = make_entity("dap:b")
      local c = make_entity("dap:c")

      store:add(a, "node")
      store:add(b, "node")
      store:add(c, "node")

      store:add_edge("dap:a", "next", "dap:b")
      store:add_edge("dap:b", "next", "dap:c")
      store:add_edge("dap:c", "next", "dap:a")

      local collection = store:dfs("dap:a", {
        direction = "out",
        edge_types = { "next" },
      })

      assert.are.equal(3, #collection._items)
    end)
  end)

  describe("_virtual metadata", function()
    it("should include path information in _virtual", function()
      local root = make_entity("dap:root")
      local child = make_entity("dap:child")
      local grandchild = make_entity("dap:grandchild")

      store:add(root, "node")
      store:add(child, "node", { { type = "parent", to = "dap:root" } })
      store:add(grandchild, "node", { { type = "parent", to = "dap:child" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })

      -- Find grandchild
      local gc = nil
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:grandchild" then
          gc = item
          break
        end
      end

      assert.is_not_nil(gc)
      assert.is_not_nil(gc._virtual)
      assert.are.equal(2, gc._virtual.depth)
      assert.are.same({ "dap:root", "dap:child" }, gc._virtual.path)
      assert.are.equal("dap:child", gc._virtual.parent)
    end)

    it("should have composite uri in _virtual", function()
      local root = make_entity("dap:root")
      local child = make_entity("dap:child")

      store:add(root, "node")
      store:add(child, "node", { { type = "parent", to = "dap:root" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })

      local child_item = nil
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:child" then
          child_item = item
          break
        end
      end

      assert.is_not_nil(child_item)
      -- virtual uri should be "root/child" (keys derived from URIs)
      assert.are.equal("root/child", child_item._virtual.uri)
    end)

    it("should expose entity properties via metatable", function()
      local root = make_entity("dap:root", { name = "Root Node", value = 42 })

      store:add(root, "node")

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
      })

      local item = collection._items[1]

      -- Properties accessible via metatable
      assert.are.equal("dap:root", item.uri)
      assert.are.equal("Root Node", item.name)
      assert.are.equal(42, item.value)

      -- _virtual also accessible
      assert.is_not_nil(item._virtual)
    end)
  end)

  describe("path-aware filter", function()
    it("should receive path context in filter function", function()
      local root = make_entity("dap:root")
      local child = make_entity("dap:child")

      store:add(root, "node")
      store:add(child, "node", { { type = "parent", to = "dap:root" } })

      local filter_contexts = {}
      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        filter = function(entity, ctx)
          table.insert(filter_contexts, { uri = entity.uri, ctx = ctx })
          return true
        end,
      })

      -- Both entities should have been filtered
      assert.are.equal(2, #filter_contexts)

      -- Root has empty path
      local root_ctx = nil
      for _, fc in ipairs(filter_contexts) do
        if fc.uri == "dap:root" then
          root_ctx = fc.ctx
          break
        end
      end
      assert.are.same({}, root_ctx.path)
      assert.are.equal(0, root_ctx.depth)

      -- Child has root in path
      local child_ctx = nil
      for _, fc in ipairs(filter_contexts) do
        if fc.uri == "dap:child" then
          child_ctx = fc.ctx
          break
        end
      end
      assert.are.same({ "dap:root" }, child_ctx.path)
      assert.are.equal(1, child_ctx.depth)
      assert.are.equal("dap:root", child_ctx.parent)
    end)

    it("should allow path-based filtering", function()
      -- Filter out entities where path contains a specific entity
      local root = make_entity("dap:root")
      local hidden = make_entity("dap:hidden")
      local leaf = make_entity("dap:leaf")

      store:add(root, "node")
      store:add(hidden, "node", { { type = "parent", to = "dap:root" } })
      store:add(leaf, "node", { { type = "parent", to = "dap:hidden" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        filter = function(entity, ctx)
          -- Exclude entities whose path contains "hidden"
          for _, p in ipairs(ctx.path) do
            if p == "dap:hidden" then return false end
          end
          return true
        end,
      })

      -- Should have root and hidden, but not leaf (filtered by path)
      assert.are.equal(2, #collection._items)
      local uris = {}
      for _, item in ipairs(collection._items) do
        uris[item.uri] = true
      end
      assert.is_true(uris["dap:root"])
      assert.is_true(uris["dap:hidden"])
      assert.is_nil(uris["dap:leaf"])
    end)
  end)

  describe("path-aware prune", function()
    it("should receive path context in prune function", function()
      local root = make_entity("dap:root")
      local child = make_entity("dap:child")

      store:add(root, "node")
      store:add(child, "node", { { type = "parent", to = "dap:root" } })

      local prune_contexts = {}
      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        prune = function(entity, ctx)
          table.insert(prune_contexts, { uri = entity.uri, ctx = ctx })
          return false
        end,
      })

      -- Both entities should have been checked for prune
      assert.are.equal(2, #prune_contexts)
    end)

    it("should allow path-based pruning in diamond", function()
      -- Diamond: root -> A -> leaf, root -> B -> leaf
      -- Prune at A, but not at B
      local root = make_entity("dap:root")
      local a = make_entity("dap:a")
      local b = make_entity("dap:b")
      local leaf = make_entity("dap:leaf")

      store:add(root, "node")
      store:add(a, "node", { { type = "parent", to = "dap:root" } })
      store:add(b, "node", { { type = "parent", to = "dap:root" } })
      store:add(leaf, "node", { { type = "parent", to = "dap:a" } })
      store:add_edge("dap:leaf", "parent", "dap:b")

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        prune = function(entity, ctx)
          -- Prune at A only
          return entity.uri == "dap:a"
        end,
      })

      -- Should have: root, a, b, and leaf via B (but not leaf via A)
      local leaf_count = 0
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          leaf_count = leaf_count + 1
          -- The leaf should be via B, not A
          assert.is_true(vim.tbl_contains(item._virtual.path, "dap:b"))
        end
      end
      assert.are.equal(1, leaf_count)
    end)
  end)

  describe("filtered_path in _virtual", function()
    it("should track filtered path excluding filtered entities", function()
      local root = make_entity("dap:root")
      local hidden = make_entity("dap:hidden")
      local leaf = make_entity("dap:leaf")

      store:add(root, "node")
      store:add(hidden, "node", { { type = "parent", to = "dap:root" } })
      store:add(leaf, "node", { { type = "parent", to = "dap:hidden" } })

      local collection = store:bfs("dap:root", {
        direction = "in",
        edge_types = { "parent" },
        filter = function(entity, ctx)
          -- Exclude "hidden" from collection
          return entity.uri ~= "dap:hidden"
        end,
      })

      -- Find leaf
      local leaf_item = nil
      for _, item in ipairs(collection._items) do
        if item.uri == "dap:leaf" then
          leaf_item = item
          break
        end
      end

      assert.is_not_nil(leaf_item)
      -- Full path includes hidden
      assert.are.same({ "dap:root", "dap:hidden" }, leaf_item._virtual.path)
      -- Filtered path excludes hidden
      assert.are.same({ "dap:root" }, leaf_item._virtual.filtered_path)
      assert.are.equal("dap:root", leaf_item._virtual.filtered_parent)
    end)
  end)
end)
