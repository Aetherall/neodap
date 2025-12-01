local neostate = require("neostate")

neostate.setup({
  -- trace = true,
  -- debug_context = true,
})

describe("neostate", function()
  describe("Disposable", function()
    it("should run cleanup functions on dispose", function()
      local d = neostate.Disposable({}, nil, "TestDisposable")
      local cleaned_up = false
      d:on_dispose(function() cleaned_up = true end)

      d:dispose()
      assert.is_true(cleaned_up)
    end)

    it("should dispose in LIFO order", function()
      local d = neostate.Disposable({}, nil, "TestLIFO")
      local order = {}
      d:on_dispose(function() table.insert(order, 1) end)
      d:on_dispose(function() table.insert(order, 2) end)

      d:dispose()
      assert.are.same({ 2, 1 }, order)
    end)

    it("should handle errors in dispose gracefully", function()
      local d = neostate.Disposable({}, nil, "TestError")
      d:on_dispose(function() error("Boom") end)
      local cleaned_up = false
      d:on_dispose(function() cleaned_up = true end)

      assert.has_no_error(function() d:dispose() end)
      assert.is_true(cleaned_up)
    end)
  end)

  describe("Signal", function()
    it("should hold a value and update it", function()
      local s = neostate.Signal(10, "TestSignal")
      assert.are.equal(10, s:get())
      s:set(20)
      assert.are.equal(20, s:get())
    end)

    it("should trigger effects on change", function()
      local s = neostate.Signal(0, "TestEffect")
      local last_val = nil

      s:use(function(val)
        last_val = val
      end)

      -- Effects run synchronously now
      assert.are.equal(0, last_val)

      s:set(1)
      assert.are.equal(1, last_val)
    end)

    it("should cleanup effects before new run", function()
      local s = neostate.Signal(0, "TestEffectCleanup")
      local cleanup_count = 0

      s:use(function()
        return function() cleanup_count = cleanup_count + 1 end
      end)

      -- Initial run happened
      s:set(1)
      -- Update triggers cleanup of previous

      assert.are.equal(1, cleanup_count)
    end)
  end)

  describe("Computed", function()
    it("should derive value from dependencies", function()
      local a = neostate.Signal(1, "a")
      local b = neostate.Signal(2, "b")

      local sum = neostate.computed(function()
        return a:get() + b:get()
      end, { a, b }, "sum")

      assert.are.equal(3, sum:get())
    end)

    it("should update when dependencies change", function()
      local a = neostate.Signal(1, "a")
      local b = neostate.Signal(2, "b")

      local sum = neostate.computed(function()
        return a:get() + b:get()
      end, { a, b }, "sum")

      assert.are.equal(3, sum:get())

      a:set(10)
      assert.are.equal(12, sum:get())

      b:set(20)
      assert.are.equal(30, sum:get())
    end)

    it("should support watching computed values", function()
      local a = neostate.Signal(1, "a")
      local b = neostate.Signal(2, "b")

      local sum = neostate.computed(function()
        return a:get() + b:get()
      end, { a, b }, "sum")

      local observed = {}
      sum:watch(function(val)
        table.insert(observed, val)
      end)

      a:set(10)  -- sum = 12
      b:set(20)  -- sum = 30

      assert.are.same({ 12, 30 }, observed)
    end)

    it("should support use() on computed values", function()
      local a = neostate.Signal(5, "a")

      local doubled = neostate.computed(function()
        return a:get() * 2
      end, { a }, "doubled")

      local observed = {}
      doubled:use(function(val)
        table.insert(observed, val)
      end)

      -- use() should fire immediately with current value
      assert.are.same({ 10 }, observed)

      a:set(7)
      assert.are.same({ 10, 14 }, observed)
    end)

    it("should chain computed signals", function()
      local base = neostate.Signal(2, "base")

      local doubled = neostate.computed(function()
        return base:get() * 2
      end, { base }, "doubled")

      local quadrupled = neostate.computed(function()
        return doubled:get() * 2
      end, { doubled }, "quadrupled")

      assert.are.equal(4, doubled:get())
      assert.are.equal(8, quadrupled:get())

      base:set(5)
      assert.are.equal(10, doubled:get())
      assert.are.equal(20, quadrupled:get())
    end)

    it("should dispose properly", function()
      local a = neostate.Signal(1, "a")

      local doubled = neostate.computed(function()
        return a:get() * 2
      end, { a }, "doubled")

      assert.are.equal(2, doubled:get())

      doubled:dispose()

      -- After dispose, changes to dependency should not affect disposed computed
      a:set(10)
      -- doubled is disposed, its internal state is cleared
      assert.is_true(doubled._disposed)
    end)

    it("should handle nil dependencies gracefully", function()
      local a = neostate.Signal(5, "a")

      local computed_val = neostate.computed(function()
        return a:get() + 1
      end, { a, nil, "not a signal" }, "computed")

      assert.are.equal(6, computed_val:get())

      a:set(10)
      assert.are.equal(11, computed_val:get())
    end)
  end)

  describe("List", function()
    it("should add and remove items", function()
      local l = neostate.List("TestList")
      local c = neostate.Disposable({ id = 1 })
      local item = l:add(c)

      assert.are.equal(1, #l._items)
      assert.are.equal(1, item.id)

      l:delete(function(item) return item.id == 1 end)
      assert.are.equal(0, #l._items)
    end)

    it("should notify listeners on add", function()
      local l = neostate.List("TestListAdd")
      local added_item = nil
      l:on_added(function(item) added_item = item end)

      l:add(neostate.Disposable({ id = 1 }))
      assert.is_not_nil(added_item)
      assert.are.equal(1, added_item.id)
    end)

    it("should run cleanup on remove", function()
      local l = neostate.List("TestListRemove")
      local cleaned_up = false
      l:on_removed(function() cleaned_up = true end)

      l:add(neostate.Disposable({ id = 1 }))
      l:delete(function(item) return item.id == 1 end)

      assert.is_true(cleaned_up)
    end)

    it("should run cleanup on extract", function()
      local l = neostate.List("TestListExtract")
      local cleaned_up = false
      l:on_removed(function() cleaned_up = true end)

      l:add(neostate.Disposable({ id = 1 }))
      l:extract(function(item) return item.id == 1 end)

      assert.is_true(cleaned_up)
    end)

    it("should allow moving items between lists", function()
      local l1 = neostate.List("List1")
      local l2 = neostate.List("List2")

      local item = l1:add(neostate.Disposable({ id = 1 }))

      -- Remove from l1 without disposing
      local removed = l1:extract(function(d) return d.id == 1 end)
      assert.are.equal(item, removed)
      assert.is_false(item._disposed)

      -- Adopt into l2
      l2:adopt(item)

      local count = 0
      l2:iter():each(function(i)
        if i == item then count = count + 1 end
      end)
      assert.are.equal(1, count)

      -- Disposing l2 should dispose item
      l2:dispose()
      assert.is_true(item._disposed)
    end)

    it("should adopt existing disposables when added", function()
      local l = neostate.List("TestListAdopt")
      local c = neostate.Disposable({ id = 1 }, nil, "ExistingComponent")

      l:add(c)

      assert.are.equal(1, #l._items)
      assert.are.equal(c, l._items[1])

      -- Verify parenting
      local disposed = false
      c:on_dispose(function() disposed = true end)
      l:dispose()
      assert.is_true(disposed)
    end)

    it("should provide reactive latest() signal", function()
      local l = neostate.List("TestLatest")

      -- Get latest signal before any items
      local latest = l:latest()
      assert.is_nil(latest:get())

      -- Add first item
      local item1 = l:add(neostate.Disposable({ id = 1 }))
      assert.are.equal(item1, latest:get())

      -- Add second item - latest should update
      local item2 = l:add(neostate.Disposable({ id = 2 }))
      assert.are.equal(item2, latest:get())

      -- Add third item
      local item3 = l:add(neostate.Disposable({ id = 3 }))
      assert.are.equal(item3, latest:get())

      -- Remove latest - should fall back to previous
      l:delete(function(d) return d.id == 3 end)
      assert.are.equal(item2, latest:get())

      -- Remove non-latest - latest should stay same
      l:delete(function(d) return d.id == 1 end)
      assert.are.equal(item2, latest:get())

      -- Remove last item - should become nil
      l:delete(function(d) return d.id == 2 end)
      assert.is_nil(latest:get())
    end)

    it("should allow watching latest() signal", function()
      local l = neostate.List("TestLatestWatch")
      local latest = l:latest()

      local observed = {}
      latest:watch(function(item)
        table.insert(observed, item and item.id or "nil")
      end)

      l:add(neostate.Disposable({ id = 1 }))
      l:add(neostate.Disposable({ id = 2 }))
      l:delete(function(d) return d.id == 2 end)

      assert.are.same({ 1, 2, 1 }, observed)
    end)
  end)

  describe("Set", function()
    it("should add and remove items by reference", function()
      local c = neostate.Set("TestSet")
      local item = c:add(neostate.Disposable({ id = 1 }))

      local count = 0
      c:iter():each(function() count = count + 1 end)
      assert.are.equal(1, count)

      c:remove(item)

      count = 0
      c:iter():each(function() count = count + 1 end)
      assert.are.equal(0, count)
    end)

    it("should notify listeners", function()
      local c = neostate.Set("TestSetListeners")
      local added_item = nil
      local cleaned_up = false

      c:subscribe(function(item)
        added_item = item
        return function() cleaned_up = true end
      end)

      local item = c:add(neostate.Disposable({ id = 1 }))
      assert.are.equal(item, added_item)

      c:remove(item)
      assert.is_true(cleaned_up)
    end)
  end)

  describe("Disposable Parenting", function()
    it("should auto-dispose children when parent dies", function()
      local parent = neostate.Disposable({}, nil, "Parent")
      local child = neostate.Disposable({}, parent, "Child")

      local child_disposed = false
      child:on_dispose(function() child_disposed = true end)

      parent:dispose()
      assert.is_true(child_disposed)
    end)

    it("should maintain parenting across async boundaries using bind", function()
      local parent = neostate.Disposable({}, nil, "AsyncParent")
      local child_disposed = false

      -- Simulate async work
      local async_fn = parent:bind(function()
        local child = neostate.Disposable({}, nil, "AsyncChild")
        child:on_dispose(function() child_disposed = true end)
      end)

      vim.schedule(async_fn)
      vim.wait(10) -- Wait for schedule

      parent:dispose()
      assert.is_true(child_disposed)
    end)

    it("should allow async child creation in list listeners if bound", function()
      local l = neostate.List("AsyncList")
      local child_disposed = false

      l:subscribe(function(item)
        vim.schedule(item:bind(function()
          local child = neostate.Disposable({}, nil, "AsyncListChild")
          child:on_dispose(function() child_disposed = true end)
        end))
      end)

      l:add(neostate.Disposable({}))
      vim.wait(10)                         -- Wait for schedule

      l:delete(function() return true end) -- Should dispose item, and thus child
      assert.is_true(child_disposed)
    end)
  end)
end)
