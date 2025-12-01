-- Test Collection indexes with subcollections and signal-valued indexes

local neostate = require("neostate")

neostate.setup({
  debug_context = true,
  trace = false,
})

describe("Collection Indexes", function()
  describe("Basic indexing", function()
    it("should index items by static values", function()
      local collection = neostate.Collection("items")
      collection:add_index("by_id", function(item) return item.id end)
      collection:add_index("by_name", function(item) return item.name end)

      local item1 = neostate.Disposable({ id = 1, name = "foo" })
      local item2 = neostate.Disposable({ id = 2, name = "bar" })
      local item3 = neostate.Disposable({ id = 3, name = "foo" })

      collection:add(item1)
      collection:add(item2)
      collection:add(item3)

      -- Query by unique key
      assert.are.equal(item1, collection:get_one("by_id", 1))
      assert.are.equal(item2, collection:get_one("by_id", 2))

      -- Query by non-unique key (multiple items with same name)
      local foos = collection:get("by_name", "foo")
      assert.are.equal(2, #foos)
      assert.is_true(vim.tbl_contains(foos, item1))
      assert.is_true(vim.tbl_contains(foos, item3))

      collection:dispose()
    end)

    it("should index items by signal values (reactive indexes)", function()
      local collection = neostate.Collection("items")
      collection:add_index("by_status", function(item) return item.status end)

      local item = neostate.Disposable({})
      item.status = neostate.Signal("pending")
      item.status:set_parent(item)

      collection:add(item)

      -- Initial value
      assert.are.equal(item, collection:get_one("by_status", "pending"))
      assert.is_nil(collection:get_one("by_status", "done"))

      -- Change signal - index should update
      item.status:set("done")

      assert.is_nil(collection:get_one("by_status", "pending"))
      assert.are.equal(item, collection:get_one("by_status", "done"))

      collection:dispose()
    end)

    it("should handle multiple items with same signal-based key", function()
      local collection = neostate.Collection("items")
      collection:add_index("by_status", function(item) return item.status end)

      local item1 = neostate.Disposable({})
      item1.status = neostate.Signal("pending")
      item1.status:set_parent(item1)

      local item2 = neostate.Disposable({})
      item2.status = neostate.Signal("pending")
      item2.status:set_parent(item2)

      collection:add(item1)
      collection:add(item2)

      -- Both should be indexed under "pending"
      local pending = collection:get("by_status", "pending")
      assert.are.equal(2, #pending)
      assert.is_true(vim.tbl_contains(pending, item1))
      assert.is_true(vim.tbl_contains(pending, item2))

      -- Change one item's status
      item1.status:set("done")

      -- Now only item2 should be under "pending"
      pending = collection:get("by_status", "pending")
      assert.are.equal(1, #pending)
      assert.are.equal(item2, pending[1])

      -- item1 should be under "done"
      local done = collection:get("by_status", "done")
      assert.are.equal(1, #done)
      assert.are.equal(item1, done[1])

      collection:dispose()
    end)
  end)

  describe("Filtered subcollections", function()
    it("should inherit parent indexes with separate maps", function()
      local parent = neostate.Collection("parent")
      parent:add_index("by_id", function(item) return item.id end)
      parent:add_index("by_type", function(item) return item.type end)

      local item1 = neostate.Disposable({ id = 1, type = "A" })
      local item2 = neostate.Disposable({ id = 2, type = "B" })
      local item3 = neostate.Disposable({ id = 3, type = "A" })

      parent:add(item1)
      parent:add(item2)
      parent:add(item3)

      -- Create filtered subcollection
      local typeA = parent:where("by_type", "A", "typeA")

      -- Subcollection should only contain type A items
      assert.are.equal(2, #typeA._items)

      -- Query subcollection's index - should only return items in subcollection
      assert.are.equal(item1, typeA:get_one("by_id", 1))
      assert.is_nil(typeA:get_one("by_id", 2))  -- item2 is type B
      assert.are.equal(item3, typeA:get_one("by_id", 3))

      -- Parent index should have all items
      assert.are.equal(item1, parent:get_one("by_id", 1))
      assert.are.equal(item2, parent:get_one("by_id", 2))
      assert.are.equal(item3, parent:get_one("by_id", 3))

      parent:dispose()
    end)

    it("should maintain separate index maps when items are added", function()
      local parent = neostate.Collection("parent")
      parent:add_index("by_type", function(item) return item.type end)
      parent:add_index("by_name", function(item) return item.name end)

      local typeA = parent:where("by_type", "A", "typeA")

      -- Add items after subcollection is created
      local item1 = neostate.Disposable({ type = "A", name = "alice" })
      local item2 = neostate.Disposable({ type = "B", name = "bob" })
      local item3 = neostate.Disposable({ type = "A", name = "adam" })

      parent:add(item1)
      parent:add(item2)
      parent:add(item3)

      -- Parent should have all items indexed by name
      assert.are.equal(item1, parent:get_one("by_name", "alice"))
      assert.are.equal(item2, parent:get_one("by_name", "bob"))
      assert.are.equal(item3, parent:get_one("by_name", "adam"))

      -- Subcollection should only have type A items indexed
      assert.are.equal(item1, typeA:get_one("by_name", "alice"))
      assert.is_nil(typeA:get_one("by_name", "bob"))  -- bob is type B
      assert.are.equal(item3, typeA:get_one("by_name", "adam"))

      parent:dispose()
    end)

    it("should update subcollection indexes when signal values change", function()
      local parent = neostate.Collection("parent")
      parent:add_index("by_session", function(item) return item.session end)
      parent:add_index("by_location", function(item) return item.location end)

      local session1 = parent:where("by_session", "session1", "session1")

      -- Add item with signal-valued location
      local item = neostate.Disposable({ session = "session1" })
      item.location = neostate.Signal("file.py:10")
      item.location:set_parent(item)

      parent:add(item)

      -- Should be indexed in parent
      assert.are.equal(item, parent:get_one("by_location", "file.py:10"))
      assert.is_nil(parent:get_one("by_location", "file.py:9"))

      -- Should be indexed in subcollection
      assert.are.equal(item, session1:get_one("by_location", "file.py:10"))
      assert.is_nil(session1:get_one("by_location", "file.py:9"))

      -- Change location signal
      item.location:set("file.py:9")

      -- Parent index should update
      assert.is_nil(parent:get_one("by_location", "file.py:10"))
      assert.are.equal(item, parent:get_one("by_location", "file.py:9"))

      -- Subcollection index should ALSO update
      assert.is_nil(session1:get_one("by_location", "file.py:10"))
      assert.are.equal(item, session1:get_one("by_location", "file.py:9"))

      parent:dispose()
    end)

    it("should handle multiple subcollections with same filter key", function()
      local parent = neostate.Collection("parent")
      parent:add_index("by_session", function(item) return item.session end)
      parent:add_index("by_location", function(item) return item.location end)

      local session1 = parent:where("by_session", "session1", "session1")
      local session2 = parent:where("by_session", "session2", "session2")

      -- Add items with signal-valued location
      local item1 = neostate.Disposable({ session = "session1" })
      item1.location = neostate.Signal("file.py:10")
      item1.location:set_parent(item1)

      local item2 = neostate.Disposable({ session = "session2" })
      item2.location = neostate.Signal("file.py:10")
      item2.location:set_parent(item2)

      parent:add(item1)
      parent:add(item2)

      -- Both items have same location, but different sessions
      -- Parent should see both
      local all_at_location = parent:get("by_location", "file.py:10")
      assert.are.equal(2, #all_at_location)

      -- Each subcollection should only see its own item
      assert.are.equal(item1, session1:get_one("by_location", "file.py:10"))
      assert.are.equal(item2, session2:get_one("by_location", "file.py:10"))

      -- Change item1's location
      item1.location:set("file.py:9")

      -- session1 should now find item1 at new location
      assert.is_nil(session1:get_one("by_location", "file.py:10"))
      assert.are.equal(item1, session1:get_one("by_location", "file.py:9"))

      -- session2 should still find item2 at old location
      assert.are.equal(item2, session2:get_one("by_location", "file.py:10"))
      assert.is_nil(session2:get_one("by_location", "file.py:9"))

      parent:dispose()
    end)
  end)

  describe("Index cleanup", function()
    it("should remove items from indexes when removed from collection", function()
      local collection = neostate.Collection("items")
      collection:add_index("by_id", function(item) return item.id end)

      local item = neostate.Disposable({ id = 1 })
      collection:add(item)

      assert.are.equal(item, collection:get_one("by_id", 1))

      -- Remove item
      collection:delete(function(i) return i.id == 1 end)

      assert.is_nil(collection:get_one("by_id", 1))

      collection:dispose()
    end)

    it("should stop watching signal when item is removed", function()
      local collection = neostate.Collection("items")
      collection:add_index("by_status", function(item) return item.status end)

      local item = neostate.Disposable({})
      item.status = neostate.Signal("pending")
      item.status:set_parent(item)

      collection:add(item)
      assert.are.equal(item, collection:get_one("by_status", "pending"))

      -- Remove item
      collection:delete(function(i) return i == item end)

      -- Change signal after removal - index should NOT update
      item.status:set("done")

      -- Should not be in index under either key
      assert.is_nil(collection:get_one("by_status", "pending"))
      assert.is_nil(collection:get_one("by_status", "done"))

      collection:dispose()
      item:dispose()
    end)
  end)
end)
