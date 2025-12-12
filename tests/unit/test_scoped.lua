-- Tests for scoped reactivity polyfill
local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local neo = require("neograph")
local scoped = require("neodap.scoped")

-- Simple schema for testing (flat format)
local test_schema = {
  Parent = {
    name = "string",
    value = "number",
    children = { type = "edge", target = "Child", reverse = "parents" },
    __indexes = { { name = "default", fields = {} } },
  },
  Child = {
    name = "string",
    active = "bool",
    parents = { type = "edge", target = "Parent", reverse = "children" },
    parent = { type = "reference", edge = "parents" },
    __indexes = { { name = "default", fields = {} } },
  },
}

local function create_test_graph()
  local raw = neo.create(test_schema)
  return scoped.wrap(raw)
end

-- =============================================================================
-- Scope tests
-- =============================================================================

T["Scope"] = MiniTest.new_set()

T["Scope"]["creates child scope"] = function()
  local parent = scoped.Scope.new(nil)
  local child = scoped.Scope.new(parent)

  MiniTest.expect.equality(child.parent, parent)
end

T["Scope"]["cancel runs cleanups in reverse"] = function()
  local order = {}
  local scope = scoped.Scope.new(nil)

  scope:onCleanup(function() table.insert(order, 1) end)
  scope:onCleanup(function() table.insert(order, 2) end)
  scope:onCleanup(function() table.insert(order, 3) end)
  scope:cancel()

  MiniTest.expect.equality(order, { 3, 2, 1 })
end

T["Scope"]["cancel cascades to children"] = function()
  local cancelled = {}
  local parent = scoped.Scope.new(nil)
  local child1 = scoped.Scope.new(parent)
  local child2 = scoped.Scope.new(parent)
  local grandchild = scoped.Scope.new(child1)

  parent:onCleanup(function() table.insert(cancelled, "parent") end)
  child1:onCleanup(function() table.insert(cancelled, "child1") end)
  child2:onCleanup(function() table.insert(cancelled, "child2") end)
  grandchild:onCleanup(function() table.insert(cancelled, "grandchild") end)

  parent:cancel()

  -- All should be cancelled
  MiniTest.expect.equality(parent.cancelled, true)
  MiniTest.expect.equality(child1.cancelled, true)
  MiniTest.expect.equality(child2.cancelled, true)
  MiniTest.expect.equality(grandchild.cancelled, true)

  -- Order: depth-first, then reverse within each scope
  -- grandchild, child1, child2, parent
  MiniTest.expect.equality(cancelled[1], "grandchild")
  MiniTest.expect.equality(cancelled[2], "child1")
  MiniTest.expect.equality(cancelled[3], "child2")
  MiniTest.expect.equality(cancelled[4], "parent")
end

-- =============================================================================
-- Signal :use() auto-cleanup tests
-- =============================================================================

T["signal:use()"] = MiniTest.new_set()

T["signal:use()"]["raw signal has get and use"] = function()
  -- First verify raw neograph signals work as expected
  local raw_graph = neo.create(test_schema)
  local raw_entity = raw_graph:insert("Parent", { name = "test" })

  -- Check raw signal structure (it's a table, not userdata)
  local raw_signal = raw_entity.name
  MiniTest.expect.equality(type(raw_signal), "table")

  -- Check methods exist
  local has_get = type(raw_signal.get) == "function"
  local has_use = type(raw_signal.use) == "function"
  MiniTest.expect.equality(has_get, true)
  MiniTest.expect.equality(has_use, true)

  -- Check value
  MiniTest.expect.equality(raw_signal:get(), "test")

  -- Check edge too
  local raw_edge = raw_entity.children
  MiniTest.expect.equality(type(raw_edge), "table")
  MiniTest.expect.equality(type(raw_edge.each), "function")
  MiniTest.expect.equality(type(raw_edge.iter), "function")
end

T["signal:use()"]["wrapper detects signals"] = function()
  local raw_graph = neo.create(test_schema)
  local raw_entity = raw_graph:insert("Parent", { name = "test" })
  local raw_signal = raw_entity.name

  -- Test our is_signal detection directly
  local ok_get, get_fn = pcall(function() return raw_signal.get end)
  local ok_use, use_fn = pcall(function() return raw_signal.use end)

  MiniTest.expect.equality(ok_get, true)
  MiniTest.expect.equality(ok_use, true)
  MiniTest.expect.equality(type(get_fn), "function")
  MiniTest.expect.equality(type(use_fn), "function")
end

T["signal:use()"]["raw entity property access"] = function()
  local raw_graph = neo.create(test_schema)
  local raw_entity = raw_graph:insert("Parent", { name = "test" })

  -- Check raw property access
  local raw_name = raw_entity.name
  MiniTest.expect.equality(type(raw_name), "table")
  MiniTest.expect.equality(type(raw_name.get), "function")
  MiniTest.expect.equality(raw_name:get(), "test")

  -- Check using bracket syntax
  local raw_name2 = raw_entity["name"]
  MiniTest.expect.equality(type(raw_name2), "table")
  MiniTest.expect.equality(raw_name2:get(), "test")
end

T["signal:use()"]["patches entity signals"] = function()
  local graph = create_test_graph()
  local entity = graph:insert("Parent", { name = "test" })

  -- Check patched entity (via __index hook)
  MiniTest.expect.equality(rawget(entity, "_scoped_patched"), true)

  -- Check signal works
  local name_signal = entity.name
  MiniTest.expect.equality(type(name_signal.get), "function")
  MiniTest.expect.equality(type(name_signal.use), "function")
  MiniTest.expect.equality(name_signal:get(), "test")

  -- Check signal is patched
  MiniTest.expect.equality(rawget(name_signal, "_scoped_patched"), true)
end

T["signal:use()"]["auto-registers with current scope"] = function()
  local graph = create_test_graph()
  local entity = graph:insert("Parent", { name = "initial" })

  local calls = {}
  local scope = scoped.createScope()

  scoped.withScope(scope, function()
    entity.name:use(function(v)
      table.insert(calls, v)
    end)
  end)

  -- Initial call from :use()
  MiniTest.expect.equality(#calls, 1)
  MiniTest.expect.equality(calls[1], "initial")

  -- Update triggers callback
  entity.name:set("test")
  MiniTest.expect.equality(#calls, 2)
  MiniTest.expect.equality(calls[2], "test")

  -- Cancel scope - subscription should be cleaned up
  scope:cancel()

  -- Further updates should NOT trigger callback
  entity.name:set("after cancel")
  MiniTest.expect.equality(#calls, 2)  -- Still 2
end

-- =============================================================================
-- Edge :each() scoped tests
-- =============================================================================

T["edge:each()"] = MiniTest.new_set()

T["edge:each()"]["creates scope per item"] = function()
  local graph = create_test_graph()
  local parent = graph:insert("Parent", {})

  local entered = {}
  local cleaned = {}

  parent.children:each(function(child)
    local name = child.name:get()
    table.insert(entered, name)
    return function()
      table.insert(cleaned, name)
    end
  end)

  -- Add children
  local c1 = graph:insert("Child", { name = "c1" })
  local c2 = graph:insert("Child", { name = "c2" })
  parent.children:link(c1)
  parent.children:link(c2)

  MiniTest.expect.equality(entered, { "c1", "c2" })
  MiniTest.expect.equality(cleaned, {})

  -- Remove c1
  parent.children:unlink(c1)
  MiniTest.expect.equality(cleaned, { "c1" })

  -- Remove c2
  parent.children:unlink(c2)
  MiniTest.expect.equality(cleaned, { "c1", "c2" })
end

T["edge:each()"]["nested subscriptions die with item"] = function()
  local graph = create_test_graph()
  local parent = graph:insert("Parent", {})

  local prop_calls = {}

  parent.children:each(function(child)
    -- Nested subscription - should die when child removed
    child.active:use(function(v)
      table.insert(prop_calls, { child.name:get(), v })
    end)
  end)

  -- Add child
  local c1 = graph:insert("Child", { name = "c1", active = false })
  parent.children:link(c1)

  -- Initial call from :use()
  MiniTest.expect.equality(#prop_calls, 1)
  MiniTest.expect.equality(prop_calls[1][1], "c1")
  MiniTest.expect.equality(prop_calls[1][2], false)

  -- Update active
  c1.active:set(true)
  MiniTest.expect.equality(#prop_calls, 2)
  MiniTest.expect.equality(prop_calls[2][2], true)

  -- Remove child - should cancel nested subscription
  parent.children:unlink(c1)

  -- Further updates should NOT trigger
  c1.active:set(false)
  MiniTest.expect.equality(#prop_calls, 2)  -- Still 2
end

T["edge:each()"]["deeply nested scopes cascade correctly"] = function()
  local graph = create_test_graph()
  local parent = graph:insert("Parent", {})

  local log = {}

  local outer_scope = scoped.createScope()

  scoped.withScope(outer_scope, function()
    parent.children:each(function(child)
      table.insert(log, "enter:" .. child.name:get())

      -- Nested property subscription
      child.active:use(function(v)
        table.insert(log, "active:" .. child.name:get() .. "=" .. tostring(v))
      end)

      return function()
        table.insert(log, "leave:" .. child.name:get())
      end
    end)
  end)

  -- Add child
  local c1 = graph:insert("Child", { name = "c1", active = false })
  parent.children:link(c1)

  MiniTest.expect.equality(log, {
    "enter:c1",
    "active:c1=false",
  })

  -- Update
  c1.active:set(true)
  MiniTest.expect.equality(log[3], "active:c1=true")

  -- Cancel outer scope - should cascade and clean everything
  outer_scope:cancel()

  -- Should have cleanup
  MiniTest.expect.equality(log[4], "leave:c1")

  -- Further updates should not trigger
  c1.active:set(false)
  MiniTest.expect.equality(#log, 4)  -- No more entries
end

-- =============================================================================
-- Integration test
-- =============================================================================

T["integration"] = MiniTest.new_set()

T["integration"]["realistic plugin pattern"] = function()
  local graph = create_test_graph()
  local parent = graph:insert("Parent", { name = "root", value = 0 })

  local ui_state = {}
  local plugin_scope = scoped.createScope()

  -- Simulate a plugin that watches parent and its children
  scoped.withScope(plugin_scope, function()
    -- Watch parent's value
    parent.value:use(function(v)
      ui_state.parent_value = v
    end)

    -- Watch children
    parent.children:each(function(child)
      local name = child.name:get()
      ui_state[name] = { active = nil }

      child.active:use(function(v)
        ui_state[name].active = v
      end)

      return function()
        ui_state[name] = nil
      end
    end)
  end)

  -- Initial state
  MiniTest.expect.equality(ui_state.parent_value, 0)

  -- Add children
  local c1 = graph:insert("Child", { name = "c1", active = true })
  local c2 = graph:insert("Child", { name = "c2", active = false })
  parent.children:link(c1)
  parent.children:link(c2)

  MiniTest.expect.equality(ui_state.c1.active, true)
  MiniTest.expect.equality(ui_state.c2.active, false)

  -- Update
  c1.active:set(false)
  MiniTest.expect.equality(ui_state.c1.active, false)

  parent.value:set(42)
  MiniTest.expect.equality(ui_state.parent_value, 42)

  -- Remove c1
  parent.children:unlink(c1)
  MiniTest.expect.equality(ui_state.c1, nil)
  MiniTest.expect.equality(ui_state.c2.active, false)  -- c2 still tracked

  -- Dispose plugin
  plugin_scope:cancel()

  -- All reactivity dead
  c2.active:set(true)
  parent.value:set(100)
  MiniTest.expect.equality(ui_state.c2, nil)  -- cleaned up
  MiniTest.expect.equality(ui_state.parent_value, 42)  -- not updated
end

return T
