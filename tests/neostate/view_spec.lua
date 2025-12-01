local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")
local View = require("neostate.view")

-- =============================================================================
-- Helper Functions
-- =============================================================================

local function make_entity(uri, props)
  local e = neostate.Disposable(props or {})
  e.uri = uri
  return e
end

-- =============================================================================
-- View Basic Tests
-- =============================================================================

describe("View", function()
  local store

  before_each(function()
    store = EntityStore.new("TestStore")
    store:add_index("thread:by_state", function(e) return e.state end)
    store:add_index("thread:by_session_id", function(e) return e.session_id end)
  end)

  after_each(function()
    store:dispose()
  end)

  -- ---------------------------------------------------------------------------
  -- Basic Creation and Iteration
  -- ---------------------------------------------------------------------------

  describe("creation and iteration", function()
    it("should create a view and iterate entities", function()
      store:add(make_entity("thread:1", { state = "stopped", session_id = "s1" }), "thread")
      store:add(make_entity("thread:2", { state = "running", session_id = "s1" }), "thread")
      store:add(make_entity("thread:3", { state = "stopped", session_id = "s2" }), "thread")

      local view = store:view("thread")
      local count = 0
      for _ in view:iter() do
        count = count + 1
      end

      assert.are.equal(3, count)
      view:dispose()
    end)

    it("should filter by index with where()", function()
      store:add(make_entity("thread:1", { state = "stopped", session_id = "s1" }), "thread")
      store:add(make_entity("thread:2", { state = "running", session_id = "s1" }), "thread")
      store:add(make_entity("thread:3", { state = "stopped", session_id = "s2" }), "thread")

      local stopped = store:view("thread"):where("by_state", "stopped")
      local count = 0
      for _ in stopped:iter() do
        count = count + 1
      end

      assert.are.equal(2, count)
      stopped:dispose()
    end)

    it("should chain multiple where() calls", function()
      store:add(make_entity("thread:1", { state = "stopped", session_id = "s1" }), "thread")
      store:add(make_entity("thread:2", { state = "running", session_id = "s1" }), "thread")
      store:add(make_entity("thread:3", { state = "stopped", session_id = "s2" }), "thread")

      local s1_stopped = store:view("thread")
        :where("by_session_id", "s1")
        :where("by_state", "stopped")

      local count = 0
      for _ in s1_stopped:iter() do
        count = count + 1
      end

      assert.are.equal(1, count)
      s1_stopped:dispose()
    end)

    it("should count entities", function()
      store:add(make_entity("thread:1", { state = "stopped" }), "thread")
      store:add(make_entity("thread:2", { state = "stopped" }), "thread")
      store:add(make_entity("thread:3", { state = "running" }), "thread")

      local stopped = store:view("thread"):where("by_state", "stopped")
      assert.are.equal(2, stopped:count())
      stopped:dispose()
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Cache Sharing
  -- ---------------------------------------------------------------------------

  describe("cache sharing", function()
    it("should share cache between views with same query", function()
      store:add(make_entity("thread:1", { state = "stopped" }), "thread")

      local view1 = store:view("thread"):where("by_state", "stopped")
      local view2 = store:view("thread"):where("by_state", "stopped")

      -- Both should use same cache
      assert.are.equal(view1._cache_key, view2._cache_key)

      -- Cache should have ref_count = 2
      local cache = store._query_cache[view1._cache_key]
      assert.are.equal(2, cache.ref_count)

      view1:dispose()
      assert.are.equal(1, cache.ref_count)

      view2:dispose()
      -- Cache should be freed
      assert.is_nil(store._query_cache[view1._cache_key])
    end)

    it("should create different caches for different queries", function()
      store:add(make_entity("thread:1", { state = "stopped" }), "thread")

      local stopped = store:view("thread"):where("by_state", "stopped")
      local running = store:view("thread"):where("by_state", "running")

      assert.are_not.equal(stopped._cache_key, running._cache_key)

      stopped:dispose()
      running:dispose()
    end)

    it("should produce same cache key regardless of filter order", function()
      store:add(make_entity("thread:1", { state = "stopped", session_id = "s1" }), "thread")

      local view1 = store:view("thread")
        :where("by_state", "stopped")
        :where("by_session_id", "s1")

      local view2 = store:view("thread")
        :where("by_session_id", "s1")
        :where("by_state", "stopped")

      -- Both should produce same canonical cache key
      assert.are.equal(view1._cache_key, view2._cache_key)

      -- Cache should have ref_count = 2
      local cache = store._query_cache[view1._cache_key]
      assert.are.equal(2, cache.ref_count)

      view1:dispose()
      view2:dispose()
    end)

    it("should isolate listeners between views sharing cache", function()
      store:add(make_entity("thread:1", { state = "stopped" }), "thread")

      local view1 = store:view("thread"):where("by_state", "stopped")
      local view2 = store:view("thread"):where("by_state", "stopped")

      local added1 = {}
      local added2 = {}
      view1:on_added(function(e) table.insert(added1, e.uri) end)
      view2:on_added(function(e) table.insert(added2, e.uri) end)

      -- Both should share cache
      assert.are.equal(view1._cache_key, view2._cache_key)

      -- Add entity - both listeners should fire
      store:add(make_entity("thread:2", { state = "stopped" }), "thread")
      assert.are.equal(1, #added1)
      assert.are.equal(1, #added2)

      -- Dispose view1
      view1:dispose()

      -- Add another entity - only view2 listener should fire
      store:add(make_entity("thread:3", { state = "stopped" }), "thread")
      assert.are.equal(1, #added1) -- Still 1
      assert.are.equal(2, #added2) -- Now 2

      view2:dispose()
    end)

    it("should not fire listeners after view disposal", function()
      local view = store:view("thread"):where("by_state", "stopped")

      local added = {}
      view:on_added(function(e) table.insert(added, e.uri) end)

      store:add(make_entity("thread:1", { state = "stopped" }), "thread")
      assert.are.equal(1, #added)

      view:dispose()

      -- After disposal, listener should not fire
      store:add(make_entity("thread:2", { state = "stopped" }), "thread")
      assert.are.equal(1, #added)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Derived View Lifecycle
  -- ---------------------------------------------------------------------------

  describe("derived view lifecycle", function()
    it("should dispose derived view when parent disposes", function()
      local base = store:view("thread")
      local derived = base:where("by_state", "stopped")

      assert.is_false(derived._disposed)

      base:dispose()

      assert.is_true(derived._disposed)
    end)

    it("should release cache when derived view chain disposes", function()
      local base = store:view("thread")
      local derived = base:where("by_state", "stopped")

      local cache_key = derived._cache_key
      assert.is_not_nil(store._query_cache[cache_key])

      base:dispose()

      -- Cache should be released
      assert.is_nil(store._query_cache[cache_key])
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Reactivity
  -- ---------------------------------------------------------------------------

  describe("reactivity", function()
    it("should react to entity additions", function()
      local view = store:view("thread"):where("by_state", "stopped")

      local added = {}
      view:on_added(function(e)
        table.insert(added, e.uri)
      end)

      store:add(make_entity("thread:1", { state = "stopped" }), "thread")
      store:add(make_entity("thread:2", { state = "running" }), "thread")
      store:add(make_entity("thread:3", { state = "stopped" }), "thread")

      assert.are.equal(2, #added)
      assert.is_true(vim.tbl_contains(added, "thread:1"))
      assert.is_true(vim.tbl_contains(added, "thread:3"))

      view:dispose()
    end)

    it("should react to entity removals", function()
      store:add(make_entity("thread:1", { state = "stopped" }), "thread")
      store:add(make_entity("thread:2", { state = "stopped" }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")

      local removed = {}
      view:on_removed(function(e)
        table.insert(removed, e.uri)
      end)

      store:dispose_entity("thread:1")

      assert.are.equal(1, #removed)
      assert.are.equal("thread:1", removed[1])

      view:dispose()
    end)

    it("should call each() for existing and future entities", function()
      store:add(make_entity("thread:1", { state = "stopped" }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")

      local seen = {}
      view:each(function(e)
        table.insert(seen, e.uri)
      end)

      -- Should see existing entity
      assert.are.equal(1, #seen)
      assert.are.equal("thread:1", seen[1])

      -- Should see future entity
      store:add(make_entity("thread:2", { state = "stopped" }), "thread")
      assert.are.equal(2, #seen)

      view:dispose()
    end)

    it("should react to Signal index value changes", function()
      local state_signal = neostate.Signal("running")
      local entity = make_entity("thread:1", { state = state_signal })
      store:add_index("thread:by_state_signal", function(e) return e.state end)
      store:add(entity, "thread")

      local view = store:view("thread"):where("by_state_signal", "stopped")

      -- Initially empty
      assert.are.equal(0, view:count())

      local added = {}
      view:on_added(function(e)
        table.insert(added, e.uri)
      end)

      -- Change signal value
      state_signal:set("stopped")

      -- Should now be in view
      assert.are.equal(1, view:count())
      assert.are.equal(1, #added)

      view:dispose()
    end)

    it("should fire on_removed when Signal changes and entity leaves view", function()
      local state_signal = neostate.Signal("stopped")
      local entity = make_entity("thread:1", { state = state_signal })
      store:add_index("thread:by_state_signal", function(e) return e.state end)
      store:add(entity, "thread")

      local view = store:view("thread"):where("by_state_signal", "stopped")

      -- Initially has entity
      assert.are.equal(1, view:count())

      local removed = {}
      view:on_removed(function(e)
        table.insert(removed, e.uri)
      end)

      -- Change signal value - entity should leave view
      state_signal:set("running")

      -- Should now be empty
      assert.are.equal(0, view:count())
      assert.are.equal(1, #removed)
      assert.are.equal("thread:1", removed[1])

      view:dispose()
    end)

    it("should handle Signal changes with composed filters (AND)", function()
      local state_signal = neostate.Signal("running")
      local session_signal = neostate.Signal("s1")
      local entity = make_entity("thread:1", { state = state_signal, session_id = session_signal })

      store:add_index("thread:by_state_sig", function(e) return e.state end)
      store:add_index("thread:by_session_sig", function(e) return e.session_id end)
      store:add(entity, "thread")

      local view = store:view("thread")
        :where("by_state_sig", "stopped")
        :where("by_session_sig", "s1")

      local added = {}
      local removed = {}
      view:on_added(function(e) table.insert(added, e.uri) end)
      view:on_removed(function(e) table.insert(removed, e.uri) end)

      -- Initially: state=running, session=s1 → doesn't match (state wrong)
      assert.are.equal(0, view:count())

      -- Change state to stopped → now matches both filters
      state_signal:set("stopped")
      assert.are.equal(1, view:count())
      assert.are.equal(1, #added)

      -- Change session to s2 → no longer matches session filter
      session_signal:set("s2")
      assert.are.equal(0, view:count())
      assert.are.equal(1, #removed)

      view:dispose()
    end)

    it("should support multiple on_added listeners", function()
      local view = store:view("thread"):where("by_state", "stopped")

      local added1 = {}
      local added2 = {}
      view:on_added(function(e) table.insert(added1, e.uri) end)
      view:on_added(function(e) table.insert(added2, e.uri) end)

      store:add(make_entity("thread:1", { state = "stopped" }), "thread")

      assert.are.equal(1, #added1)
      assert.are.equal(1, #added2)

      view:dispose()
    end)

    it("should support multiple on_removed listeners", function()
      store:add(make_entity("thread:1", { state = "stopped" }), "thread")
      local view = store:view("thread"):where("by_state", "stopped")

      local removed1 = {}
      local removed2 = {}
      view:on_removed(function(e) table.insert(removed1, e.uri) end)
      view:on_removed(function(e) table.insert(removed2, e.uri) end)

      store:dispose_entity("thread:1")

      assert.are.equal(1, #removed1)
      assert.are.equal(1, #removed2)

      view:dispose()
    end)

    it("should allow unsubscribing from on_added", function()
      local view = store:view("thread"):where("by_state", "stopped")

      local added = {}
      local unsub = view:on_added(function(e)
        table.insert(added, e.uri)
      end)

      store:add(make_entity("thread:1", { state = "stopped" }), "thread")
      assert.are.equal(1, #added)

      -- Unsubscribe
      unsub()

      store:add(make_entity("thread:2", { state = "stopped" }), "thread")
      -- Should still be 1 - listener was removed
      assert.are.equal(1, #added)

      view:dispose()
    end)

    it("should allow unsubscribing from on_removed", function()
      store:add(make_entity("thread:1", { state = "stopped" }), "thread")
      store:add(make_entity("thread:2", { state = "stopped" }), "thread")
      local view = store:view("thread"):where("by_state", "stopped")

      local removed = {}
      local unsub = view:on_removed(function(e)
        table.insert(removed, e.uri)
      end)

      store:dispose_entity("thread:1")
      assert.are.equal(1, #removed)

      -- Unsubscribe
      unsub()

      store:dispose_entity("thread:2")
      -- Should still be 1 - listener was removed
      assert.are.equal(1, #removed)

      view:dispose()
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Computed Signals
  -- ---------------------------------------------------------------------------

  describe("computed signals", function()
    it("some() should return true if any entity matches", function()
      store:add(make_entity("thread:1", { state = "stopped", hit = false }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", hit = true }), "thread")
      store:add(make_entity("thread:3", { state = "stopped", hit = false }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local any_hit = view:some(function(e) return e.hit end)

      assert.is_true(any_hit:get())

      view:dispose()
    end)

    it("some() should return false if no entities match", function()
      store:add(make_entity("thread:1", { state = "stopped", hit = false }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", hit = false }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local any_hit = view:some(function(e) return e.hit end)

      assert.is_false(any_hit:get())

      view:dispose()
    end)

    it("some() should update when entity is added", function()
      store:add(make_entity("thread:1", { state = "stopped", hit = false }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local any_hit = view:some(function(e) return e.hit end)

      assert.is_false(any_hit:get())

      store:add(make_entity("thread:2", { state = "stopped", hit = true }), "thread")

      assert.is_true(any_hit:get())

      view:dispose()
    end)

    it("every() should return true if all entities match", function()
      store:add(make_entity("thread:1", { state = "stopped", valid = true }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", valid = true }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local all_valid = view:every(function(e) return e.valid end)

      assert.is_true(all_valid:get())

      view:dispose()
    end)

    it("every() should return false if any entity doesn't match", function()
      store:add(make_entity("thread:1", { state = "stopped", valid = true }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", valid = false }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local all_valid = view:every(function(e) return e.valid end)

      assert.is_false(all_valid:get())

      view:dispose()
    end)

    it("aggregate() should compute custom aggregate", function()
      store:add(make_entity("thread:1", { state = "stopped", count = 5 }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", count = 3 }), "thread")
      store:add(make_entity("thread:3", { state = "stopped", count = 2 }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local total = view:aggregate(function(items)
        local sum = 0
        for _, item in ipairs(items) do
          sum = sum + item.count
        end
        return sum
      end)

      assert.are.equal(10, total:get())

      view:dispose()
    end)

    it("some() should update to false when matching entity is removed", function()
      store:add(make_entity("thread:1", { state = "stopped", hit = false }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", hit = true }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local any_hit = view:some(function(e) return e.hit end)

      assert.is_true(any_hit:get())

      -- Remove the only matching entity
      store:dispose_entity("thread:2")

      assert.is_false(any_hit:get())

      view:dispose()
    end)

    it("every() should update to true when non-matching entity is removed", function()
      store:add(make_entity("thread:1", { state = "stopped", valid = true }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", valid = false }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local all_valid = view:every(function(e) return e.valid end)

      assert.is_false(all_valid:get())

      -- Remove the non-matching entity
      store:dispose_entity("thread:2")

      assert.is_true(all_valid:get())

      view:dispose()
    end)

    it("aggregate() should recompute when entity is removed", function()
      store:add(make_entity("thread:1", { state = "stopped", count = 5 }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", count = 3 }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local total = view:aggregate(function(items)
        local sum = 0
        for _, item in ipairs(items) do
          sum = sum + item.count
        end
        return sum
      end)

      assert.are.equal(8, total:get())

      store:dispose_entity("thread:1")

      assert.are.equal(3, total:get())

      view:dispose()
    end)

    it("some() should react to Signal property changes", function()
      local hit_signal = neostate.Signal(false)
      store:add(make_entity("thread:1", { state = "stopped", hit = hit_signal }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local any_hit = view:some(function(e) return e.hit end)

      assert.is_false(any_hit:get())

      -- Change Signal value
      hit_signal:set(true)

      assert.is_true(any_hit:get())

      view:dispose()
    end)

    it("every() should react to Signal property changes", function()
      local valid_signal = neostate.Signal(true)
      store:add(make_entity("thread:1", { state = "stopped", valid = true }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", valid = valid_signal }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local all_valid = view:every(function(e) return e.valid end)

      assert.is_true(all_valid:get())

      -- Change Signal value to false
      valid_signal:set(false)

      assert.is_false(all_valid:get())

      view:dispose()
    end)

    it("aggregate() should react to Signal property changes", function()
      local count_signal = neostate.Signal(5)
      store:add(make_entity("thread:1", { state = "stopped", count = count_signal }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", count = 3 }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local total = view:aggregate(
        function(items)
          local sum = 0
          for _, item in ipairs(items) do
            local c = item.count
            if type(c) == "table" and c.get then c = c:get() end
            sum = sum + c
          end
          return sum
        end,
        function(e) return type(e.count) == "table" and e.count or nil end
      )

      assert.are.equal(8, total:get())

      -- Change Signal value
      count_signal:set(10)

      assert.are.equal(13, total:get())

      view:dispose()
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- View API Methods
  -- ---------------------------------------------------------------------------

  describe("API methods", function()
    it("find() should return first entity matching predicate", function()
      store:add(make_entity("thread:1", { state = "stopped", priority = 1 }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", priority = 5 }), "thread")
      store:add(make_entity("thread:3", { state = "stopped", priority = 3 }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local high_priority = view:find(function(e) return e.priority > 2 end)

      assert.is_not_nil(high_priority)
      assert.is_true(high_priority.priority > 2)

      view:dispose()
    end)

    it("find() should return nil if no entity matches", function()
      store:add(make_entity("thread:1", { state = "stopped", priority = 1 }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local result = view:find(function(e) return e.priority > 10 end)

      assert.is_nil(result)

      view:dispose()
    end)

    it("first() should return first entity in view", function()
      store:add(make_entity("thread:1", { state = "stopped" }), "thread")
      store:add(make_entity("thread:2", { state = "stopped" }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local first = view:first()

      assert.is_not_nil(first)
      assert.is_true(first.state == "stopped")

      view:dispose()
    end)

    it("first() should return nil for empty view", function()
      local view = store:view("thread"):where("by_state", "stopped")
      local first = view:first()

      assert.is_nil(first)

      view:dispose()
    end)

    it("get_one() should find entity by additional index", function()
      store:add(make_entity("thread:1", { state = "stopped", session_id = "s1" }), "thread")
      store:add(make_entity("thread:2", { state = "stopped", session_id = "s2" }), "thread")
      store:add(make_entity("thread:3", { state = "running", session_id = "s1" }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      local found = view:get_one("by_session_id", "s2")

      assert.is_not_nil(found)
      assert.are.equal("thread:2", found.uri)

      view:dispose()
    end)

    it("get_one() should return nil if not in view", function()
      store:add(make_entity("thread:1", { state = "stopped", session_id = "s1" }), "thread")
      store:add(make_entity("thread:2", { state = "running", session_id = "s2" }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      -- thread:2 has session_id=s2 but state=running, so not in view
      local found = view:get_one("by_session_id", "s2")

      assert.is_nil(found)

      view:dispose()
    end)

    it("call() should invoke method on all entities", function()
      local called = {}
      local function make_callable_entity(uri, props)
        local e = make_entity(uri, props)
        e.mark = function(self)
          table.insert(called, self.uri)
        end
        return e
      end

      store:add(make_callable_entity("thread:1", { state = "stopped" }), "thread")
      store:add(make_callable_entity("thread:2", { state = "stopped" }), "thread")
      store:add(make_callable_entity("thread:3", { state = "running" }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      view:call("mark")

      assert.are.equal(2, #called)
      assert.is_true(vim.tbl_contains(called, "thread:1"))
      assert.is_true(vim.tbl_contains(called, "thread:2"))

      view:dispose()
    end)

    it("call() should pass arguments to method", function()
      local results = {}
      local function make_callable_entity(uri, props)
        local e = make_entity(uri, props)
        e.record = function(self, a, b)
          table.insert(results, { uri = self.uri, a = a, b = b })
        end
        return e
      end

      store:add(make_callable_entity("thread:1", { state = "stopped" }), "thread")

      local view = store:view("thread"):where("by_state", "stopped")
      view:call("record", "hello", 42)

      assert.are.equal(1, #results)
      assert.are.equal("hello", results[1].a)
      assert.are.equal(42, results[1].b)

      view:dispose()
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Edge Traversal with follow()
  -- ---------------------------------------------------------------------------

  describe("follow() edge traversal", function()
    before_each(function()
      -- Add indexes for hierarchical structure
      store:add_index("stack:by_is_current", function(e) return e.is_current end)
      store:add_index("frame:by_index", function(e) return e.index end)
    end)

    it("should traverse edges to target entities", function()
      -- Create hierarchy: stack -> frames via "children" edge
      local stack = make_entity("stack:1", { is_current = true })
      local frame1 = make_entity("frame:1", { index = 0, name = "main" })
      local frame2 = make_entity("frame:2", { index = 1, name = "foo" })

      store:add(stack, "stack")
      store:add(frame1, "frame")
      store:add(frame2, "frame")

      -- Add children edges from stack to frames
      store:add_edge("stack:1", "children", "frame:1")
      store:add_edge("stack:1", "children", "frame:2")

      local stacks_view = store:view("stack"):where("by_is_current", true)
      local frames_view = stacks_view:follow("children")

      assert.are.equal(2, frames_view:count())

      local names = {}
      for f in frames_view:iter() do
        table.insert(names, f.name)
      end
      assert.is_true(vim.tbl_contains(names, "main"))
      assert.is_true(vim.tbl_contains(names, "foo"))

      stacks_view:dispose()
    end)

    it("should filter target entities by type", function()
      local stack = make_entity("stack:1", { is_current = true })
      local frame = make_entity("frame:1", { index = 0 })
      local other = make_entity("other:1", { foo = "bar" })

      store:add(stack, "stack")
      store:add(frame, "frame")
      store:add(other, "other")

      store:add_edge("stack:1", "children", "frame:1")
      store:add_edge("stack:1", "children", "other:1")

      local stacks_view = store:view("stack"):where("by_is_current", true)

      -- Without type filter
      local all_children = stacks_view:follow("children")
      assert.are.equal(2, all_children:count())

      -- With type filter
      local frames_only = stacks_view:follow("children", "frame")
      assert.are.equal(1, frames_only:count())

      local first = frames_only:first()
      assert.are.equal("frame:1", first.uri)

      stacks_view:dispose()
    end)

    it("should react when source view changes (entity enters source)", function()
      local stack1 = make_entity("stack:1", { is_current = false })
      local stack2 = make_entity("stack:2", { is_current = true })
      local frame1 = make_entity("frame:1", { index = 0 })
      local frame2 = make_entity("frame:2", { index = 0 })

      -- Use Signal for is_current so we can change it
      stack1.is_current = neostate.Signal(false)
      store:add_index("stack:by_is_current_sig", function(e) return e.is_current end)

      store:add(stack1, "stack")
      store:add(stack2, "stack")
      store:add(frame1, "frame")
      store:add(frame2, "frame")

      store:add_edge("stack:1", "children", "frame:1")
      store:add_edge("stack:2", "children", "frame:2")

      local current_stacks = store:view("stack"):where("by_is_current_sig", true)
      local frames = current_stacks:follow("children")

      -- Initially only frame2 (from stack2 which is current)
      assert.are.equal(1, frames:count())
      assert.are.equal("frame:2", frames:first().uri)

      local added = {}
      frames:on_added(function(e) table.insert(added, e.uri) end)

      -- Change stack1 to current - its frames should appear
      stack1.is_current:set(true)

      assert.are.equal(2, frames:count())
      assert.are.equal(1, #added)
      assert.are.equal("frame:1", added[1])

      current_stacks:dispose()
    end)

    it("should react when source view changes (entity leaves source)", function()
      local stack = make_entity("stack:1", {})
      stack.is_current = neostate.Signal(true)
      store:add_index("stack:by_is_current_sig", function(e) return e.is_current end)

      local frame = make_entity("frame:1", { index = 0 })

      store:add(stack, "stack")
      store:add(frame, "frame")
      store:add_edge("stack:1", "children", "frame:1")

      local current_stacks = store:view("stack"):where("by_is_current_sig", true)
      local frames = current_stacks:follow("children")

      assert.are.equal(1, frames:count())

      local removed = {}
      frames:on_removed(function(e) table.insert(removed, e.uri) end)

      -- Change stack to not current - its frames should disappear
      stack.is_current:set(false)

      assert.are.equal(0, frames:count())
      assert.are.equal(1, #removed)
      assert.are.equal("frame:1", removed[1])

      current_stacks:dispose()
    end)

    it("should react to source index Signal change with follow->where chain", function()
      -- This tests the exact pattern: stack[0]/frame[0]
      -- When stack's index changes from 0 to 1, old frames should leave
      -- IMPORTANT: Both stack AND frame have reactive index Signals (like SDK)
      store:add_index("stack:by_index_sig", function(e) return e.index end)
      store:add_index("frame:by_index_sig", function(e) return e.index end)

      -- Create two stacks with reactive index Signals
      local stack1 = make_entity("stack:1", {})
      stack1.index = neostate.Signal(0)  -- Initially stack[0]

      local stack2 = make_entity("stack:2", {})
      stack2.index = neostate.Signal(1)  -- Initially stack[1]

      -- Frames with reactive index Signals (like SDK)
      local frame1 = make_entity("frame:1", { name = "level_3" })
      frame1.index = neostate.Signal(0)

      local frame2 = make_entity("frame:2", { name = "level_2" })
      frame2.index = neostate.Signal(0)

      store:add(stack1, "stack")
      store:add(stack2, "stack")
      store:add(frame1, "frame")
      store:add(frame2, "frame")

      -- stack1 -> frame1, stack2 -> frame2
      store:add_edge("stack:1", "frames", "frame:1")
      store:add_edge("stack:2", "frames", "frame:2")

      -- Query: stack[0] -> frame[0]
      local stack_view = store:view("stack"):where("by_index_sig", 0)
      local frames = stack_view:follow("frames", "frame"):where("by_index_sig", 0)

      -- Initially should have 1 frame (frame1 from stack1)
      assert.are.equal(1, frames:count())
      assert.are.equal("frame:1", frames:first().uri)

      local added = {}
      local removed = {}
      frames:on_added(function(e) table.insert(added, e.uri) end)
      frames:on_removed(function(e) table.insert(removed, e.uri) end)

      -- Simulate new stack becoming current: stack1 index 0->1, stack2 index 1->0
      stack1.index:set(1)  -- stack1 is now stack[1]
      stack2.index:set(0)  -- stack2 is now stack[0]

      -- Now should have frame2 (from stack2) instead of frame1
      assert.are.equal(1, frames:count(), "Should have exactly 1 frame after index swap")
      assert.are.equal("frame:2", frames:first().uri, "Should now show frame2 from stack2")

      -- Events should have fired
      assert.are.equal(1, #removed, "Should have removed frame1")
      assert.are.equal("frame:1", removed[1])
      assert.are.equal(1, #added, "Should have added frame2")
      assert.are.equal("frame:2", added[1])

      stack_view:dispose()
    end)

    it("should react when new stack is created and old becomes stale (SDK scenario)", function()
      -- This models the EXACT SDK scenario:
      -- 1. stack:1 is created (index=0), frame:1 in it
      -- 2. Query is set up: stack[0]/frame[0]
      -- 3. New stack:2 is created (index=0), stack:1's index changes to 1
      -- 4. frame:2 is created in stack:2
      -- Result: frame:1 should leave, frame:2 should enter
      store:add_index("stack:by_index_sig", function(e) return e.index end)
      store:add_index("frame:by_index_sig", function(e) return e.index end)

      -- Step 1: Create first stack and frame
      local stack1 = make_entity("stack:1", {})
      stack1.index = neostate.Signal(0)  -- stack[0]

      local frame1 = make_entity("frame:1", { name = "level_3" })
      frame1.index = neostate.Signal(0)

      store:add(stack1, "stack")
      store:add(frame1, "frame")
      store:add_edge("stack:1", "frames", "frame:1")

      -- Step 2: Set up the query
      local stack_view = store:view("stack"):where("by_index_sig", 0)
      local frames = stack_view:follow("frames", "frame"):where("by_index_sig", 0)

      assert.are.equal(1, frames:count(), "Initial: should have 1 frame")
      assert.are.equal("frame:1", frames:first().uri)

      local added = {}
      local removed = {}
      frames:on_added(function(e) table.insert(added, e.uri) end)
      frames:on_removed(function(e) table.insert(removed, e.uri) end)

      -- Step 3: New stack created, old stack becomes stale
      -- (In SDK, this happens when thread:stack() is called after continue)
      stack1.index:set(1)  -- Old stack is now stack[1]

      local stack2 = make_entity("stack:2", {})
      stack2.index = neostate.Signal(0)  -- New stack is stack[0]
      store:add(stack2, "stack")

      -- Step 4: Frame created in new stack
      local frame2 = make_entity("frame:2", { name = "level_2" })
      frame2.index = neostate.Signal(0)
      store:add(frame2, "frame")
      store:add_edge("stack:2", "frames", "frame:2")

      -- Verify: should have frame2, not frame1
      assert.are.equal(1, frames:count(), "After step: should have exactly 1 frame")
      assert.are.equal("frame:2", frames:first().uri, "Should now show frame2")

      -- Events
      assert.are.equal(1, #removed, "Should have removed frame1")
      assert.are.equal("frame:1", removed[1])
      assert.are.equal(1, #added, "Should have added frame2")
      assert.are.equal("frame:2", added[1])

      stack_view:dispose()
    end)

    it("should react when edge is added", function()
      local stack = make_entity("stack:1", { is_current = true })
      local frame1 = make_entity("frame:1", { index = 0 })
      local frame2 = make_entity("frame:2", { index = 1 })

      store:add(stack, "stack")
      store:add(frame1, "frame")
      store:add(frame2, "frame")

      -- Only one edge initially
      store:add_edge("stack:1", "children", "frame:1")

      local current_stacks = store:view("stack"):where("by_is_current", true)
      local frames = current_stacks:follow("children")

      assert.are.equal(1, frames:count())

      local added = {}
      frames:on_added(function(e) table.insert(added, e.uri) end)

      -- Add another edge
      store:add_edge("stack:1", "children", "frame:2")

      assert.are.equal(2, frames:count())
      assert.are.equal(1, #added)
      assert.are.equal("frame:2", added[1])

      current_stacks:dispose()
    end)

    it("should react when edge is removed", function()
      local stack = make_entity("stack:1", { is_current = true })
      local frame1 = make_entity("frame:1", { index = 0 })
      local frame2 = make_entity("frame:2", { index = 1 })

      store:add(stack, "stack")
      store:add(frame1, "frame")
      store:add(frame2, "frame")

      store:add_edge("stack:1", "children", "frame:1")
      store:add_edge("stack:1", "children", "frame:2")

      local current_stacks = store:view("stack"):where("by_is_current", true)
      local frames = current_stacks:follow("children")

      assert.are.equal(2, frames:count())

      local removed = {}
      frames:on_removed(function(e) table.insert(removed, e.uri) end)

      -- Remove edge
      store:remove_edge("stack:1", "children", "frame:1")

      assert.are.equal(1, frames:count())
      assert.are.equal(1, #removed)
      assert.are.equal("frame:1", removed[1])

      current_stacks:dispose()
    end)

    it("should chain follow() with where()", function()
      local stack = make_entity("stack:1", { is_current = true })
      local frame0 = make_entity("frame:0", { index = 0, name = "top" })
      local frame1 = make_entity("frame:1", { index = 1, name = "middle" })
      local frame2 = make_entity("frame:2", { index = 2, name = "bottom" })

      store:add(stack, "stack")
      store:add(frame0, "frame")
      store:add(frame1, "frame")
      store:add(frame2, "frame")

      store:add_edge("stack:1", "children", "frame:0")
      store:add_edge("stack:1", "children", "frame:1")
      store:add_edge("stack:1", "children", "frame:2")

      local current_stacks = store:view("stack"):where("by_is_current", true)
      -- Must specify target type "frame" to enable where() chaining with frame indexes
      local top_frames = current_stacks:follow("children", "frame"):where("by_index", 0)

      assert.are.equal(1, top_frames:count())
      assert.are.equal("top", top_frames:first().name)

      current_stacks:dispose()
    end)

    it("should handle multiple sources pointing to same target", function()
      local stack1 = make_entity("stack:1", { is_current = true })
      local stack2 = make_entity("stack:2", { is_current = true })
      local frame = make_entity("frame:1", { index = 0 })

      store:add(stack1, "stack")
      store:add(stack2, "stack")
      store:add(frame, "frame")

      -- Both stacks point to same frame
      store:add_edge("stack:1", "children", "frame:1")
      store:add_edge("stack:2", "children", "frame:1")

      local current_stacks = store:view("stack"):where("by_is_current", true)
      local frames = current_stacks:follow("children")

      -- Should only have frame once (deduplicated)
      assert.are.equal(1, frames:count())

      -- Remove one edge - frame should still be there
      store:remove_edge("stack:1", "children", "frame:1")
      assert.are.equal(1, frames:count())

      -- Remove second edge - frame should be gone
      store:remove_edge("stack:2", "children", "frame:1")
      assert.are.equal(0, frames:count())

      current_stacks:dispose()
    end)

    it("should handle source entity removal", function()
      local stack = make_entity("stack:1", { is_current = true })
      local frame = make_entity("frame:1", { index = 0 })

      store:add(stack, "stack")
      store:add(frame, "frame")
      store:add_edge("stack:1", "children", "frame:1")

      local current_stacks = store:view("stack"):where("by_is_current", true)
      local frames = current_stacks:follow("children")

      assert.are.equal(1, frames:count())

      local removed = {}
      frames:on_removed(function(e) table.insert(removed, e.uri) end)

      -- Remove the source entity
      store:dispose_entity("stack:1")

      assert.are.equal(0, frames:count())
      assert.are.equal(1, #removed)

      current_stacks:dispose()
    end)

    it("should clean up subscriptions on dispose", function()
      local stack = make_entity("stack:1", { is_current = true })
      local frame = make_entity("frame:1", { index = 0 })

      store:add(stack, "stack")
      store:add(frame, "frame")
      store:add_edge("stack:1", "children", "frame:1")

      local current_stacks = store:view("stack"):where("by_is_current", true)
      local frames = current_stacks:follow("children")

      local added = {}
      frames:on_added(function(e) table.insert(added, e.uri) end)

      -- Dispose the view
      current_stacks:dispose()

      -- Adding more data should not trigger the listener
      local frame2 = make_entity("frame:2", { index = 1 })
      store:add(frame2, "frame")
      store:add_edge("stack:1", "children", "frame:2")

      assert.are.equal(0, #added)
    end)

    it("should support deep chaining: view -> where -> follow -> where", function()
      -- session -> thread -> stack -> frame hierarchy
      -- Note: thread:by_state already added in parent before_each
      store:add_index("session:by_active", function(e) return e.active end)

      local session = make_entity("session:1", { active = true })
      local thread1 = make_entity("thread:1", { state = "stopped" })
      local thread2 = make_entity("thread:2", { state = "running" })
      local stack1 = make_entity("stack:1", { is_current = true })
      local stack2 = make_entity("stack:2", { is_current = true })
      local frame1 = make_entity("frame:1", { index = 0 })
      local frame2 = make_entity("frame:2", { index = 0 })
      local frame3 = make_entity("frame:3", { index = 1 })

      store:add(session, "session")
      store:add(thread1, "thread")
      store:add(thread2, "thread")
      store:add(stack1, "stack")
      store:add(stack2, "stack")
      store:add(frame1, "frame")
      store:add(frame2, "frame")
      store:add(frame3, "frame")

      -- session -> threads
      store:add_edge("session:1", "threads", "thread:1")
      store:add_edge("session:1", "threads", "thread:2")
      -- threads -> stacks
      store:add_edge("thread:1", "stacks", "stack:1")
      store:add_edge("thread:2", "stacks", "stack:2")
      -- stacks -> frames
      store:add_edge("stack:1", "frames", "frame:1")
      store:add_edge("stack:1", "frames", "frame:3")
      store:add_edge("stack:2", "frames", "frame:2")

      -- Query: active sessions -> stopped threads -> current stacks -> top frames
      local result = store:view("session")
        :where("by_active", true)
        :follow("threads", "thread")
        :where("by_state", "stopped")
        :follow("stacks", "stack")
        :where("by_is_current", true)
        :follow("frames", "frame")
        :where("by_index", 0)

      assert.are.equal(1, result:count())
      assert.are.equal("frame:1", result:first().uri)

      session:dispose()
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Mutation Errors
  -- ---------------------------------------------------------------------------

  describe("mutation errors", function()
    it("should throw error on add()", function()
      local view = store:view("thread")
      assert.has_error(function()
        view:add({})
      end)
      view:dispose()
    end)

    it("should throw error on adopt()", function()
      local view = store:view("thread")
      assert.has_error(function()
        view:adopt({})
      end)
      view:dispose()
    end)

    it("should throw error on delete()", function()
      local view = store:view("thread")
      assert.has_error(function()
        view:delete(function() return true end)
      end)
      view:dispose()
    end)
  end)
end)
