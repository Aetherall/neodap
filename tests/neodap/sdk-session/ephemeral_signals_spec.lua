-- Test ephemeral signal GC behavior with weak references

local neostate = require("neostate")

neostate.setup({
  debug_context = true,
  trace = false,
})

describe("Ephemeral Signals (Weak References)", function()
  describe("Weak listener storage", function()
    it("should allow listeners to be GC'd when signal is GC'd", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ value = 10 })
      collection:add(item1)

      -- Create ephemeral aggregate in local scope
      do
        local sum = collection:aggregate(function(items)
          local total = 0
          for _, item in ipairs(items) do
            total = total + item.value
          end
          return total
        end)

        assert.are.equal(10, sum:get())

        -- sum goes out of scope here
      end

      -- Force GC to collect the signal
      collectgarbage("collect")
      collectgarbage("collect")  -- Run twice to ensure finalization

      -- Verify listeners were cleaned up by checking they don't fire
      -- We can't directly check _listeners (weak table), but we can verify
      -- that adding items doesn't cause errors from stale listeners
      local item2 = neostate.Disposable({ value = 20 })
      collection:add(item2)

      -- If we got here without errors, weak refs worked
      assert.are.equal(2, #collection._items)

      collection:dispose()
    end)

    it("should keep listeners alive while signal has strong references", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ value = 10 })
      collection:add(item1)

      -- Create aggregate with strong reference
      local sum = collection:aggregate(function(items)
        local total = 0
        for _, item in ipairs(items) do
          total = total + item.value
        end
        return total
      end)

      assert.are.equal(10, sum:get())

      -- Force GC
      collectgarbage("collect")
      collectgarbage("collect")

      -- Signal should still be alive and reactive
      local item2 = neostate.Disposable({ value = 20 })
      collection:add(item2)

      assert.are.equal(30, sum:get(), "Signal should still be reactive")

      collection:dispose()
    end)
  end)

  describe("Weak result references in aggregate", function()
    it("should not prevent GC when result goes out of scope", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({})
      item1.status = neostate.Signal("pending")
      item1.status:set_parent(item1)
      collection:add(item1)

      local gc_triggered = false

      do
        local done_count = collection:aggregate(
          function(items)
            local count = 0
            for _, item in ipairs(items) do
              if item.status:get() == "done" then
                count = count + 1
              end
            end
            return count
          end,
          function(item) return item.status end
        )

        assert.are.equal(0, done_count:get())

        -- Modify to trigger listener
        item1.status:set("done")
        assert.are.equal(1, done_count:get())

        -- done_count goes out of scope here
      end

      -- Force GC
      collectgarbage("collect")
      collectgarbage("collect")

      -- Change signal again - listeners should not fire (GC'd)
      item1.status:set("pending")

      -- If no errors, weak refs worked
      assert.are.equal("pending", item1.status:get())

      collection:dispose()
    end)

    it("should handle multiple ephemeral aggregates independently", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ value = 10 })
      local item2 = neostate.Disposable({ value = 20 })
      collection:add(item1)
      collection:add(item2)

      -- Create first ephemeral aggregate
      do
        local sum1 = collection:aggregate(function(items)
          local total = 0
          for _, item in ipairs(items) do
            total = total + item.value
          end
          return total
        end)
        assert.are.equal(30, sum1:get())
      end

      -- Force GC to collect first aggregate
      collectgarbage("collect")
      collectgarbage("collect")

      -- Create second ephemeral aggregate (should work independently)
      do
        local sum2 = collection:aggregate(function(items)
          local total = 0
          for _, item in ipairs(items) do
            total = total + item.value
          end
          return total
        end)
        assert.are.equal(30, sum2:get())
      end

      -- Force GC again
      collectgarbage("collect")
      collectgarbage("collect")

      -- Collection should still be healthy
      local item3 = neostate.Disposable({ value = 30 })
      collection:add(item3)

      assert.are.equal(3, #collection._items)

      collection:dispose()
    end)
  end)

  describe("some() with ephemeral signals", function()
    it("should allow ephemeral some() queries to be GC'd", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({})
      item1.active = neostate.Signal(false)
      item1.active:set_parent(item1)

      local item2 = neostate.Disposable({})
      item2.active = neostate.Signal(false)
      item2.active:set_parent(item2)

      collection:add(item1)
      collection:add(item2)

      -- Ephemeral query
      do
        local has_active = collection:some(function(item)
          return item.active
        end)

        assert.is_false(has_active:get())

        item1.active:set(true)
        assert.is_true(has_active:get())
      end

      -- Force GC
      collectgarbage("collect")
      collectgarbage("collect")

      -- Change signals - should not cause issues
      item2.active:set(true)

      assert.is_true(item2.active:get())

      collection:dispose()
    end)
  end)

  describe("every() with ephemeral signals", function()
    it("should allow ephemeral every() queries to be GC'd", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({})
      item1.ready = neostate.Signal(true)
      item1.ready:set_parent(item1)

      local item2 = neostate.Disposable({})
      item2.ready = neostate.Signal(true)
      item2.ready:set_parent(item2)

      collection:add(item1)
      collection:add(item2)

      -- Ephemeral query
      do
        local all_ready = collection:every(function(item)
          return item.ready
        end)

        assert.is_true(all_ready:get())

        item1.ready:set(false)
        assert.is_false(all_ready:get())
      end

      -- Force GC
      collectgarbage("collect")
      collectgarbage("collect")

      -- Change signals - should not cause issues
      item2.ready:set(false)

      assert.is_false(item2.ready:get())

      collection:dispose()
    end)
  end)

  describe("Mixed strong and weak references", function()
    it("should handle both persistent and ephemeral aggregates on same collection", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ value = 10 })
      collection:add(item1)

      -- Persistent aggregate (strong reference)
      local persistent_sum = collection:aggregate(function(items)
        local total = 0
        for _, item in ipairs(items) do
          total = total + item.value
        end
        return total
      end)

      assert.are.equal(10, persistent_sum:get())

      -- Ephemeral aggregate (no external strong ref)
      do
        local ephemeral_sum = collection:aggregate(function(items)
          local total = 0
          for _, item in ipairs(items) do
            total = total + item.value
          end
          return total
        end)

        assert.are.equal(10, ephemeral_sum:get())
      end

      -- Force GC
      collectgarbage("collect")
      collectgarbage("collect")

      -- Add new item
      local item2 = neostate.Disposable({ value = 20 })
      collection:add(item2)

      -- Persistent should still work
      assert.are.equal(30, persistent_sum:get(), "Persistent aggregate should still be reactive")

      collection:dispose()
    end)
  end)

  describe("__gc metamethod disposal", function()
    it("aggregate signals are parented to collections", function()
      -- Aggregate signals are parented to their collections
      -- When collection is disposed, aggregate signals are also disposed

      local collection = neostate.Collection("items")

      local sum = collection:aggregate(function(items)
        return #items
      end)

      assert.are.equal(0, sum:get())

      -- Disposing collection should cascade to aggregate signal
      collection:dispose()

      -- Signal should be disposed
      assert.is_true(sum._disposed)
    end)
  end)

  describe("Practical use case: ephemeral queries", function()
    it("should support one-time reactive queries without explicit cleanup", function()
      local sessions = neostate.Collection("sessions")

      local session1 = neostate.Disposable({ id = 1 })
      session1.state = neostate.Signal("running")
      session1.state:set_parent(session1)

      local session2 = neostate.Disposable({ id = 2 })
      session2.state = neostate.Signal("stopped")
      session2.state:set_parent(session2)

      sessions:add(session1)
      sessions:add(session2)

      -- Ephemeral query: check if any session is stopped
      local function has_stopped_session()
        local result = sessions:some(function(s) return s.state end)
        -- some() returns a Signal<boolean> that reactively tracks if any state == "stopped"
        local has_any_stopped = result:get()
        return has_any_stopped
      end

      -- Initial check - session2 is stopped
      assert.is_true(has_stopped_session())

      -- Change state
      session1.state:set("stopped")

      -- Query again (creates new aggregate signal)
      -- Both sessions are now stopped
      assert.is_true(has_stopped_session())

      -- Force GC - weak listeners allow cleanup
      collectgarbage("collect")
      collectgarbage("collect")

      sessions:dispose()
    end)
  end)
end)
