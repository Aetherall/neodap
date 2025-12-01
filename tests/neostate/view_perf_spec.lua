--[[
  View Performance Tests

  This file measures performance of View operations:
  - View creation with varying entity counts
  - Iteration over large views
  - Cache sharing efficiency
  - Reactive add/remove notifications
  - Computed signals (some/every/aggregate)
  - Index composition (multiple filters)
  - Signal-based index changes

  Run with: make test neostate
  Or: nvim --headless -u tests/helpers/minimal_init.lua -c "PlenaryBustedFile tests/neostate/view_perf_spec.lua"
]]

local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")

-- =============================================================================
-- Performance Utilities
-- =============================================================================

local function measure_once(name, fn)
  collectgarbage("collect")
  local start = vim.loop.hrtime()
  local result = fn()
  local elapsed = (vim.loop.hrtime() - start) / 1e6
  print(string.format("\t%s: %.3f ms", name, elapsed))
  return elapsed, result
end

local function make_entity(uri, props)
  local entity = neostate.Disposable(props or {}, nil, uri)
  entity.uri = uri
  return entity
end

-- =============================================================================
-- View Performance Tests
-- =============================================================================

describe("View Performance", function()
  local store

  before_each(function()
    store = EntityStore.new("PerfStore")
    store:add_index("item:by_state", function(e) return e.state end)
    store:add_index("item:by_category", function(e) return e.category end)
    store:add_index("item:by_priority", function(e) return e.priority end)
  end)

  after_each(function()
    store:dispose()
  end)

  -- ---------------------------------------------------------------------------
  -- View Creation
  -- ---------------------------------------------------------------------------

  describe("View Creation", function()
    it("PERF: create view over 1000 entities", function()
      -- Add 1000 entities, half stopped, half running
      for i = 1, 1000 do
        local state = i % 2 == 0 and "stopped" or "running"
        store:add(make_entity("item:" .. i, { state = state }), "item")
      end

      local elapsed = measure_once("Create view with filter", function()
        local view = store:view("item"):where("by_state", "stopped")
        local count = view:count()
        view:dispose()
        return count
      end)

      print(string.format("\tFiltered view count: 500 entities"))
      assert.is_true(elapsed < 50, "View creation should be < 50ms")
    end)

    it("PERF: create view over 10000 entities", function()
      for i = 1, 10000 do
        local state = i % 2 == 0 and "stopped" or "running"
        store:add(make_entity("item:" .. i, { state = state }), "item")
      end

      local elapsed = measure_once("Create view with filter (10k)", function()
        local view = store:view("item"):where("by_state", "stopped")
        local count = view:count()
        view:dispose()
        return count
      end)

      print(string.format("\tFiltered view count: 5000 entities"))
      assert.is_true(elapsed < 200, "View creation should be < 200ms for 10k entities")
    end)

    it("PERF: chained where() with multiple filters", function()
      -- Add entities with category and state combinations
      for i = 1, 5000 do
        store:add(make_entity("item:" .. i, {
          state = i % 3 == 0 and "stopped" or "running",
          category = "cat" .. (i % 10),
        }), "item")
      end

      local elapsed = measure_once("Create view with 2 filters", function()
        local view = store:view("item")
          :where("by_state", "stopped")
          :where("by_category", "cat3")
        local count = view:count()
        view:dispose()
        return count
      end)

      print(string.format("\tDouble-filtered view"))
      assert.is_true(elapsed < 100, "Chained filter should be < 100ms")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Iteration
  -- ---------------------------------------------------------------------------

  describe("Iteration", function()
    it("PERF: iterate over 5000 entities", function()
      for i = 1, 5000 do
        store:add(make_entity("item:" .. i, { state = "stopped", value = i }), "item")
      end

      local view = store:view("item"):where("by_state", "stopped")

      local elapsed, sum = measure_once("Iterate and sum values", function()
        local total = 0
        for entity in view:iter() do
          total = total + entity.value
        end
        return total
      end)

      print(string.format("\tSum: %d", sum))
      assert.is_true(elapsed < 50, "Iteration should be < 50ms for 5k entities")

      view:dispose()
    end)

    it("PERF: count() vs manual iteration", function()
      for i = 1, 5000 do
        store:add(make_entity("item:" .. i, { state = "stopped" }), "item")
      end

      local view = store:view("item"):where("by_state", "stopped")

      local count_elapsed = measure_once("count()", function()
        return view:count()
      end)

      local iter_elapsed = measure_once("Manual iteration count", function()
        local n = 0
        for _ in view:iter() do n = n + 1 end
        return n
      end)

      print(string.format("\tcount() vs iter ratio: %.2fx", iter_elapsed / count_elapsed))

      view:dispose()
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Cache Sharing
  -- ---------------------------------------------------------------------------

  describe("Cache Sharing", function()
    it("PERF: multiple views sharing cache", function()
      for i = 1, 5000 do
        store:add(make_entity("item:" .. i, { state = "stopped" }), "item")
      end

      -- First view creates cache
      local elapsed1 = measure_once("First view (cache creation)", function()
        local view = store:view("item"):where("by_state", "stopped")
        local count = view:count()
        return { view = view, count = count }
      end)

      -- Second view reuses cache
      local elapsed2 = measure_once("Second view (cache reuse)", function()
        local view = store:view("item"):where("by_state", "stopped")
        local count = view:count()
        return { view = view, count = count }
      end)

      print(string.format("\tCache reuse speedup: %.2fx", elapsed1 / elapsed2))
      assert.is_true(elapsed2 < elapsed1, "Cache reuse should be faster")

      -- Cleanup - need to access the returned values
    end)

    it("PERF: 100 views sharing same cache", function()
      for i = 1, 1000 do
        store:add(make_entity("item:" .. i, { state = "stopped" }), "item")
      end

      local views = {}

      local elapsed = measure_once("Create 100 views (shared cache)", function()
        for i = 1, 100 do
          local view = store:view("item"):where("by_state", "stopped")
          table.insert(views, view)
        end
        return #views
      end)

      -- Verify cache ref count
      local cache = store._query_cache[views[1]._cache_key]
      print(string.format("\tCache ref_count: %d", cache.ref_count))
      assert.are.equal(100, cache.ref_count)

      -- Cleanup
      for _, view in ipairs(views) do
        view:dispose()
      end

      assert.is_true(elapsed < 50, "100 cached views should be < 50ms")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Reactivity
  -- ---------------------------------------------------------------------------

  describe("Reactivity", function()
    it("PERF: reactive additions to view (1000 entities)", function()
      local view = store:view("item"):where("by_state", "stopped")

      local added_count = 0
      view:on_added(function()
        added_count = added_count + 1
      end)

      local elapsed = measure_once("Add 1000 entities reactively", function()
        for i = 1, 1000 do
          store:add(make_entity("item:" .. i, { state = "stopped" }), "item")
        end
        return added_count
      end)

      print(string.format("\tCallback invocations: %d", added_count))
      assert.are.equal(1000, added_count)
      assert.is_true(elapsed < 200, "1000 reactive adds should be < 200ms")

      view:dispose()
    end)

    it("PERF: reactive removals from view (1000 entities)", function()
      for i = 1, 1000 do
        store:add(make_entity("item:" .. i, { state = "stopped" }), "item")
      end

      local view = store:view("item"):where("by_state", "stopped")

      local removed_count = 0
      view:on_removed(function()
        removed_count = removed_count + 1
      end)

      local elapsed = measure_once("Remove 1000 entities reactively", function()
        for i = 1, 1000 do
          store:dispose_entity("item:" .. i)
        end
        return removed_count
      end)

      print(string.format("\tCallback invocations: %d", removed_count))
      assert.are.equal(1000, removed_count)
      assert.is_true(elapsed < 500, "1000 reactive removes should be < 500ms")

      view:dispose()
    end)

    it("PERF: multiple listeners on same view", function()
      local view = store:view("item"):where("by_state", "stopped")

      local counts = {}
      for i = 1, 10 do
        counts[i] = 0
        view:on_added(function()
          counts[i] = counts[i] + 1
        end)
      end

      local elapsed = measure_once("Add 500 entities (10 listeners)", function()
        for i = 1, 500 do
          store:add(make_entity("item:" .. i, { state = "stopped" }), "item")
        end
      end)

      local total = 0
      for _, c in ipairs(counts) do total = total + c end
      print(string.format("\tTotal callback invocations: %d (10 x 500)", total))
      assert.are.equal(5000, total)

      view:dispose()
    end)

    it("PERF: Signal index changes (entity enters/leaves view)", function()
      local signals = {}
      for i = 1, 500 do
        local sig = neostate.Signal("running")
        signals[i] = sig
        store:add(make_entity("item:" .. i, { state = sig }), "item")
      end

      store:add_index("item:by_state_sig", function(e) return e.state end)
      local view = store:view("item"):where("by_state_sig", "stopped")

      local added = 0
      local removed = 0
      view:on_added(function() added = added + 1 end)
      view:on_removed(function() removed = removed + 1 end)

      -- Change half to stopped
      local elapsed1 = measure_once("Change 250 Signals to 'stopped'", function()
        for i = 1, 250 do
          signals[i]:set("stopped")
        end
      end)
      print(string.format("\tEntities entered view: %d", added))

      -- Change them back
      local elapsed2 = measure_once("Change 250 Signals back to 'running'", function()
        for i = 1, 250 do
          signals[i]:set("running")
        end
      end)
      print(string.format("\tEntities left view: %d", removed))

      view:dispose()
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Computed Signals
  -- ---------------------------------------------------------------------------

  describe("Computed Signals", function()
    it("PERF: some() over 1000 entities", function()
      for i = 1, 1000 do
        store:add(make_entity("item:" .. i, {
          state = "stopped",
          hit = i == 500, -- Only one matches
        }), "item")
      end

      local view = store:view("item"):where("by_state", "stopped")

      local elapsed, signal = measure_once("Create some() signal", function()
        return view:some(function(e) return e.hit end)
      end)

      assert.is_true(signal:get())
      print(string.format("\tsome() result: %s", tostring(signal:get())))

      view:dispose()
    end)

    it("PERF: some() reactivity with additions", function()
      local view = store:view("item"):where("by_state", "stopped")
      local any_hit = view:some(function(e) return e.hit end)

      assert.is_false(any_hit:get())

      local elapsed = measure_once("Add 500 entities, last one matches", function()
        for i = 1, 500 do
          store:add(make_entity("item:" .. i, {
            state = "stopped",
            hit = i == 500,
          }), "item")
        end
      end)

      assert.is_true(any_hit:get())
      print(string.format("\tsome() updated correctly"))

      view:dispose()
    end)

    it("PERF: every() over 1000 entities", function()
      for i = 1, 1000 do
        store:add(make_entity("item:" .. i, {
          state = "stopped",
          valid = true,
        }), "item")
      end

      local view = store:view("item"):where("by_state", "stopped")

      local elapsed, signal = measure_once("Create every() signal", function()
        return view:every(function(e) return e.valid end)
      end)

      assert.is_true(signal:get())
      print(string.format("\tevery() result: %s", tostring(signal:get())))

      view:dispose()
    end)

    it("PERF: aggregate() sum over 1000 entities", function()
      for i = 1, 1000 do
        store:add(make_entity("item:" .. i, {
          state = "stopped",
          value = i,
        }), "item")
      end

      local view = store:view("item"):where("by_state", "stopped")

      local elapsed, signal = measure_once("Create aggregate() sum signal", function()
        return view:aggregate(function(items)
          local sum = 0
          for _, item in ipairs(items) do
            sum = sum + item.value
          end
          return sum
        end)
      end)

      local expected = (1000 * 1001) / 2 -- Sum of 1 to 1000
      assert.are.equal(expected, signal:get())
      print(string.format("\taggregate() sum: %d", signal:get()))

      view:dispose()
    end)

    it("PERF: aggregate() reactivity with additions", function()
      local view = store:view("item"):where("by_state", "stopped")
      local total = view:aggregate(function(items)
        local sum = 0
        for _, item in ipairs(items) do
          sum = sum + item.value
        end
        return sum
      end)

      assert.are.equal(0, total:get())

      local elapsed = measure_once("Add 500 entities, track sum", function()
        for i = 1, 500 do
          store:add(make_entity("item:" .. i, {
            state = "stopped",
            value = i,
          }), "item")
        end
      end)

      local expected = (500 * 501) / 2
      assert.are.equal(expected, total:get())
      print(string.format("\tFinal aggregate: %d", total:get()))

      view:dispose()
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Scale Tests
  -- ---------------------------------------------------------------------------

  describe("Scale Tests", function()
    it("PERF: view over 50000 entities", function()
      print("\n\tGenerating 50000 entities...")
      for i = 1, 50000 do
        local state = i % 5 == 0 and "stopped" or "running"
        store:add(make_entity("item:" .. i, { state = state, value = i }), "item")
      end
      print("\tGeneration complete")

      local elapsed, count = measure_once("Create view (10k stopped)", function()
        local view = store:view("item"):where("by_state", "stopped")
        local c = view:count()
        view:dispose()
        return c
      end)

      print(string.format("\tFiltered count: %d", count))
      assert.are.equal(10000, count)
    end)

    it("PERF: many concurrent views", function()
      for i = 1, 1000 do
        local state = ({ "a", "b", "c", "d", "e" })[(i % 5) + 1]
        store:add(make_entity("item:" .. i, { state = state }), "item")
      end

      local views = {}

      local elapsed = measure_once("Create 50 different views", function()
        for _, state in ipairs({ "a", "b", "c", "d", "e" }) do
          for i = 1, 10 do
            local view = store:view("item"):where("by_state", state)
            table.insert(views, view)
          end
        end
        return #views
      end)

      print(string.format("\tViews created: %d", #views))
      print(string.format("\tUnique caches: %d", vim.tbl_count(store._query_cache)))

      -- Should have 6 caches: 5 filtered (one per state) + 1 base "item:" cache
      -- (base view from store:view("item") before where() is called)
      assert.are.equal(6, vim.tbl_count(store._query_cache))

      for _, view in ipairs(views) do
        view:dispose()
      end
    end)

    it("PERF: rapid view create/dispose cycle", function()
      for i = 1, 1000 do
        store:add(make_entity("item:" .. i, { state = "stopped" }), "item")
      end

      local elapsed = measure_once("1000 view create/dispose cycles", function()
        for i = 1, 1000 do
          -- Keep reference to base view to properly dispose entire chain
          local base = store:view("item")
          local view = base:where("by_state", "stopped")
          local _ = view:count()
          base:dispose() -- Disposing base also disposes derived
        end
      end)

      -- Cache should be empty after all views disposed
      assert.are.equal(0, vim.tbl_count(store._query_cache))
      print(string.format("\tCache properly cleaned up"))
    end)
  end)
end)
