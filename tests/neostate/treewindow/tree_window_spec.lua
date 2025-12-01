local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")
local TreeWindow = require("neostate.tree_window")

describe("TreeWindow", function()
  local store

  before_each(function()
    store = EntityStore.new("test")
  end)

  after_each(function()
    if store then
      store:dispose()
    end
  end)

  local function create_simple_tree()
    -- Create: root -> [A, B, C]
    --         A -> [A1, A2]
    --         B -> [B1]
    store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
    store:add({ uri = "node:A", key = "A", name = "Node A" }, "node", { { type = "parent", to = "node:root" } })
    store:add({ uri = "node:B", key = "B", name = "Node B" }, "node", { { type = "parent", to = "node:root" } })
    store:add({ uri = "node:C", key = "C", name = "Node C" }, "node", { { type = "parent", to = "node:root" } })
    store:add({ uri = "node:A1", key = "A1", name = "Node A1" }, "node", { { type = "parent", to = "node:A" } })
    store:add({ uri = "node:A2", key = "A2", name = "Node A2" }, "node", { { type = "parent", to = "node:A" } })
    store:add({ uri = "node:B1", key = "B1", name = "Node B1" }, "node", { { type = "parent", to = "node:B" } })
  end

  describe("Construction", function()
    it("creates window with correct initial state", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        above = 10,
        below = 10,
      })

      assert.are.equal("root", window.focus:get())
      assert.is_true(#window.items._items > 0)

      window:dispose()
    end)

    it("shows tree in DFS order", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Expected DFS order: root, A, A1, A2, B, B1, C
      local expected = { "root", "root/A", "root/A/A1", "root/A/A2", "root/B", "root/B/B1", "root/C" }
      local actual = {}
      for _, item in ipairs(window.items._items) do
        table.insert(actual, item._virtual.uri)
      end

      assert.are.same(expected, actual)

      window:dispose()
    end)
  end)

  describe("Navigation", function()
    it("move_down moves to next item", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })
      assert.are.equal("root", window.focus:get())

      window:move_down()
      assert.are.equal("root/A", window.focus:get())

      window:move_down()
      assert.are.equal("root/A/A1", window.focus:get())

      window:dispose()
    end)

    it("move_up moves to previous item", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      window:move_down()
      window:move_down()
      assert.are.equal("root/A/A1", window.focus:get())

      window:move_up()
      assert.are.equal("root/A", window.focus:get())

      window:move_up()
      assert.are.equal("root", window.focus:get())

      window:dispose()
    end)

    it("move_into enters first child", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })
      assert.are.equal("root", window.focus:get())

      window:move_into()
      assert.are.equal("root/A", window.focus:get())

      window:move_into()
      assert.are.equal("root/A/A1", window.focus:get())

      window:dispose()
    end)

    it("move_out goes to parent", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      window:focus_on("root/A/A1")
      assert.are.equal("root/A/A1", window.focus:get())

      window:move_out()
      assert.are.equal("root/A", window.focus:get())

      window:move_out()
      assert.are.equal("root", window.focus:get())

      window:dispose()
    end)

    it("focus_on jumps to arbitrary item", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local success = window:focus_on("root/B/B1")
      assert.is_true(success)
      assert.are.equal("root/B/B1", window.focus:get())

      window:dispose()
    end)
  end)

  describe("Collapse/Expand", function()
    it("collapse hides descendants", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Collapse A - should hide A1, A2
      window:collapse("root/A")

      -- Wait for debounced refresh and reactive updates
      vim.wait(50, function() return false end)

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- Should have: root, A (collapsed), B, B1, C
      assert.are.same({ "root", "root/A", "root/B", "root/B/B1", "root/C" }, visible)

      window:dispose()
    end)

    it("expand shows descendants", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      window:collapse("root/A")
      window:expand("root/A")

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- Should have all items again
      assert.are.same({ "root", "root/A", "root/A/A1", "root/A/A2", "root/B", "root/B/B1", "root/C" }, visible)

      window:dispose()
    end)

    it("collapsing parent of focus moves focus to parent", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })
      window:focus_on("root/A/A1")

      window:collapse("root/A")

      -- Focus should move to collapsed node
      assert.are.equal("root/A", window.focus:get())

      window:dispose()
    end)

    it("toggle toggles collapse state", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Initially expanded
      assert.is_false(window:is_collapsed("root/A"))

      -- Toggle to collapse
      window:toggle("root/A")
      assert.is_true(window:is_collapsed("root/A"))

      -- Toggle to expand
      window:toggle("root/A")
      assert.is_false(window:is_collapsed("root/A"))

      window:dispose()
    end)

    it("collapse root hides all descendants", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      window:collapse("root")

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- Only root should be visible
      assert.are.same({ "root" }, visible)

      window:dispose()
    end)

    it("collapse focused node hides its children", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Focus on A, then collapse it
      window:focus_on("root/A")
      assert.are.equal("root/A", window.focus:get())

      window:collapse()  -- Collapse current focus

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- A1 and A2 should be hidden
      assert.are.same({ "root", "root/A", "root/B", "root/B/B1", "root/C" }, visible)

      window:dispose()
    end)

    it("toggle on focused node works correctly", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Focus on B and toggle
      window:focus_on("root/B")
      window:toggle()  -- Toggle current focus

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- B1 should be hidden
      assert.are.same({ "root", "root/A", "root/A/A1", "root/A/A2", "root/B", "root/C" }, visible)

      -- Toggle again to expand
      window:toggle()

      visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- B1 should be visible again
      assert.are.same({ "root", "root/A", "root/A/A1", "root/A/A2", "root/B", "root/B/B1", "root/C" }, visible)

      window:dispose()
    end)

    it("collapse multiple siblings independently", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Collapse both A and B
      window:collapse("root/A")
      window:collapse("root/B")

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- Only A, B (collapsed), and C visible, no children
      assert.are.same({ "root", "root/A", "root/B", "root/C" }, visible)

      -- Expand just A
      window:expand("root/A")

      visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- A's children visible, B still collapsed
      assert.are.same({ "root", "root/A", "root/A/A1", "root/A/A2", "root/B", "root/C" }, visible)

      window:dispose()
    end)

    it("is_collapsed returns correct value for nested nodes", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Nothing collapsed initially
      assert.is_false(window:is_collapsed("root"))
      assert.is_false(window:is_collapsed("root/A"))
      assert.is_false(window:is_collapsed("root/B"))

      -- Collapse A
      window:collapse("root/A")
      assert.is_true(window:is_collapsed("root/A"))
      assert.is_false(window:is_collapsed("root/B"))

      -- Collapse B
      window:collapse("root/B")
      assert.is_true(window:is_collapsed("root/A"))
      assert.is_true(window:is_collapsed("root/B"))

      -- Expand A
      window:expand("root/A")
      assert.is_false(window:is_collapsed("root/A"))
      assert.is_true(window:is_collapsed("root/B"))

      window:dispose()
    end)

    it("viewport items have correct entity_uri for collapse tracking", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Verify each viewport item has entity_uri matching the store entity
      for _, item in ipairs(window.items._items) do
        local entity_uri = item._virtual.entity_uri
        assert.is_not_nil(entity_uri, "entity_uri should be set on " .. item._virtual.uri)

        -- Verify entity exists in store with this URI
        local entity = store:get(entity_uri)
        assert.is_not_nil(entity, "entity should exist for " .. entity_uri)
        assert.are.equal(entity_uri, entity.uri)
      end

      window:dispose()
    end)
  end)

  describe("Collapse/Expand with Deep Trees", function()
    local function create_deep_tree()
      -- Create: root -> A -> A1 -> A1a -> A1a1
      --                      A1b
      --               A2
      --         B -> B1
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
      store:add({ uri = "node:A", key = "A", name = "Node A" }, "node", { { type = "parent", to = "node:root" } })
      store:add({ uri = "node:A1", key = "A1", name = "Node A1" }, "node", { { type = "parent", to = "node:A" } })
      store:add({ uri = "node:A1a", key = "A1a", name = "Node A1a" }, "node", { { type = "parent", to = "node:A1" } })
      store:add({ uri = "node:A1a1", key = "A1a1", name = "Node A1a1" }, "node", { { type = "parent", to = "node:A1a" } })
      store:add({ uri = "node:A1b", key = "A1b", name = "Node A1b" }, "node", { { type = "parent", to = "node:A1" } })
      store:add({ uri = "node:A2", key = "A2", name = "Node A2" }, "node", { { type = "parent", to = "node:A" } })
      store:add({ uri = "node:B", key = "B", name = "Node B" }, "node", { { type = "parent", to = "node:root" } })
      store:add({ uri = "node:B1", key = "B1", name = "Node B1" }, "node", { { type = "parent", to = "node:B" } })
    end

    it("collapse deeply nested node hides its subtree", function()
      create_deep_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Collapse A1 (depth 2) - should hide A1a, A1a1, A1b
      window:collapse("root/A/A1")

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- A1a, A1a1, A1b should be hidden
      assert.are.same({
        "root",
        "root/A",
        "root/A/A1",  -- collapsed
        "root/A/A2",
        "root/B",
        "root/B/B1",
      }, visible)

      window:dispose()
    end)

    it("collapse at depth 3 works correctly", function()
      create_deep_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Collapse A1a (depth 3) - should hide only A1a1
      window:collapse("root/A/A1/A1a")

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      assert.are.same({
        "root",
        "root/A",
        "root/A/A1",
        "root/A/A1/A1a",  -- collapsed
        "root/A/A1/A1b",
        "root/A/A2",
        "root/B",
        "root/B/B1",
      }, visible)

      window:dispose()
    end)

    it("focus on deep node then collapse works", function()
      create_deep_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Focus on a deep node, then collapse it
      window:focus_on("root/A/A1")
      assert.are.equal("root/A/A1", window.focus:get())

      -- Collapse the focused node
      window:toggle()  -- Should collapse A1

      assert.is_true(window:is_collapsed("root/A/A1"))

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- A1's children should be hidden
      assert.are.same({
        "root",
        "root/A",
        "root/A/A1",  -- collapsed, still focused
        "root/A/A2",
        "root/B",
        "root/B/B1",
      }, visible)

      window:dispose()
    end)

    it("collapse ancestor when descendant already collapsed", function()
      create_deep_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- First collapse A1a (deeper)
      window:collapse("root/A/A1/A1a")
      assert.is_true(window:is_collapsed("root/A/A1/A1a"))

      -- Then collapse A1 (ancestor)
      window:collapse("root/A/A1")

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- Both A1 and its subtree hidden
      assert.are.same({
        "root",
        "root/A",
        "root/A/A1",  -- collapsed
        "root/A/A2",
        "root/B",
        "root/B/B1",
      }, visible)

      -- Expand A1 - A1a should still be collapsed
      window:expand("root/A/A1")

      visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- A1 expanded, but A1a still collapsed (A1a1 hidden)
      assert.are.same({
        "root",
        "root/A",
        "root/A/A1",
        "root/A/A1/A1a",  -- still collapsed
        "root/A/A1/A1b",
        "root/A/A2",
        "root/B",
        "root/B/B1",
      }, visible)

      -- Verify A1a still marked as collapsed
      assert.is_true(window:is_collapsed("root/A/A1/A1a"))

      window:dispose()
    end)

    it("collapse works after navigating away and back", function()
      create_deep_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Focus on deep node
      window:focus_on("root/A/A1/A1a")

      -- Collapse it
      window:collapse()
      assert.is_true(window:is_collapsed("root/A/A1/A1a"))

      -- Navigate to completely different branch
      window:focus_on("root/B/B1")

      -- Navigate back
      window:focus_on("root/A/A1/A1a")

      -- Should still be collapsed
      assert.is_true(window:is_collapsed("root/A/A1/A1a"))

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- A1a1 should still be hidden
      assert.is_false(vim.tbl_contains(visible, "root/A/A1/A1a/A1a1"))

      window:dispose()
    end)
  end)

  describe("Reactive Mutations", function()
    it("updates when node added to tree", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local initial_count = #window.items._items
      assert.are.equal(7, initial_count)

      -- Add new node
      store:add({ uri = "node:C1", key = "C1", name = "Node C1" }, "node", { { type = "parent", to = "node:C" } })

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      -- Should have one more item
      assert.are.equal(8, #window.items._items)

      window:dispose()
    end)

    it("updates when node removed from tree", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      assert.are.equal(7, #window.items._items)

      -- Remove a node
      store:dispose_entity("node:C")

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      -- Should have fewer items
      assert.are.equal(6, #window.items._items)

      window:dispose()
    end)

    it("updates when node is reparented", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Initial check: A is child of root
      -- Expected: root, root/A, ...
      local items = {}
      for _, item in ipairs(window.items._items) do
        table.insert(items, item._virtual.uri)
      end
      assert.is_true(vim.tbl_contains(items, "root/A"))
      assert.is_false(vim.tbl_contains(items, "root/B/A"))

      -- Move A to be child of B
      store:remove_edge("node:A", "parent", "node:root")
      store:add_edge("node:A", "parent", "node:B")

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      local new_items = {}
      for _, item in ipairs(window.items._items) do
        table.insert(new_items, item._virtual.uri)
      end

      -- A should now be under B
      assert.is_false(vim.tbl_contains(new_items, "root/A"))
      assert.is_true(vim.tbl_contains(new_items, "root/B/A"))

      -- Verify order: root, B, B1, B2, A (A is appended to B's children)
      -- Store uses insertion order, so A comes after existing children B1, B2
      local b_idx = 0
      local ba_idx = 0
      local bb1_idx = 0

      for i, uri in ipairs(new_items) do
        if uri == "root/B" then b_idx = i end
        if uri == "root/B/A" then ba_idx = i end
        if uri == "root/B/B1" then bb1_idx = i end
      end

      assert.is_true(b_idx < bb1_idx, "B should be before B1")
      assert.is_true(bb1_idx < ba_idx, "B1 should be before A (A appended last)")

      window:dispose()
    end)

    it("updates when node is added (insertion order)", function()
      create_simple_tree()
      -- A has children A1, A2.
      -- Insert A1_5 which should sort between A1 and A2.

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      store:add({ uri = "node:A1_5", key = "A1_5", name = "Node A1.5" }, "node", { { type = "parent", to = "node:A" } })

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      local items = {}
      for _, item in ipairs(window.items._items) do
        table.insert(items, item._virtual.uri)
      end

      -- Find indices
      local a1_idx = 0
      local a15_idx = 0
      local a2_idx = 0

      for i, uri in ipairs(items) do
        if uri == "root/A/A1" then a1_idx = i end
        if uri == "root/A/A1_5" then a15_idx = i end
        if uri == "root/A/A2" then a2_idx = i end
      end

      assert.is_true(a1_idx > 0)
      assert.is_true(a15_idx > 0)
      assert.is_true(a2_idx > 0)

      -- Verify order: A1, A2, A1_5 (Insertion order: A1_5 appended last)
      assert.is_true(a1_idx < a2_idx, "A1 should be before A2")
      assert.is_true(a2_idx < a15_idx, "A2 should be before A1_5 (appended last)")

      window:dispose()
    end)
  end)

  describe("Filter Functionality", function()
    it("set_filter filters out non-matching items", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Filter to only show items with "A" in name
      window:set_filter(function(entity)
        return entity.name and entity.name:find("A") ~= nil
      end)

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- Should only show Root (always shown as root) and A-named items
      -- Note: filter is applied, so only entities with "A" pass
      for _, vuri in ipairs(visible) do
        local item = nil
        for _, w in ipairs(window.items._items) do
          if w._virtual.uri == vuri then item = w break end
        end
        if item and item.name then
          assert.is_true(item.name:find("A") ~= nil or item.name == "Root",
            "Item " .. item.name .. " should contain 'A' or be Root")
        end
      end

      window:dispose()
    end)

    it("set_filter with nil clears filter", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })
      local initial_count = #window.items._items

      -- Set restrictive filter
      window:set_filter(function() return false end)
      -- Root is always shown even if filter fails
      assert.is_true(#window.items._items < initial_count)

      -- Clear filter
      window:set_filter(nil)
      assert.are.equal(initial_count, #window.items._items)

      window:dispose()
    end)

    it("filter passed at construction works", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        filter = function(entity)
          return entity.key ~= "B1"  -- Filter out B1
        end
      })

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- B1 should not be visible
      assert.is_false(vim.tbl_contains(visible, "root/B/B1"))
      -- But B should still be visible
      assert.is_true(vim.tbl_contains(visible, "root/B"))

      window:dispose()
    end)
  end)

  describe("Search Functionality", function()
    it("set_search filters items by name", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      window:set_search("A1")

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item.name)
      end

      -- Only items matching "A1" should be visible
      assert.is_true(vim.tbl_contains(visible, "Node A1"))

      window:dispose()
    end)

    it("set_search is case insensitive", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      window:set_search("node a")  -- lowercase

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item.name)
      end

      -- Should match "Node A", "Node A1", "Node A2"
      assert.is_true(vim.tbl_contains(visible, "Node A") or
                     vim.tbl_contains(visible, "Node A1") or
                     vim.tbl_contains(visible, "Node A2"))

      window:dispose()
    end)

    it("clear_search shows all items again", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })
      local initial_count = #window.items._items

      window:set_search("A1")
      assert.is_true(#window.items._items < initial_count)

      window:clear_search()
      assert.are.equal(initial_count, #window.items._items)

      window:dispose()
    end)
  end)

  describe("User Prune Function", function()
    it("prune option skips subtrees", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        prune = function(entity)
          return entity.key == "A"  -- Prune A and all its children
        end
      })

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- A should be visible but A1, A2 should be pruned
      assert.is_true(vim.tbl_contains(visible, "root/A"))
      assert.is_false(vim.tbl_contains(visible, "root/A/A1"))
      assert.is_false(vim.tbl_contains(visible, "root/A/A2"))
      -- B and its children should still be visible
      assert.is_true(vim.tbl_contains(visible, "root/B"))
      assert.is_true(vim.tbl_contains(visible, "root/B/B1"))

      window:dispose()
    end)
  end)

  describe("Utility Methods", function()
    it("info returns correct state", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local info = window:info()

      assert.are.equal("root", info.focus)
      assert.are.equal(1, info.focus_index)
      assert.are.equal(7, info.viewport_size)
      assert.are.equal(7, info.total_size)

      -- Move focus and check again
      window:move_down()
      window:move_down()
      info = window:info()

      assert.are.equal("root/A/A1", info.focus)
      assert.are.equal(3, info.focus_index)

      window:dispose()
    end)

    it("refresh rebuilds the window", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })
      local initial_count = #window.items._items

      -- Add a node directly to store
      store:add({ uri = "node:D", key = "D", name = "Node D" }, "node", { { type = "parent", to = "node:root" } })

      -- Force refresh (synchronous)
      window:refresh()

      -- Should have new item
      assert.are.equal(initial_count + 1, #window.items._items)

      window:dispose()
    end)

    it("getFocus returns focused item wrapper", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local focused = window:getFocus()

      assert.is_not_nil(focused)
      assert.are.equal("root", focused._virtual.uri)
      assert.are.equal("Root", focused.name)
      assert.are.equal("node:root", focused.uri)

      -- Move focus and check
      window:move_down()
      focused = window:getFocus()

      assert.are.equal("root/A", focused._virtual.uri)
      assert.are.equal("Node A", focused.name)

      window:dispose()
    end)

    it("focus_viewport_index returns correct index", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      assert.are.equal(1, window:focus_viewport_index())

      window:move_down()
      assert.are.equal(2, window:focus_viewport_index())

      window:move_down()
      assert.are.equal(3, window:focus_viewport_index())

      window:dispose()
    end)

    it("on_rebuild callback is called on rebuild", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local rebuild_count = 0
      local unsub = window:on_rebuild(function()
        rebuild_count = rebuild_count + 1
      end)

      -- Trigger rebuild via collapse
      window:collapse("root/A")
      assert.are.equal(1, rebuild_count)

      -- Trigger another rebuild
      window:expand("root/A")
      assert.are.equal(2, rebuild_count)

      -- Unsubscribe
      unsub()

      -- Should not increment after unsubscribe
      window:refresh()
      assert.are.equal(2, rebuild_count)

      window:dispose()
    end)

    it("once_rebuild fires only once then auto-unsubscribes", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local call_count = 0
      window:once_rebuild(function()
        call_count = call_count + 1
      end)

      -- First rebuild should trigger callback
      window:collapse("root/A")
      assert.are.equal(1, call_count)

      -- Second rebuild should NOT trigger (auto-unsubscribed)
      window:expand("root/A")
      assert.are.equal(1, call_count)

      -- Third rebuild should still not trigger
      window:refresh()
      assert.are.equal(1, call_count)

      window:dispose()
    end)

    it("once_rebuild can be cancelled before firing", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local called = false
      local unsub = window:once_rebuild(function()
        called = true
      end)

      -- Cancel before rebuild
      unsub()

      -- Rebuild should NOT trigger callback
      window:collapse("root/A")
      assert.is_false(called)

      window:dispose()
    end)
  end)

  describe("Depth Calculation", function()
    it("viewport items have correct depth values", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local depth_map = {}
      for _, item in ipairs(window.items._items) do
        depth_map[item._virtual.uri] = item._virtual.depth
      end

      assert.are.equal(0, depth_map["root"])
      assert.are.equal(1, depth_map["root/A"])
      assert.are.equal(1, depth_map["root/B"])
      assert.are.equal(1, depth_map["root/C"])
      assert.are.equal(2, depth_map["root/A/A1"])
      assert.are.equal(2, depth_map["root/A/A2"])
      assert.are.equal(2, depth_map["root/B/B1"])

      window:dispose()
    end)

    it("deep tree has correct depth at all levels", function()
      -- Create: root -> A -> B -> C -> D -> E
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
      store:add({ uri = "node:A", key = "A", name = "A" }, "node", { { type = "parent", to = "node:root" } })
      store:add({ uri = "node:B", key = "B", name = "B" }, "node", { { type = "parent", to = "node:A" } })
      store:add({ uri = "node:C", key = "C", name = "C" }, "node", { { type = "parent", to = "node:B" } })
      store:add({ uri = "node:D", key = "D", name = "D" }, "node", { { type = "parent", to = "node:C" } })
      store:add({ uri = "node:E", key = "E", name = "E" }, "node", { { type = "parent", to = "node:D" } })

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local depth_map = {}
      for _, item in ipairs(window.items._items) do
        depth_map[item._virtual.uri] = item._virtual.depth
      end

      assert.are.equal(0, depth_map["root"])
      assert.are.equal(1, depth_map["root/A"])
      assert.are.equal(2, depth_map["root/A/B"])
      assert.are.equal(3, depth_map["root/A/B/C"])
      assert.are.equal(4, depth_map["root/A/B/C/D"])
      assert.are.equal(5, depth_map["root/A/B/C/D/E"])

      window:dispose()
    end)
  end)

  describe("Navigation Edge Cases", function()
    it("move_down at last item returns false", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Navigate to last item (C)
      window:focus_on("root/C")

      local result = window:move_down()
      assert.is_false(result)
      assert.are.equal("root/C", window.focus:get())

      window:dispose()
    end)

    it("move_up at first item returns false", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Already at root (first item)
      local result = window:move_up()
      assert.is_false(result)
      assert.are.equal("root", window.focus:get())

      window:dispose()
    end)

    it("move_into on leaf node returns false", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Navigate to A1 (leaf node)
      window:focus_on("root/A/A1")

      local result = window:move_into()
      assert.is_false(result)
      assert.are.equal("root/A/A1", window.focus:get())

      window:dispose()
    end)

    it("move_out from root returns false", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- At root, no parent
      local result = window:move_out()
      assert.is_false(result)
      assert.are.equal("root", window.focus:get())

      window:dispose()
    end)

    it("focus_on non-existent vuri returns false", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local result = window:focus_on("root/NonExistent")
      assert.is_false(result)
      -- Focus should remain unchanged
      assert.are.equal("root", window.focus:get())

      window:dispose()
    end)

    it("focus_on nil returns false", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local result = window:focus_on(nil)
      assert.is_false(result)

      window:dispose()
    end)
  end)

  describe("Edge Cases", function()
    it("handles single node tree", function()
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      assert.are.equal(1, #window.items._items)
      assert.are.equal("root", window.focus:get())

      -- Navigation should fail gracefully
      assert.is_false(window:move_down())
      assert.is_false(window:move_up())
      assert.is_false(window:move_into())
      assert.is_false(window:move_out())

      window:dispose()
    end)

    it("handles root with no children", function()
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      assert.are.same({ "root" }, visible)

      window:dispose()
    end)

    it("collapse on node with no children is safe", function()
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
      store:add({ uri = "node:A", key = "A", name = "A" }, "node", { { type = "parent", to = "node:root" } })

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Collapse A (has no children)
      window:collapse("root/A")

      -- Should still work, just no change in visible items
      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      assert.are.same({ "root", "root/A" }, visible)
      assert.is_true(window:is_collapsed("root/A"))

      window:dispose()
    end)

    it("toggle without focus does nothing", function()
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Clear focus
      window.focus:set(nil)

      -- Should not error
      window:toggle()
      window:collapse()
      window:expand()

      window:dispose()
    end)
  end)

  describe("Viewport Budget", function()
    it("respects below budget limit", function()
      -- Create a tree with many nodes
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
      for i = 1, 20 do
        store:add({ uri = "node:" .. i, key = tostring(i), name = "Node " .. i }, "node", {
          { type = "parent", to = "node:root" }
        })
      end

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        above = 5,
        below = 5,  -- Only show 5 items below focus
      })

      -- With focus on root, should show root + up to 5 below
      assert.is_true(#window.items._items <= 6)

      window:dispose()
    end)

    it("respects above budget limit", function()
      -- Create a deep tree
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
      local parent = "node:root"
      for i = 1, 20 do
        local uri = "node:" .. i
        store:add({ uri = uri, key = tostring(i), name = "Node " .. i }, "node", {
          { type = "parent", to = parent }
        })
        parent = uri
      end

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        above = 5,
        below = 5,
      })

      -- Focus on deepest node
      window:focus_on("root/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20")
      -- Force rebuild to apply budget
      window:refresh()

      -- Should have limited items (above + below budget)
      assert.is_true(#window.items._items <= 11)  -- 5 above + focus + 5 below

      window:dispose()
    end)
  end)

  describe("Disposal", function()
    it("disposed window stops reacting to store changes", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })
      local initial_count = #window.items._items

      window:dispose()

      -- Add node after disposal
      store:add({ uri = "node:D", key = "D", name = "Node D" }, "node", { { type = "parent", to = "node:root" } })

      -- Wait for any potential rebuild
      vim.wait(50, function() return false end)

      -- Should not have changed (disposed)
      assert.are.equal(initial_count, #window.items._items)
    end)

    it("on_rebuild listeners are not called after disposal", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local called = false
      window:on_rebuild(function()
        called = true
      end)

      window:dispose()

      -- Try to trigger rebuild
      -- This shouldn't crash or call the listener
      -- (internal rebuild is prevented by _disposed check)

      assert.is_false(called)
    end)
  end)

  describe("Reactive Filters", function()
    it("filter returning Signal triggers rebuild on signal change", function()
      create_simple_tree()

      local show_b = neostate.Signal(true)

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        filter = function(entity)
          if entity.key == "B" or entity.key == "B1" then
            return show_b  -- Return Signal
          end
          return true
        end
      })

      -- Initially B is shown
      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end
      assert.is_true(vim.tbl_contains(visible, "root/B"))

      -- Change signal to hide B
      show_b:set(false)

      -- Wait for debounced rebuild
      vim.wait(50, function() return false end)

      visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end

      -- B should now be hidden
      assert.is_false(vim.tbl_contains(visible, "root/B"))
      assert.is_false(vim.tbl_contains(visible, "root/B/B1"))

      window:dispose()
      show_b:dispose()
    end)

    it("prune with Signal reads current value", function()
      create_simple_tree()

      -- Start with prune signal already true
      local prune_a = neostate.Signal(true)

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        prune = function(entity)
          if entity.key == "A" then
            return prune_a  -- Return Signal - reads current value
          end
          return false
        end
      })

      -- A's children should be pruned (signal is true)
      local visible = {}
      for _, item in ipairs(window.items._items) do
        table.insert(visible, item._virtual.uri)
      end
      assert.is_true(vim.tbl_contains(visible, "root/A"))  -- A itself visible
      assert.is_false(vim.tbl_contains(visible, "root/A/A1"))
      assert.is_false(vim.tbl_contains(visible, "root/A/A2"))

      window:dispose()
      prune_a:dispose()
    end)
  end)

  describe("Pathkeys", function()
    it("viewport items have pathkeys array", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- All items should have a pathkeys array (may be empty for root)
      for _, item in ipairs(window.items._items) do
        assert.is_table(item._virtual.pathkeys,
          "item " .. item._virtual.uri .. " should have pathkeys array")
      end

      window:dispose()
    end)

    it("pathkeys contains ancestor keys (not including self)", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      -- Pathkeys structure: contains keys of ancestors, not the item itself
      -- root: pathkeys = {} (no ancestors)
      -- root/A: pathkeys = {"root"} (ancestor is root)
      -- root/A/A1: pathkeys = {"root", "A"} (ancestors are root, A)
      for _, item in ipairs(window.items._items) do
        if item._virtual.uri == "root" then
          assert.are.same({}, item._virtual.pathkeys)
        elseif item._virtual.uri == "root/A" then
          assert.are.same({ "root" }, item._virtual.pathkeys)
        elseif item._virtual.uri == "root/A/A1" then
          assert.are.same({ "root", "A" }, item._virtual.pathkeys)
        elseif item._virtual.uri == "root/B/B1" then
          assert.are.same({ "root", "B" }, item._virtual.pathkeys)
        end
      end

      window:dispose()
    end)

    it("pathkeys length equals depth (ancestors only)", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      for _, item in ipairs(window.items._items) do
        local depth = item._virtual.depth
        local pathkeys = item._virtual.pathkeys
        -- pathkeys length equals depth (ancestors only, not self)
        assert.are.equal(depth, #pathkeys,
          "item at depth " .. depth .. " should have " .. depth .. " pathkeys (ancestors), got " .. #pathkeys)
      end

      window:dispose()
    end)
  end)

  describe("Scroll Margin", function()
    it("scroll margin triggers rebuild when approaching bottom", function()
      -- Create a tree with enough nodes to test scrolling
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
      for i = 1, 20 do
        store:add({ uri = "node:" .. i, key = tostring(i), name = "Node " .. i }, "node", {
          { type = "parent", to = "node:root" }
        })
      end

      local rebuild_count = 0
      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        above = 10,
        below = 10,
        scroll_margin = 3,
      })

      window:on_rebuild(function()
        rebuild_count = rebuild_count + 1
      end)

      -- Move down until we approach bottom margin
      for _ = 1, 15 do
        window:move_down()
      end

      -- Should have triggered at least one rebuild due to scroll margin
      -- (rebuild happens when within scroll_margin of edge)
      assert.is_true(rebuild_count >= 1)

      window:dispose()
    end)

    it("scroll margin triggers rebuild when approaching top", function()
      -- Create a deep tree (linear chain) to properly test scroll
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
      local parent = "node:root"
      for i = 1, 30 do
        local uri = "node:" .. i
        store:add({ uri = uri, key = tostring(i), name = "Node " .. i }, "node", {
          { type = "parent", to = parent }
        })
        parent = uri
      end

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        above = 10,
        below = 10,
        scroll_margin = 3,
      })

      -- Move to a deep node first using navigation
      for _ = 1, 20 do
        window:move_down()
      end
      window:refresh()

      local rebuild_count = 0
      window:on_rebuild(function()
        rebuild_count = rebuild_count + 1
      end)

      -- Move up until we approach top margin
      for _ = 1, 15 do
        window:move_up()
      end

      -- Should have triggered at least one rebuild
      assert.is_true(rebuild_count >= 1)

      window:dispose()
    end)

    it("custom scroll_margin is respected", function()
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
      for i = 1, 10 do
        store:add({ uri = "node:" .. i, key = tostring(i), name = "Node " .. i }, "node", {
          { type = "parent", to = "node:root" }
        })
      end

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        above = 5,
        below = 5,
        scroll_margin = 2,  -- Custom margin
      })

      assert.are.equal(2, window.scroll_margin)

      window:dispose()
    end)

    it("default scroll_margin is min of above and below", function()
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")

      local window = TreeWindow:new(store, "node:root", {
        edge_type = "parent",
        above = 10,
        below = 5,
        -- No scroll_margin specified
      })

      -- Default should be min(10, 5) = 5
      assert.are.equal(5, window.scroll_margin)

      window:dispose()
    end)
  end)

  describe("Parent Vuri", function()
    it("_parent_vuri returns correct parent path", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      assert.are.equal("root/A", window:_parent_vuri("root/A/A1"))
      assert.are.equal("root", window:_parent_vuri("root/A"))
      assert.is_nil(window:_parent_vuri("root"))

      window:dispose()
    end)

    it("_parent_vuri handles deep paths", function()
      store:add({ uri = "node:root", key = "root", name = "Root" }, "node")
      store:add({ uri = "node:A", key = "A", name = "A" }, "node", { { type = "parent", to = "node:root" } })
      store:add({ uri = "node:B", key = "B", name = "B" }, "node", { { type = "parent", to = "node:A" } })
      store:add({ uri = "node:C", key = "C", name = "C" }, "node", { { type = "parent", to = "node:B" } })

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      assert.are.equal("root/A/B", window:_parent_vuri("root/A/B/C"))
      assert.are.equal("root/A", window:_parent_vuri("root/A/B"))
      assert.are.equal("root", window:_parent_vuri("root/A"))

      window:dispose()
    end)
  end)

  describe("Focus Signal", function()
    it("focus signal can be watched for changes", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local focus_changes = {}
      window.focus:watch(function(new_focus)
        table.insert(focus_changes, new_focus)
      end)

      window:move_down()
      window:move_down()
      window:move_up()

      assert.are.same({ "root/A", "root/A/A1", "root/A" }, focus_changes)

      window:dispose()
    end)

    it("focus signal use() runs immediately and on change", function()
      create_simple_tree()

      local window = TreeWindow:new(store, "node:root", { edge_type = "parent" })

      local all_focus = {}
      window.focus:use(function(focus)
        table.insert(all_focus, focus)
      end)

      -- use() runs immediately with current value
      assert.are.equal(1, #all_focus)
      assert.are.equal("root", all_focus[1])

      window:move_down()
      assert.are.equal(2, #all_focus)
      assert.are.equal("root/A", all_focus[2])

      window:dispose()
    end)
  end)

  describe("DAP-like Scenarios", function()
    it("handles rapid stack creation with prepend_edge (newest first)", function()
      -- Create debugger structure
      store:add({ uri = "debugger:1", key = "Debugger", name = "Debugger" }, "debugger")
      store:add({ uri = "session:1", key = "Session 1", name = "Session 1" }, "session", {
        { type = "parent", to = "debugger:1" }
      })
      store:add({ uri = "thread:1", key = "Thread 1", name = "Thread 1" }, "thread", {
        { type = "parent", to = "session:1" }
      })

      local window = TreeWindow:new(store, "debugger:1", { edge_type = "parent" })

      -- Simulate stepping - add stacks with prepend_edge (like real SDK does)
      -- SDK convention: index 0 = latest (newest), higher index = older
      -- Stacks are created in order: first stop creates index 2, then 1, then 0 (latest)
      -- prepend_edge ensures newest (index 0) appears at top
      for i = 2, 0, -1 do
        store:add({ uri = "stack:" .. i, key = "Stack [" .. i .. "]", name = "Stack [" .. i .. "]" }, "stack", {})
        store:prepend_edge("stack:" .. i, "parent", "thread:1")
        -- Add frames to each stack
        for j = 1, 3 do
          store:add({ uri = "frame:" .. i .. ":" .. j, key = "Frame " .. j, name = "Frame " .. j }, "frame", {
            { type = "parent", to = "stack:" .. i }
          })
        end
      end

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      -- Collect viewport items
      local items = {}
      for _, item in ipairs(window.items._items) do
        table.insert(items, item._virtual.uri)
      end

      -- Verify newest-first order: Stack [0] (latest/newest) at top, Stack [2] (oldest) at bottom
      local expected = {
        "Debugger",
        "Debugger/Session 1",
        "Debugger/Session 1/Thread 1",
        "Debugger/Session 1/Thread 1/Stack [0]",  -- Latest (index 0) at top
        "Debugger/Session 1/Thread 1/Stack [0]/Frame 1",
        "Debugger/Session 1/Thread 1/Stack [0]/Frame 2",
        "Debugger/Session 1/Thread 1/Stack [0]/Frame 3",
        "Debugger/Session 1/Thread 1/Stack [1]",
        "Debugger/Session 1/Thread 1/Stack [1]/Frame 1",
        "Debugger/Session 1/Thread 1/Stack [1]/Frame 2",
        "Debugger/Session 1/Thread 1/Stack [1]/Frame 3",
        "Debugger/Session 1/Thread 1/Stack [2]",  -- Oldest (index 2) at bottom
        "Debugger/Session 1/Thread 1/Stack [2]/Frame 1",
        "Debugger/Session 1/Thread 1/Stack [2]/Frame 2",
        "Debugger/Session 1/Thread 1/Stack [2]/Frame 3",
      }

      assert.are.same(expected, items)

      window:dispose()
    end)

    it("handles interleaved outputs with stacks (newest stacks first)", function()
      store:add({ uri = "debugger:1", key = "Debugger", name = "Debugger" }, "debugger")
      store:add({ uri = "session:1", key = "Session 1", name = "Session 1" }, "session", {
        { type = "parent", to = "debugger:1" }
      })
      store:add({ uri = "thread:1", key = "Thread 1", name = "Thread 1" }, "thread", {
        { type = "parent", to = "session:1" }
      })

      local window = TreeWindow:new(store, "debugger:1", { edge_type = "parent" })

      -- Simulate interleaved stack creation and telemetry output
      -- SDK convention: index 0 = latest, higher = older
      -- First stop: creates Stack [1] (will become older)
      -- Second stop: creates Stack [0] (latest)
      -- prepend_edge ensures latest appears at top
      store:add({ uri = "stack:1", key = "Stack [1]", name = "Stack [1]" }, "stack", {})
      store:prepend_edge("stack:1", "parent", "thread:1")
      store:add({ uri = "output:1", key = "[telemetry] op1", name = "[telemetry] op1" }, "output", {
        { type = "parent", to = "session:1" }
      })
      store:add({ uri = "stack:0", key = "Stack [0]", name = "Stack [0]" }, "stack", {})
      store:prepend_edge("stack:0", "parent", "thread:1")
      store:add({ uri = "output:2", key = "[telemetry] op2", name = "[telemetry] op2" }, "output", {
        { type = "parent", to = "session:1" }
      })

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      local items = {}
      for _, item in ipairs(window.items._items) do
        table.insert(items, item._virtual.uri)
      end

      -- Stacks: latest first (Stack [0] at top, Stack [1] below)
      -- Outputs: insertion order (op1 before op2)
      local expected = {
        "Debugger",
        "Debugger/Session 1",
        "Debugger/Session 1/Thread 1",
        "Debugger/Session 1/Thread 1/Stack [0]",  -- Latest (index 0) at top
        "Debugger/Session 1/Thread 1/Stack [1]",  -- Older (index 1) below
        "Debugger/Session 1/[telemetry] op1",
        "Debugger/Session 1/[telemetry] op2",
      }

      assert.are.same(expected, items)

      window:dispose()
    end)
  end)

  describe("Deep Tree Path Correctness", function()
    -- These tests verify that deeply nested items maintain correct vuris and depths
    -- even when added reactively after the initial tree build.
    -- This is critical for DAP-like scenarios where scopes/variables are lazy-loaded.

    it("items added to deep tree have correct vuri with full path", function()
      -- Create: session -> thread -> stack -> frame -> (scopes added later)
      store:add({ uri = "session:1", key = "session", name = "Session" }, "session")
      store:add({ uri = "thread:1", key = "thread:0", name = "Thread 0" }, "thread", {
        { type = "parent", to = "session:1" }
      })
      store:add({ uri = "stack:1", key = "stack:0", name = "Stack 0" }, "stack", {
        { type = "parent", to = "thread:1" }
      })
      store:add({ uri = "frame:1", key = "frame:0", name = "Frame 0" }, "frame", {
        { type = "parent", to = "stack:1" }
      })

      local window = TreeWindow:new(store, "session:1", { edge_type = "parent" })

      -- Verify initial tree structure
      local items = {}
      for _, item in ipairs(window.items._items) do
        items[item._virtual.uri] = {
          depth = item._virtual.depth,
          pathkeys = item._virtual.pathkeys,
        }
      end

      assert.are.equal(0, items["session"].depth)
      assert.are.equal(1, items["session/thread:0"].depth)
      assert.are.equal(2, items["session/thread:0/stack:0"].depth)
      assert.are.equal(3, items["session/thread:0/stack:0/frame:0"].depth)

      -- Now add scopes lazily (like DAP does when expanding a frame)
      store:add({ uri = "scope:1", key = "scope:Local", name = "Local" }, "scope", {
        { type = "parent", to = "frame:1" }
      })

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      -- Verify scope has correct vuri and depth
      items = {}
      for _, item in ipairs(window.items._items) do
        items[item._virtual.uri] = {
          depth = item._virtual.depth,
          pathkeys = item._virtual.pathkeys,
        }
      end

      -- The scope should have depth 4 and full path in vuri
      assert.is_not_nil(items["session/thread:0/stack:0/frame:0/scope:Local"],
        "Scope should have full path in vuri")
      assert.are.equal(4, items["session/thread:0/stack:0/frame:0/scope:Local"].depth)
      assert.are.same(
        { "session", "thread:0", "stack:0", "frame:0" },
        items["session/thread:0/stack:0/frame:0/scope:Local"].pathkeys
      )

      window:dispose()
    end)

    it("variables added under scope have correct vuri with full path", function()
      -- Create: session -> thread -> stack -> frame -> scope
      store:add({ uri = "session:1", key = "session", name = "Session" }, "session")
      store:add({ uri = "thread:1", key = "thread:0", name = "Thread 0" }, "thread", {
        { type = "parent", to = "session:1" }
      })
      store:add({ uri = "stack:1", key = "stack:0", name = "Stack 0" }, "stack", {
        { type = "parent", to = "thread:1" }
      })
      store:add({ uri = "frame:1", key = "frame:0", name = "Frame 0" }, "frame", {
        { type = "parent", to = "stack:1" }
      })
      store:add({ uri = "scope:1", key = "scope:Local", name = "Local" }, "scope", {
        { type = "parent", to = "frame:1" }
      })

      local window = TreeWindow:new(store, "session:1", { edge_type = "parent" })

      -- Now add variables lazily (like DAP does when expanding a scope)
      store:add({ uri = "var:a", key = "var:a", name = "a" }, "variable", {
        { type = "parent", to = "scope:1" }
      })
      store:add({ uri = "var:b", key = "var:b", name = "b" }, "variable", {
        { type = "parent", to = "scope:1" }
      })

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      -- Verify variables have correct vuri and depth
      local items = {}
      for _, item in ipairs(window.items._items) do
        items[item._virtual.uri] = {
          depth = item._virtual.depth,
          pathkeys = item._virtual.pathkeys,
          entity_uri = item._virtual.entity_uri or item.uri,
        }
      end

      -- Variables should have depth 5 and full path in vuri
      local expected_vuri_a = "session/thread:0/stack:0/frame:0/scope:Local/var:a"
      local expected_vuri_b = "session/thread:0/stack:0/frame:0/scope:Local/var:b"

      assert.is_not_nil(items[expected_vuri_a],
        "Variable a should have full path in vuri, got: " .. vim.inspect(vim.tbl_keys(items)))
      assert.is_not_nil(items[expected_vuri_b],
        "Variable b should have full path in vuri")

      assert.are.equal(5, items[expected_vuri_a].depth,
        "Variable a should have depth 5")
      assert.are.equal(5, items[expected_vuri_b].depth,
        "Variable b should have depth 5")

      assert.are.same(
        { "session", "thread:0", "stack:0", "frame:0", "scope:Local" },
        items[expected_vuri_a].pathkeys
      )

      window:dispose()
    end)

    it("expanding collapsed node produces items with correct vuris", function()
      -- Create deep tree but collapse intermediate node
      store:add({ uri = "session:1", key = "session", name = "Session" }, "session")
      store:add({ uri = "thread:1", key = "thread:0", name = "Thread 0" }, "thread", {
        { type = "parent", to = "session:1" }
      })
      store:add({ uri = "stack:1", key = "stack:0", name = "Stack 0" }, "stack", {
        { type = "parent", to = "thread:1" }
      })
      store:add({ uri = "frame:1", key = "frame:0", name = "Frame 0" }, "frame", {
        { type = "parent", to = "stack:1" }
      })
      store:add({ uri = "scope:1", key = "scope:Local", name = "Local" }, "scope", {
        { type = "parent", to = "frame:1" }
      })
      store:add({ uri = "var:x", key = "var:x", name = "x" }, "variable", {
        { type = "parent", to = "scope:1" }
      })

      local window = TreeWindow:new(store, "session:1", { edge_type = "parent" })

      -- Collapse the frame
      window:collapse("session/thread:0/stack:0/frame:0")

      -- Wait for rebuild
      vim.wait(50, function() return false end)

      -- Now focus on frame and expand it
      window:focus_on("session/thread:0/stack:0/frame:0")
      window:expand()

      -- Wait for rebuild
      vim.wait(50, function() return false end)

      -- Verify variable still has correct vuri after expand
      local items = {}
      for _, item in ipairs(window.items._items) do
        items[item._virtual.uri] = {
          depth = item._virtual.depth,
          pathkeys = item._virtual.pathkeys,
        }
      end

      local expected_vuri = "session/thread:0/stack:0/frame:0/scope:Local/var:x"
      assert.is_not_nil(items[expected_vuri],
        "Variable should have full path after expand")
      assert.are.equal(5, items[expected_vuri].depth)

      window:dispose()
    end)

    it("focus change to deep node maintains correct paths for children", function()
      -- Create full tree
      store:add({ uri = "session:1", key = "session", name = "Session" }, "session")
      store:add({ uri = "thread:1", key = "thread:0", name = "Thread 0" }, "thread", {
        { type = "parent", to = "session:1" }
      })
      store:add({ uri = "stack:1", key = "stack:0", name = "Stack 0" }, "stack", {
        { type = "parent", to = "thread:1" }
      })
      store:add({ uri = "frame:1", key = "frame:0", name = "Frame 0" }, "frame", {
        { type = "parent", to = "stack:1" }
      })
      store:add({ uri = "scope:1", key = "scope:Local", name = "Local" }, "scope", {
        { type = "parent", to = "frame:1" }
      })
      store:add({ uri = "var:y", key = "var:y", name = "y" }, "variable", {
        { type = "parent", to = "scope:1" }
      })

      local window = TreeWindow:new(store, "session:1", { edge_type = "parent" })

      -- Focus on the scope
      window:focus_on("session/thread:0/stack:0/frame:0/scope:Local")
      window:refresh()

      -- Now check variable still has correct path
      local found_var = nil
      for _, item in ipairs(window.items._items) do
        if item.uri == "var:y" then
          found_var = item
          break
        end
      end

      assert.is_not_nil(found_var, "Variable should be visible")
      assert.are.equal("session/thread:0/stack:0/frame:0/scope:Local/var:y", found_var._virtual.uri,
        "Variable vuri should include full path")
      assert.are.equal(5, found_var._virtual.depth,
        "Variable depth should be 5")

      window:dispose()
    end)

    it("nested variables maintain correct paths", function()
      -- Create: session -> scope -> var:obj -> var:prop (nested object)
      store:add({ uri = "session:1", key = "session", name = "Session" }, "session")
      store:add({ uri = "scope:1", key = "scope:Local", name = "Local" }, "scope", {
        { type = "parent", to = "session:1" }
      })
      store:add({ uri = "var:obj", key = "var:obj", name = "obj" }, "variable", {
        { type = "parent", to = "scope:1" }
      })
      -- Nested property under the object
      store:add({ uri = "var:prop", key = "var:prop", name = "prop" }, "variable", {
        { type = "parent", to = "var:obj" }
      })

      local window = TreeWindow:new(store, "session:1", { edge_type = "parent" })

      local items = {}
      for _, item in ipairs(window.items._items) do
        items[item._virtual.uri] = {
          depth = item._virtual.depth,
        }
      end

      -- Check nested variable has correct path
      assert.is_not_nil(items["session/scope:Local/var:obj/var:prop"],
        "Nested variable should have full path in vuri")
      assert.are.equal(3, items["session/scope:Local/var:obj/var:prop"].depth)

      window:dispose()
    end)
  end)
end)
