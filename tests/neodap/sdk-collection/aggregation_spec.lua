-- Test Collection aggregation methods (aggregate, some, every)

local neostate = require("neostate")

neostate.setup({
  debug_context = true,
  trace = false,
})

describe("Collection Aggregation", function()
  describe("aggregate()", function()
    it("should compute initial aggregate value", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ value = 10 })
      local item2 = neostate.Disposable({ value = 20 })
      local item3 = neostate.Disposable({ value = 30 })

      collection:add(item1)
      collection:add(item2)
      collection:add(item3)

      -- Sum all values
      local sum = collection:aggregate(function(items)
        local total = 0
        for _, item in ipairs(items) do
          total = total + item.value
        end
        return total
      end)

      assert.are.equal(60, sum:get())

      collection:dispose()
    end)

    it("should update when items are added", function()
      local collection = neostate.Collection("items")

      local sum = collection:aggregate(function(items)
        local total = 0
        for _, item in ipairs(items) do
          total = total + item.value
        end
        return total
      end)

      assert.are.equal(0, sum:get())

      collection:add(neostate.Disposable({ value = 5 }))
      assert.are.equal(5, sum:get())

      collection:add(neostate.Disposable({ value = 15 }))
      assert.are.equal(20, sum:get())

      collection:dispose()
    end)

    it("should update when items are removed", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ id = 1, value = 10 })
      local item2 = neostate.Disposable({ id = 2, value = 20 })

      collection:add(item1)
      collection:add(item2)

      local sum = collection:aggregate(function(items)
        local total = 0
        for _, item in ipairs(items) do
          total = total + item.value
        end
        return total
      end)

      assert.are.equal(30, sum:get())

      collection:delete(function(item) return item.id == 1 end)
      assert.are.equal(20, sum:get())

      collection:dispose()
    end)

    it("should watch signals on items when signal_getter provided", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({})
      item1.status = neostate.Signal("pending")
      item1.status:set_parent(item1)

      local item2 = neostate.Disposable({})
      item2.status = neostate.Signal("done")
      item2.status:set_parent(item2)

      collection:add(item1)
      collection:add(item2)

      -- Count how many items are "done"
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

      assert.are.equal(1, done_count:get())

      -- Change item1 status to "done"
      item1.status:set("done")
      assert.are.equal(2, done_count:get())

      -- Change item2 status to "pending"
      item2.status:set("pending")
      assert.are.equal(1, done_count:get())

      collection:dispose()
    end)

    it("should setup signal watchers for items added after aggregate created", function()
      local collection = neostate.Collection("items")

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

      -- Add item after aggregate was created
      local item = neostate.Disposable({})
      item.status = neostate.Signal("pending")
      item.status:set_parent(item)
      collection:add(item)

      assert.are.equal(0, done_count:get())

      -- Change its status - should update aggregate
      item.status:set("done")
      assert.are.equal(1, done_count:get())

      collection:dispose()
    end)
  end)

  describe("some()", function()
    it("should return true if any item matches predicate", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ status = "pending" })
      local item2 = neostate.Disposable({ status = "done" })

      collection:add(item1)
      collection:add(item2)

      local has_done = collection:some(function(item)
        return item.status == "done"
      end)

      assert.is_true(has_done:get())

      collection:dispose()
    end)

    it("should return false if no items match predicate", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ status = "pending" })
      local item2 = neostate.Disposable({ status = "pending" })

      collection:add(item1)
      collection:add(item2)

      local has_done = collection:some(function(item)
        return item.status == "done"
      end)

      assert.is_false(has_done:get())

      collection:dispose()
    end)

    it("should update when signal-based predicate changes", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({})
      item1.active = neostate.Signal(false)
      item1.active:set_parent(item1)

      local item2 = neostate.Disposable({})
      item2.active = neostate.Signal(false)
      item2.active:set_parent(item2)

      collection:add(item1)
      collection:add(item2)

      local has_active = collection:some(function(item)
        return item.active
      end)

      assert.is_false(has_active:get())

      -- Activate item1
      item1.active:set(true)
      assert.is_true(has_active:get())

      -- Deactivate item1
      item1.active:set(false)
      assert.is_false(has_active:get())

      collection:dispose()
    end)

    it("should work with items added after some() created", function()
      local collection = neostate.Collection("items")

      local has_active = collection:some(function(item)
        return item.active
      end)

      assert.is_false(has_active:get())

      local item = neostate.Disposable({})
      item.active = neostate.Signal(true)
      item.active:set_parent(item)
      collection:add(item)

      assert.is_true(has_active:get())

      collection:dispose()
    end)
  end)

  describe("every()", function()
    it("should return true if all items match predicate", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ verified = true })
      local item2 = neostate.Disposable({ verified = true })

      collection:add(item1)
      collection:add(item2)

      local all_verified = collection:every(function(item)
        return item.verified == true
      end)

      assert.is_true(all_verified:get())

      collection:dispose()
    end)

    it("should return false if any item doesn't match predicate", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({ verified = true })
      local item2 = neostate.Disposable({ verified = false })

      collection:add(item1)
      collection:add(item2)

      local all_verified = collection:every(function(item)
        return item.verified == true
      end)

      assert.is_false(all_verified:get())

      collection:dispose()
    end)

    it("should update when signal-based predicate changes", function()
      local collection = neostate.Collection("items")

      local item1 = neostate.Disposable({})
      item1.ready = neostate.Signal(true)
      item1.ready:set_parent(item1)

      local item2 = neostate.Disposable({})
      item2.ready = neostate.Signal(true)
      item2.ready:set_parent(item2)

      collection:add(item1)
      collection:add(item2)

      local all_ready = collection:every(function(item)
        return item.ready
      end)

      assert.is_true(all_ready:get())

      -- Mark item1 as not ready
      item1.ready:set(false)
      assert.is_false(all_ready:get())

      -- Mark item1 as ready again
      item1.ready:set(true)
      assert.is_true(all_ready:get())

      collection:dispose()
    end)

    it("should return true for empty collection", function()
      local collection = neostate.Collection("items")

      local all_ready = collection:every(function(item)
        return item.ready
      end)

      assert.is_true(all_ready:get())

      collection:dispose()
    end)
  end)

  describe("Use case: breakpoint.hit derived from bindings", function()
    it("should compute hit state from bindings", function()
      local bindings = neostate.Collection("bindings")

      local binding1 = neostate.Disposable({})
      binding1.hit = neostate.Signal(false)
      binding1.hit:set_parent(binding1)

      local binding2 = neostate.Disposable({})
      binding2.hit = neostate.Signal(false)
      binding2.hit:set_parent(binding2)

      bindings:add(binding1)
      bindings:add(binding2)

      -- Compute if any binding is hit
      local is_hit = bindings:some(function(binding)
        return binding.hit
      end)

      assert.is_false(is_hit:get())

      -- Hit binding1
      binding1.hit:set(true)
      assert.is_true(is_hit:get())

      -- Hit binding2 as well
      binding2.hit:set(true)
      assert.is_true(is_hit:get())

      -- Unhit binding1 (binding2 still hit)
      binding1.hit:set(false)
      assert.is_true(is_hit:get())

      -- Unhit binding2 (none hit)
      binding2.hit:set(false)
      assert.is_false(is_hit:get())

      bindings:dispose()
    end)
  end)
end)
