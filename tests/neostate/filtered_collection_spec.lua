local neostate = require("neostate")

describe("Filtered Collections", function()
    describe("Index-based filtering", function()
        it("should create filtered collection by index", function()
            local c = neostate.Collection("Users")
            c:add_index("by_role", function(item) return item.role end)

            local admin1 = c:add(neostate.Disposable({ id = 1, role = "admin" }))
            local user1 = c:add(neostate.Disposable({ id = 2, role = "user" }))
            local admin2 = c:add(neostate.Disposable({ id = 3, role = "admin" }))

            local admins = c:where("by_role", "admin")

            -- Check filtered collection contains only admins
            assert.are.equal(2, #admins._items)

            local has_admin1 = false
            local has_admin2 = false
            for item in admins.iter() do
                if item == admin1 then has_admin1 = true end
                if item == admin2 then has_admin2 = true end
            end
            assert.is_true(has_admin1)
            assert.is_true(has_admin2)
        end)

        it("should sync parent additions to filtered child", function()
            local c = neostate.Collection("Users")
            c:add_index("by_role", function(item) return item.role end)

            local admins = c:where("by_role", "admin")
            assert.are.equal(0, #admins._items)

            -- Add admin to parent
            local admin1 = c:add(neostate.Disposable({ id = 1, role = "admin" }))

            -- Should appear in filtered collection
            assert.are.equal(1, #admins._items)
            assert.are.equal(admin1, admins._items[1])

            -- Add user to parent
            c:add(neostate.Disposable({ id = 2, role = "user" }))

            -- Should NOT appear in filtered collection
            assert.are.equal(1, #admins._items)
        end)

        it("should sync parent removals to filtered child", function()
            local c = neostate.Collection("Users")
            c:add_index("by_role", function(item) return item.role end)

            local admin1 = c:add(neostate.Disposable({ id = 1, role = "admin" }))
            local user1 = c:add(neostate.Disposable({ id = 2, role = "user" }))

            local admins = c:where("by_role", "admin")
            assert.are.equal(1, #admins._items)

            -- Remove admin from parent
            c:delete(function(i) return i == admin1 end)

            -- Should be removed from filtered collection
            assert.are.equal(0, #admins._items)
        end)

        it("should forward child additions to parent", function()
            local c = neostate.Collection("Users")
            c:add_index("by_role", function(item) return item.role end)

            local admins = c:where("by_role", "admin")

            -- Add admin to filtered collection
            local admin1 = admins:add(neostate.Disposable({ id = 1, role = "admin" }))

            -- Should appear in both collections
            assert.are.equal(1, #admins._items)
            assert.are.equal(1, #c._items)
            assert.are.equal(admin1, c._items[1])
        end)

        it("should error when adding non-matching item to filtered child", function()
            local c = neostate.Collection("Users")
            c:add_index("by_role", function(item) return item.role end)

            local admins = c:where("by_role", "admin")

            -- Try to add user to admins collection
            local success = pcall(function()
                admins:add(neostate.Disposable({ id = 1, role = "user" }))
            end)

            assert.is_false(success)
            assert.are.equal(0, #admins._items)
            assert.are.equal(0, #c._items)
        end)
    end)

    describe("Predicate-based filtering", function()
        it("should create filtered collection by predicate", function()
            local c = neostate.Collection("Items")

            local item1 = c:add(neostate.Disposable({ value = 10, valid = true }))
            local item2 = c:add(neostate.Disposable({ value = 20, valid = false }))
            local item3 = c:add(neostate.Disposable({ value = 30, valid = true }))

            local valid_items = c:where(function(item) return item.valid end)

            -- Check filtered collection contains only valid items
            assert.are.equal(2, #valid_items._items)

            local has_item1 = false
            local has_item3 = false
            for item in valid_items.iter() do
                if item == item1 then has_item1 = true end
                if item == item3 then has_item3 = true end
            end
            assert.is_true(has_item1)
            assert.is_true(has_item3)
        end)

        it("should sync parent additions to predicate-filtered child", function()
            local c = neostate.Collection("Items")
            local valid_items = c:where(function(item) return item.valid end)

            assert.are.equal(0, #valid_items._items)

            -- Add valid item
            local item1 = c:add(neostate.Disposable({ value = 10, valid = true }))
            assert.are.equal(1, #valid_items._items)

            -- Add invalid item
            c:add(neostate.Disposable({ value = 20, valid = false }))
            assert.are.equal(1, #valid_items._items)
        end)

        it("should forward child additions to parent with validation", function()
            local c = neostate.Collection("Items")
            local valid_items = c:where(function(item) return item.valid end)

            -- Add valid item to filtered collection
            local item1 = valid_items:add(neostate.Disposable({ value = 10, valid = true }))

            -- Should appear in both collections
            assert.are.equal(1, #valid_items._items)
            assert.are.equal(1, #c._items)

            -- Try to add invalid item to filtered collection
            local success = pcall(function()
                valid_items:add(neostate.Disposable({ value = 20, valid = false }))
            end)

            assert.is_false(success)
            assert.are.equal(1, #valid_items._items)
            assert.are.equal(1, #c._items)
        end)
    end)

    describe("Reactive signal filtering", function()
        it("should filter based on reactive signal values", function()
            local c = neostate.Collection("Items")
            c:add_index("by_status", function(item) return item.status end)

            local item1 = neostate.Disposable({ id = 1 })
            item1.status = neostate.Signal("pending")

            local item2 = neostate.Disposable({ id = 2 })
            item2.status = neostate.Signal("active")

            c:add(item1)
            c:add(item2)

            local active_items = c:where("by_status", "active")

            -- Check initial state
            assert.are.equal(1, #active_items._items)
            assert.are.equal(item2, active_items._items[1])

            -- Change item1 status to active
            item1.status:set("active")

            -- Now both should be in active_items
            assert.are.equal(2, #active_items._items)
        end)
    end)

    describe("Multiple filtered collections", function()
        it("should support multiple filtered views of same parent", function()
            local c = neostate.Collection("Users")
            c:add_index("by_role", function(item) return item.role end)

            local admins = c:where("by_role", "admin")
            local users = c:where("by_role", "user")

            -- Add items to parent
            local admin1 = c:add(neostate.Disposable({ id = 1, role = "admin" }))
            local user1 = c:add(neostate.Disposable({ id = 2, role = "user" }))
            local admin2 = c:add(neostate.Disposable({ id = 3, role = "admin" }))

            -- Check each filtered view
            assert.are.equal(2, #admins._items)
            assert.are.equal(1, #users._items)
            assert.are.equal(3, #c._items)

            -- Add through filtered collection
            local user2 = users:add(neostate.Disposable({ id = 4, role = "user" }))

            -- Should propagate correctly
            assert.are.equal(2, #admins._items)
            assert.are.equal(2, #users._items)
            assert.are.equal(4, #c._items)

            -- Remove from parent
            c:delete(function(i) return i == admin1 end)

            assert.are.equal(1, #admins._items)
            assert.are.equal(2, #users._items)
            assert.are.equal(3, #c._items)
        end)
    end)

    describe("Edge cases", function()
        it("should handle empty parent collection", function()
            local c = neostate.Collection("Empty")
            c:add_index("by_type", function(item) return item.type end)

            local filtered = c:where("by_type", "test")
            assert.are.equal(0, #filtered._items)
        end)

        it("should cleanup subscriptions when filtered collection is disposed", function()
            local c = neostate.Collection("Parent")
            c:add_index("by_type", function(item) return item.type end)

            local filtered = c:where("by_type", "test")

            -- Dispose the filtered collection
            filtered:dispose()

            -- Add item to parent (should not affect disposed child)
            c:add(neostate.Disposable({ type = "test" }))

            -- No errors should occur
            assert.is_true(true)
        end)

        it("should not duplicate items when adding existing parent item to child", function()
            local c = neostate.Collection("Parent")
            c:add_index("by_type", function(item) return item.type end)

            local item1 = c:add(neostate.Disposable({ type = "test" }))
            local filtered = c:where("by_type", "test")

            -- Item should already be in filtered collection
            assert.are.equal(1, #filtered._items)

            -- Try to add same item to filtered collection
            filtered:add(item1)

            -- Should not duplicate
            assert.are.equal(1, #filtered._items)
            assert.are.equal(1, #c._items)
        end)

        it("should allow custom collection names", function()
            local c = neostate.Collection("Users")
            c:add_index("by_role", function(item) return item.role end)

            -- Create filtered collection with custom name
            local admins = c:where("by_role", "admin", "AdminUsers")

            -- Check the debug name
            assert.are.equal("AdminUsers", admins._debug_name)

            -- Verify it still works functionally
            c:add(neostate.Disposable({ role = "admin" }))
            assert.are.equal(1, #admins._items)
        end)
    end)
end)
