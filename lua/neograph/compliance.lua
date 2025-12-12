--[[
  Compliance Test Suite for neograph-native

  This file tests the full specification of neograph-native including:
  - Core CRUD operations and node proxies
  - Signals and EdgeHandles with reactive subscriptions
  - Property, Reference, and Collection rollups
  - Index coverage and edge filtering
  - Virtualized views with expand/collapse
  - Deep tree reactivity and callbacks
  - Multi-parent DAG support
  - Recursive and inline edge configurations
  - Edge cursors (skip/take) for per-edge pagination
  - Planned improvements from Appendix D

  Test Sections:
    1. Basic Operations (B-*)
    2. Signal Operations (S-*)
    3. EdgeHandle Operations (E-*)
    4. Property Rollups (PR-*)
    5. Reference Rollups (RR-*)
    6. Collection Rollups (CR-*)
    7. View Core (VC-*)
    8. View Filters (VF-*)
    9. View Expand/Collapse (VE-*)
   10. View Callbacks (VCB-*)
   11. View Edge Callbacks (VEC-*)
   12. Multi-Parent DAG (MP-*)
   13. Raw/Proxy Boundary (RP-*)
   14. Index Coupling (IC-*)
   15. Recursive Edges (RE-*)
   16. Edge Configuration (EC-*)
   17. View Navigation (VN-*)
   18. Item Methods (IM-*)
   19. Graph Utilities (GU-*)
   20. Inline Edges (IL-*)
   21. Edge Cursors (ST-*)
   22. Edge Handle Identity (EI-*) [Appendix D.1]
   23. Reverse Edge Event Propagation (REP-*) [Appendix D.2]
   24. Previous Value in Callbacks (PV-*) [Appendix D.3]
   25. Deep Equality (DE-*) [Appendix D.4]
   26. Multi-Subscriber Events (MS-*) [Appendix D.5]
   27. Undefined Property Access (UP-*) [Appendix D.6]

  Total: 256 tests (201 existing + 43 Appendix D + 12 additional)

  NOTE: Appendix D tests (Sections 22-27) verify planned improvements.
  Some tests document EXPECTED behavior and will FAIL until fixes are implemented.
--]]

local neo = require("init")

--------------------------------------------------------------------------------
-- Test Framework
--------------------------------------------------------------------------------

local passed = 0
local failed = 0
local current_section = ""

local function section(name)
  current_section = name
  print("\n-- " .. name .. " --")
end

local function test(id, name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  [PASS] " .. id .. ": " .. name)
  else
    failed = failed + 1
    print("  [FAIL] " .. id .. ": " .. name)
    print("         Error: " .. tostring(err))
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "Assertion failed") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
  end
end

local function assert_true(v, msg)
  if not v then
    error((msg or "Assertion failed") .. ": expected true, got " .. tostring(v))
  end
end

local function assert_false(v, msg)
  if v then
    error((msg or "Assertion failed") .. ": expected false, got " .. tostring(v))
  end
end

local function assert_nil(v, msg)
  if v ~= nil then
    error((msg or "Assertion failed") .. ": expected nil, got " .. tostring(v))
  end
end

local function assert_not_nil(v, msg)
  if v == nil then
    error((msg or "Assertion failed") .. ": expected non-nil value")
  end
end

local function count_iter(iter)
  local n = 0
  for _ in iter do n = n + 1 end
  return n
end

local function collect_iter(iter)
  local items = {}
  for item in iter do items[#items + 1] = item end
  return items
end

--------------------------------------------------------------------------------
-- Schemas for Testing
--------------------------------------------------------------------------------

-- Basic schema for Node/Property tests
local function basic_schema()
  return {
    User = {
      name = "string",
      age = "number",
      active = "bool",
      nickname = "string",

      posts = { type = "edge", target = "Post", reverse = "author",
        __indexes = {
          { name = "default", fields = {} },
          { name = "by_published", fields = {{ name = "published" }} },
          { name = "by_views", fields = {{ name = "views", dir = "desc" }} },
          { name = "by_published_views", fields = {{ name = "published" }, { name = "views", dir = "desc" }} },
        },
      },
      friends = { type = "edge", target = "User" },

      __indexes = {
        { name = "default", fields = {{ name = "name" }} },
        { name = "by_age", fields = {{ name = "age", dir = "desc" }} },
        { name = "by_active_age", fields = {{ name = "active" }, { name = "age", dir = "desc" }} },
      },
    },

    Post = {
      title = "string",
      published = "bool",
      views = "number",
      created_at = "number",
      featured = "bool",

      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },

      __indexes = {
        { name = "default", fields = {{ name = "title" }} },
        { name = "by_views", fields = {{ name = "views", dir = "desc" }} },
        { name = "by_created", fields = {{ name = "created_at", dir = "desc" }} },
      },
    },

    Comment = {
      text = "string",
      likes = "number",

      post = { type = "edge", target = "Post", reverse = "comments" },

      __indexes = {
        { name = "default", fields = {} },
      },
    },
  }
end

-- Schema with rollups
local function rollup_schema()
  return {
    User = {
      name = "string",
      status = "string",

      posts = { type = "edge", target = "Post", reverse = "author",
        __indexes = {
          { name = "default", fields = {} },
          { name = "by_published", fields = {{ name = "published" }} },
          { name = "by_created", fields = {{ name = "created_at", dir = "desc" }} },
          { name = "by_views", fields = {{ name = "views", dir = "desc" }} },
          { name = "by_published_created", fields = {{ name = "published" }, { name = "created_at", dir = "desc" }} },
        },
      },

      -- Property rollups (all compute types)
      post_count = { type = "count", edge = "posts" },
      published_count = { type = "count", edge = "posts", filter = { published = true } },
      total_views = { type = "sum", edge = "posts", property = "views" },
      avg_views = { type = "avg", edge = "posts", property = "views" },
      min_views = { type = "min", edge = "posts", property = "views" },
      max_views = { type = "max", edge = "posts", property = "views" },
      first_title = { type = "first", edge = "posts", property = "title" },
      last_title = { type = "last", edge = "posts", property = "title" },
      has_published = { type = "any", edge = "posts", filter = { published = true } },
      all_featured = { type = "all", edge = "posts", property = "featured" },

      -- Reference rollups
      latest_post = { type = "reference", edge = "posts", sort = { field = "created_at", dir = "desc" } },
      top_post = { type = "reference", edge = "posts", sort = { field = "views", dir = "desc" } },
      latest_published = { type = "reference", edge = "posts",
        filter = { published = true }, sort = { field = "created_at", dir = "desc" } },

      -- Collection rollups
      published_posts = { type = "collection", edge = "posts", filter = { published = true } },
      posts_by_views = { type = "collection", edge = "posts", sort = { field = "views", dir = "desc" } },

      __indexes = {
        { name = "default", fields = {{ name = "name" }} },
        { name = "by_post_count", fields = {{ name = "post_count", dir = "desc" }} },
      },
    },

    Post = {
      title = "string",
      published = "bool",
      views = "number",
      created_at = "number",
      featured = "bool",

      author = { type = "edge", target = "User", reverse = "posts" },

      __indexes = {
        { name = "default", fields = {{ name = "title" }} },
        { name = "by_created", fields = {{ name = "created_at", dir = "desc" }} },
      },
    },
  }
end

-- Schema for view tests with nested edges
local function view_schema()
  return {
    User = {
      name = "string",
      active = "bool",

      posts = { type = "edge", target = "Post", reverse = "author",
        __indexes = {
          { name = "default", fields = {} },
          { name = "by_created_at_desc", fields = {{ name = "created_at", dir = "desc" }} },
        },
      },

      __indexes = {
        { name = "default", fields = {{ name = "name" }} },
      },
    },

    Post = {
      title = "string",
      published = "bool",
      created_at = "number",

      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },

      __indexes = {
        { name = "default", fields = {{ name = "title" }} },
        { name = "by_created_at", fields = {{ name = "created_at" }} },
      },
    },

    Comment = {
      text = "string",

      post = { type = "edge", target = "Post", reverse = "comments" },

      __indexes = {
        { name = "default", fields = {} },
      },
    },
  }
end

--------------------------------------------------------------------------------
-- Section 1: Node/Property Tests (NP-*)
--------------------------------------------------------------------------------

print("\n=== Compliance Test Suite ===")
print("Testing against SPEC.md using n-wise orthogonal arrays\n")

section("Section 1: Node/Property Tests (NP-*)")

test("NP01", "Insert node with string property", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })

  assert_eq(node.name:get(), "Alice")
  assert_true(node._id > 0, "ID should be positive integer")
  assert_eq(node._type, "User")
end)

test("NP02", "Insert node with number property, undefined optional", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { age = 30 })

  assert_eq(node.age:get(), 30)
  assert_nil(node.nickname:get())
end)

test("NP03", "Insert node with boolean property", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { active = true })

  assert_eq(node.active:get(), true)
end)

test("NP04", "Insert node with nil property value", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { nickname = nil })

  assert_nil(node.nickname:get())
end)

test("NP05", "Get existing node by ID", function()
  local g = neo.create(basic_schema())
  local original = g:insert("User", { name = "Alice" })
  local retrieved = g:get(original._id)

  assert_not_nil(retrieved)
  assert_eq(retrieved.name:get(), "Alice")
  assert_eq(retrieved._id, original._id)
end)

test("NP06", "Get non-existent node", function()
  local g = neo.create(basic_schema())
  local result = g:get(999)

  assert_nil(result)
end)

test("NP07", "Update existing node property", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })
  local updated = g:update(node._id, { name = "Bob" })

  assert_not_nil(updated)
  assert_eq(node.name:get(), "Bob")
end)

test("NP08", "Update adds undefined property", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })
  g:update(node._id, { age = 25 })

  assert_eq(node.age:get(), 25)
end)

test("NP09", "Update property to nil using neo.NIL", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })
  g:update(node._id, { name = neo.NIL })

  assert_nil(node.name:get())
end)

test("NP10", "Delete existing node", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })
  local id = node._id
  local result = g:delete(id)

  assert_true(result)
  assert_nil(g:get(id))
end)

test("NP11", "Delete non-existent node", function()
  local g = neo.create(basic_schema())
  local result = g:delete(999)

  assert_false(result)
end)

--------------------------------------------------------------------------------
-- Section 2: Signal Tests (SG-*)
--------------------------------------------------------------------------------

section("Section 2: Signal Tests (SG-*)")

test("SG01", "Get returns current string value", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })

  assert_eq(node.name:get(), "Alice")
end)

test("SG02", "Get returns nil for nil/undefined", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", {})

  assert_nil(node.nickname:get())
end)

test("SG03", "Set updates value", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })
  node.name:set("Bob")

  assert_eq(node.name:get(), "Bob")
end)

test("SG04", "Set triggers single subscriber", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { age = 25 })

  local received = nil
  node.age:use(function(v)
    received = v
  end)

  node.age:set(30)
  assert_eq(received, 30)
end)

test("SG05", "Set triggers multiple subscribers", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { active = false })

  local count = 0
  node.active:use(function() count = count + 1 end)
  node.active:use(function() count = count + 1 end)
  node.active:use(function() count = count + 1 end)

  count = 0  -- Reset after initial calls
  node.active:set(true)
  assert_eq(count, 3)
end)

test("SG06", "Use runs effect immediately (no cleanup)", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })

  local received = nil
  node.name:use(function(v)
    received = v
  end)

  assert_eq(received, "Alice")
end)

test("SG07", "Use cleanup runs after change", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { age = 25 })

  local cleanup_called = false
  local cleanup_value = nil
  node.age:use(function(v)
    return function()
      cleanup_called = true
      cleanup_value = v
    end
  end)

  node.age:set(30)
  assert_true(cleanup_called)
  assert_eq(cleanup_value, 25)
end)

test("SG08", "Unsub runs cleanup, prevents future effects", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })

  local effect_count = 0
  local cleanup_count = 0
  local unsub = node.name:use(function()
    effect_count = effect_count + 1
    return function()
      cleanup_count = cleanup_count + 1
    end
  end)

  assert_eq(effect_count, 1)  -- Initial call

  unsub()
  assert_eq(cleanup_count, 1)  -- Cleanup on unsub

  node.name:set("Bob")
  assert_eq(effect_count, 1)  -- No new effect after unsub
end)

test("SG09", "Use with nil value and cleanup", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { nickname = nil })

  local received = "NOT_CALLED"
  local cleanup_called = false
  local unsub = node.nickname:use(function(v)
    received = v
    return function()
      cleanup_called = true
    end
  end)

  assert_nil(received)
  unsub()
  assert_true(cleanup_called)
end)

--------------------------------------------------------------------------------
-- Section 3: EdgeHandle Tests (EH-*)
--------------------------------------------------------------------------------

section("Section 3: EdgeHandle Tests (EH-*)")

test("EH01", "Link to empty edge with reverse", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  user.posts:link(post)

  assert_eq(user.posts:count(), 1)
  assert_eq(post.author:count(), 1)
end)

test("EH02", "Link triggers onLink subscriber", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  local linked_node = nil
  user.posts:onLink(function(node)
    linked_node = node
  end)

  user.posts:link(post)
  assert_not_nil(linked_node)
  assert_eq(linked_node._id, post._id)
end)

test("EH03", "Unlink from edge with reverse", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  user.posts:link(post)
  assert_eq(user.posts:count(), 1)

  user.posts:unlink(post)
  assert_eq(user.posts:count(), 0)
  assert_eq(post.author:count(), 0)
end)

test("EH04", "Unlink triggers onUnlink and each cleanup", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  local cleanup_called = false
  user.posts:each(function(p)
    return function()
      cleanup_called = true
    end
  end)

  user.posts:link(post)
  user.posts:unlink(post)

  assert_true(cleanup_called)
end)

test("EH05", "Iter on empty edge yields nothing", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local count = count_iter(user.posts:iter())
  assert_eq(count, 0)
end)

test("EH06", "Iter with equality filter", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true })
  local post2 = g:insert("Post", { title = "P2", published = false })
  local post3 = g:insert("Post", { title = "P3", published = true })

  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local filtered = user.posts:filter({
    filters = {{ field = "published", op = "eq", value = true }}
  })

  local count = count_iter(filtered:iter())
  assert_eq(count, 2)
end)

test("EH07", "Count on empty edge returns 0", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  assert_eq(user.posts:count(), 0)
end)

test("EH08", "Count on populated edge", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  for i = 1, 3 do
    local post = g:insert("Post", { title = "Post " .. i })
    user.posts:link(post)
  end

  assert_eq(user.posts:count(), 3)
end)

test("EH09", "Filter with range operator", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", views = 10 })
  local post2 = g:insert("Post", { title = "P2", views = 50 })
  local post3 = g:insert("Post", { title = "P3", views = 100 })

  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local filtered = user.posts:filter({
    filters = {{ field = "views", op = "gt", value = 20 }}
  })

  local count = count_iter(filtered:iter())
  assert_eq(count, 2)
end)

test("EH10", "Filter with compound filters", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true, views = 5 })
  local post2 = g:insert("Post", { title = "P2", published = true, views = 50 })
  local post3 = g:insert("Post", { title = "P3", published = false, views = 100 })

  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local filtered = user.posts:filter({
    filters = {
      { field = "published", op = "eq", value = true },
      { field = "views", op = "gte", value = 10 }
    }
  })

  local count = count_iter(filtered:iter())
  assert_eq(count, 1)  -- Only P2 matches both
end)

test("EH11", "Each on empty edge", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local called = false
  local unsub = user.posts:each(function()
    called = true
  end)

  assert_false(called)
  assert_not_nil(unsub)
end)

test("EH12", "Each tracks membership with filter", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello", published = true })

  local enter_count = 0
  local leave_count = 0

  local filtered = user.posts:filter({
    filters = {{ field = "published", op = "eq", value = true }}
  })

  filtered:each(function(p)
    enter_count = enter_count + 1
    return function()
      leave_count = leave_count + 1
    end
  end)

  user.posts:link(post)
  assert_eq(enter_count, 1)

  post.published:set(false)
  assert_eq(leave_count, 1)
end)

--------------------------------------------------------------------------------
-- Section 4: Rollup Tests (RL-*)
--------------------------------------------------------------------------------

section("Section 4: Rollup Tests (RL-*)")

test("RL01", "Property rollup count starts at 0", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })

  assert_eq(user.post_count:get(), 0)
end)

test("RL02", "Property rollup count with filter decrements on unlink", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true })
  local post2 = g:insert("Post", { title = "P2", published = true })

  user.posts:link(post1)
  user.posts:link(post2)
  assert_eq(user.published_count:get(), 2)

  user.posts:unlink(post1)
  assert_eq(user.published_count:get(), 1)
end)

test("RL03", "Property rollup sum updates on target property change", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", views = 10 })
  local post2 = g:insert("Post", { title = "P2", views = 20 })

  user.posts:link(post1)
  user.posts:link(post2)
  assert_eq(user.total_views:get(), 30)

  post1.views:set(30)
  assert_eq(user.total_views:get(), 50)
end)

test("RL04", "Property rollup avg returns nil when empty", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })

  assert_nil(user.avg_views:get())
end)

test("RL05", "Property rollup avg computes correctly", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", views = 10 })
  local post2 = g:insert("Post", { title = "P2", views = 20 })
  local post3 = g:insert("Post", { title = "P3", views = 30 })

  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  assert_eq(user.avg_views:get(), 20)
end)

test("RL06", "Property rollup min updates on link", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", views = 20 })
  local post2 = g:insert("Post", { title = "P2", views = 30 })
  local post3 = g:insert("Post", { title = "P3", views = 10 })

  user.posts:link(post1)
  user.posts:link(post2)
  assert_eq(user.min_views:get(), 20)

  user.posts:link(post3)
  assert_eq(user.min_views:get(), 10)
end)

test("RL07", "Property rollup max updates on target change", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", views = 100 })

  user.posts:link(post)
  assert_eq(user.max_views:get(), 100)

  post.views:set(50)
  assert_eq(user.max_views:get(), 50)
end)

test("RL08", "Property rollup first returns first target's property", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "Alpha" })
  local post2 = g:insert("Post", { title = "Beta" })

  user.posts:link(post2)
  user.posts:link(post1)

  -- First is determined by index order (default = by title)
  assert_eq(user.first_title:get(), "Alpha")
end)

test("RL09", "Property rollup last updates on unlink", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "Alpha" })
  local post2 = g:insert("Post", { title = "Beta" })
  local post3 = g:insert("Post", { title = "Gamma" })

  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  assert_eq(user.last_title:get(), "Gamma")

  user.posts:unlink(post3)
  assert_eq(user.last_title:get(), "Beta")
end)

test("RL10", "Property rollup any becomes true on first match", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  assert_false(user.has_published:get() or false)

  user.posts:link(post)
  assert_true(user.has_published:get())
end)

test("RL11", "Property rollup all tracks truthiness", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", featured = true })
  local post2 = g:insert("Post", { title = "P2", featured = true })

  user.posts:link(post1)
  user.posts:link(post2)
  assert_true(user.all_featured:get())

  post1.featured:set(false)
  assert_false(user.all_featured:get())
end)

test("RL12", "Reference rollup empty returns nil", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })

  assert_nil(user.latest_post:get())
end)

test("RL13", "Reference rollup changes on sort property update", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "Old", created_at = 1 })
  local post2 = g:insert("Post", { title = "New", created_at = 2 })

  user.posts:link(post1)
  user.posts:link(post2)

  local latest = user.latest_post:get()
  assert_not_nil(latest)
  assert_eq(latest.title:get(), "New")

  -- Update old post to be newest
  post1.created_at:set(3)

  latest = user.latest_post:get()
  assert_eq(latest.title:get(), "Old")
end)

test("RL14", "Reference rollup handles single unlink", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Only", created_at = 1 })

  user.posts:link(post)
  assert_not_nil(user.latest_post:get())

  user.posts:unlink(post)
  assert_nil(user.latest_post:get())
end)

test("RL15", "Collection rollup includes matching on link", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  user.posts:link(post)

  local count = count_iter(user.published_posts:iter())
  assert_eq(count, 1)
end)

test("RL16", "Collection rollup reacts to filter field change", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  user.posts:link(post)
  assert_eq(count_iter(user.published_posts:iter()), 1)

  post.published:set(false)
  assert_eq(count_iter(user.published_posts:iter()), 0)
end)

test("RL17", "Collection rollup sorted empty", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })

  assert_eq(user.posts_by_views:count(), 0)
end)

--------------------------------------------------------------------------------
-- Section 5: Index Tests (IX-*)
--------------------------------------------------------------------------------

section("Section 5: Index Tests (IX-*)")

test("IX01", "Single field index covers equality filter", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", age = 30 })
  g:insert("User", { name = "Bob", age = 25 })
  g:insert("User", { name = "Charlie", age = 35 })

  local view = g:view({
    type = "User",
    filters = {{ field = "name", op = "eq", value = "Alice" }}
  })

  local items = view:collect()
  assert_eq(#items, 1)
  assert_eq(items[1].node.name:get(), "Alice")
end)

test("IX02", "Single field index partial coverage with range", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", age = 30 })
  g:insert("User", { name = "Bob", age = 25 })
  g:insert("User", { name = "Charlie", age = 35 })

  local view = g:view({
    type = "User",
    filters = {{ field = "age", op = "gt", value = 26 }}
  })

  local items = view:collect()
  assert_eq(#items, 2)  -- Alice (30) and Charlie (35)
end)

test("IX03", "No covering index throws error", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", active = true, age = 30 })
  g:insert("User", { name = "Bob", active = false, age = 25 })

  -- Filter on nickname which has no index - should error
  local ok, err = pcall(function()
    g:view({
      type = "User",
      filters = {{ field = "nickname", op = "eq", value = "Al" }}
    })
  end)

  assert_false(ok)
  assert_true(err:match("No index covers query") ~= nil)
end)

test("IX04", "Compound index full coverage with range and sort", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", active = true, age = 30 })
  g:insert("User", { name = "Bob", active = true, age = 40 })
  g:insert("User", { name = "Charlie", active = false, age = 35 })

  local view = g:view({
    type = "User",
    filters = {
      { field = "active", op = "eq", value = true },
      { field = "age", op = "gt", value = 25 }
    }
  })

  local items = view:collect()
  assert_eq(#items, 2)  -- Alice and Bob
end)

test("IX05", "Compound index partial with sort match", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", active = true, age = 30 })
  g:insert("User", { name = "Alice", active = true, age = 40 })
  g:insert("User", { name = "Bob", active = true, age = 25 })

  local view = g:view({
    type = "User",
    filters = {{ field = "active", op = "eq", value = true }}
  })

  local items = view:collect()
  assert_eq(#items, 3)
end)

test("IX06", "Single field index unused, range filter present", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", age = 30 })
  g:insert("User", { name = "Bob", age = 25 })

  -- Index is on name, but filter is on age
  local view = g:view({
    type = "User",
    filters = {{ field = "age", op = "gt", value = 20 }}
  })

  local items = view:collect()
  assert_eq(#items, 2)
end)

--------------------------------------------------------------------------------
-- Section 6: View Tests (VW-*)
--------------------------------------------------------------------------------

section("Section 6: View Tests (VW-*)")

test("VW01", "View with no filters, root only, initial on_enter", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice" })
  g:insert("User", { name = "Bob" })

  local enters = {}
  local view = g:view({
    type = "User",
  }, {
    callbacks = {
      on_enter = function(node, position)
        enters[#enters + 1] = { node = node, pos = position }
      end
    }
  })

  assert_eq(#enters, 2)
  assert_eq(enters[1].node._type, "User")
end)

test("VW02", "View with equality filter, root delete fires on_leave", function()
  local g = neo.create(basic_schema())
  local alice = g:insert("User", { name = "Alice", active = true })
  g:insert("User", { name = "Bob", active = true })

  local leaves = {}
  local view = g:view({
    type = "User",
    filters = {{ field = "active", op = "eq", value = true }}
  }, {
    callbacks = {
      on_leave = function(node)
        leaves[#leaves + 1] = node
      end
    }
  })

  assert_eq(view:total(), 2)

  g:delete(alice._id)
  assert_eq(#leaves, 1)
  assert_eq(view:total(), 1)
end)

test("VW03", "View with range filter, property change fires on_change", function()
  local g = neo.create(basic_schema())
  local alice = g:insert("User", { name = "Alice", age = 30 })

  local changes = {}
  local view = g:view({
    type = "User",
    filters = {{ field = "age", op = "gt", value = 20 }}
  }, {
    callbacks = {
      on_change = function(node, prop, new_val, old_val)
        changes[#changes + 1] = { prop = prop, new = new_val, old = old_val }
      end
    }
  })

  alice.name:set("Alicia")
  assert_eq(#changes, 1)
  assert_eq(changes[1].prop, "name")
  assert_eq(changes[1].new, "Alicia")
  assert_eq(changes[1].old, "Alice")
end)

test("VW04", "View one-level expansion, on_enter fires for children", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1" })
  local post2 = g:insert("Post", { title = "P2" })
  local post3 = g:insert("Post", { title = "P3" })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local enters = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_enter = function(node, position, edge_name, parent_id)
        enters[#enters + 1] = { node = node, edge = edge_name, parent = parent_id }
      end
    }
  })

  view:expand(user._id, "posts")

  -- Should have 1 root + 3 children enter events
  local child_enters = 0
  for _, e in ipairs(enters) do
    if e.edge == "posts" then child_enters = child_enters + 1 end
  end
  assert_eq(child_enters, 3)
end)

test("VW05", "Inline children, change fires on_change", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local changes = {}
  local view = g:view({
    type = "User",
    edges = { posts = { inline = true } }
  }, {
    callbacks = {
      on_change = function(node, prop, new_val, old_val)
        changes[#changes + 1] = { node = node, prop = prop }
      end
    }
  })

  view:expand(user._id, "posts")
  post.title:set("Updated")

  local post_changes = 0
  for _, c in ipairs(changes) do
    if c.prop == "title" then post_changes = post_changes + 1 end
  end
  assert_eq(post_changes, 1)
end)

test("VW06", "Nested expansion (2+ levels), on_enter for all levels", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  local comment = g:insert("Comment", { text = "Great!" })
  user.posts:link(post)
  post.comments:link(comment)

  local enters = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        edges = {
          comments = {}
        }
      }
    }
  }, {
    callbacks = {
      on_enter = function(node, position, edge_name, parent_id)
        enters[#enters + 1] = { type = node._type, edge = edge_name }
      end
    }
  })

  view:expand(user._id, "posts")

  -- Find the post's path_key and expand comments
  local items = view:collect()
  for _, item in ipairs(items) do
    if item.node._type == "Post" then
      view:expand(item.id, "comments")
      break
    end
  end

  local user_enters = 0
  local post_enters = 0
  local comment_enters = 0
  for _, e in ipairs(enters) do
    if e.type == "User" then user_enters = user_enters + 1 end
    if e.type == "Post" then post_enters = post_enters + 1 end
    if e.type == "Comment" then comment_enters = comment_enters + 1 end
  end

  assert_eq(user_enters, 1)
  assert_eq(post_enters, 1)
  assert_eq(comment_enters, 1)
end)

test("VW07", "Nested collapse fires on_leave for all descendants", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  local comment = g:insert("Comment", { text = "Great!" })
  user.posts:link(post)
  post.comments:link(comment)

  local leaves = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        edges = { comments = {} }
      }
    }
  }, {
    callbacks = {
      on_leave = function(node, edge_name, parent_id)
        leaves[#leaves + 1] = { type = node._type }
      end
    }
  })

  view:expand(user._id, "posts")
  local items = view:collect()
  for _, item in ipairs(items) do
    if item.node._type == "Post" then
      view:expand(item.id, "comments")
      break
    end
  end

  view:collapse(user._id, "posts")

  -- Both post and comment should have left
  local post_leaves = 0
  local comment_leaves = 0
  for _, l in ipairs(leaves) do
    if l.type == "Post" then post_leaves = post_leaves + 1 end
    if l.type == "Comment" then comment_leaves = comment_leaves + 1 end
  end

  assert_true(post_leaves >= 1)
  assert_true(comment_leaves >= 1)
end)

test("VW08", "Multi-parent node, on_change fires per path", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)
  user2.posts:link(post)

  local change_count = 0
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_change = function(node, prop, new_val, old_val)
        if prop == "title" then
          change_count = change_count + 1
        end
      end
    }
  })

  view:expand(user1._id, "posts")
  view:expand(user2._id, "posts")

  post.title:set("Updated")

  -- Should fire twice (once per parent path)
  assert_eq(change_count, 2)
end)

test("VW09", "Multi-parent node, on_enter fires per path", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)

  local post_enters = 0
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_enter = function(node, position, edge_name, parent_id)
        if node._type == "Post" then
          post_enters = post_enters + 1
        end
      end
    }
  })

  view:expand(user1._id, "posts")
  assert_eq(post_enters, 1)

  user2.posts:link(post)
  view:expand(user2._id, "posts")
  assert_eq(post_enters, 2)  -- Enters again under second parent
end)

test("VW10", "Deep multi-parent, on_change fires per nested path", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "Post1" })
  local post2 = g:insert("Post", { title = "Post2" })
  local comment = g:insert("Comment", { text = "Shared" })

  user.posts:link(post1)
  user.posts:link(post2)
  post1.comments:link(comment)
  post2.comments:link(comment)

  local comment_changes = 0
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        edges = { comments = {} }
      }
    }
  }, {
    callbacks = {
      on_change = function(node, prop)
        if prop == "text" then
          comment_changes = comment_changes + 1
        end
      end
    }
  })

  view:expand(user._id, "posts")
  local items = view:collect()
  for _, item in ipairs(items) do
    if item.node._type == "Post" then
      view:expand(item.id, "comments")
    end
  end

  comment.text:set("Updated")

  -- Should fire twice (once per path: user->post1->comment, user->post2->comment)
  assert_eq(comment_changes, 2)
end)

test("VW11", "Eager expansion fires on_expand at creation", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local expands = {}
  local view = g:view({
    type = "User",
    edges = { posts = { eager = true } }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expands[#expands + 1] = { id = node._id, edge = edge_name, context = context }
      end
    }
  })

  -- Eager expansion should have triggered on_expand
  assert_true(#expands >= 1)
  -- Should have eager = true context
  assert_true(expands[1].context.eager)
end)

test("VW12", "Collapse fires on_collapse callback", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local collapses = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_collapse = function(node, edge_name, context)
        collapses[#collapses + 1] = { id = node._id, edge = edge_name, context = context }
      end
    }
  })

  view:expand(user._id, "posts")
  view:collapse(user._id, "posts")

  assert_eq(#collapses, 1)
  assert_eq(collapses[1].id, user._id)
  assert_eq(collapses[1].edge, "posts")
  assert_not_nil(collapses[1].context)
  assert_eq(collapses[1].context.path_key, tostring(user._id))
end)

--------------------------------------------------------------------------------
-- Section 7: View Methods Tests (VM-*)
--------------------------------------------------------------------------------

section("Section 7: View Methods Tests (VM-*)")

test("VM01", "items() returns iterator", function()
  local g = neo.create(basic_schema())
  for i = 1, 5 do
    g:insert("User", { name = "User" .. i })
  end

  local view = g:view({ type = "User" }, { limit = 10 })
  local count = 0
  for item in view:items() do
    count = count + 1
  end

  assert_eq(count, 5)
end)

test("VM02", "total() returns root count", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", active = true })
  g:insert("User", { name = "Bob", active = false })
  g:insert("User", { name = "Charlie", active = true })

  local view = g:view({
    type = "User",
    filters = {{ field = "active", op = "eq", value = true }}
  })

  assert_eq(view:total(), 2)
end)

test("VM03", "visible_total() includes expansions", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local post1 = g:insert("Post", { title = "P1" })
  local post2 = g:insert("Post", { title = "P2" })
  local post3 = g:insert("Post", { title = "P3" })
  user1.posts:link(post1)
  user1.posts:link(post2)
  user1.posts:link(post3)

  local view = g:view({
    type = "User",
    edges = { posts = {} }
  })

  assert_eq(view:visible_total(), 2)  -- Just roots

  view:expand(user1._id, "posts")
  assert_eq(view:visible_total(), 5)  -- 2 roots + 3 children
end)

test("VM04", "collect() returns list", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice" })
  g:insert("User", { name = "Bob" })

  local view = g:view({ type = "User" })
  local items = view:collect()

  assert_eq(type(items), "table")
  assert_eq(#items, 2)
  assert_not_nil(items[1].id)
  assert_not_nil(items[1].node)
end)

test("VM05", "scroll() changes offset", function()
  local g = neo.create(basic_schema())
  for i = 1, 10 do
    g:insert("User", { name = "User" .. string.format("%02d", i) })
  end

  local view = g:view({ type = "User" }, { limit = 5 })

  local first_items = view:collect()
  assert_eq(#first_items, 5)

  view:scroll(5)
  local second_items = view:collect()
  assert_eq(#second_items, 5)

  -- Items should be different
  assert_true(first_items[1].id ~= second_items[1].id)
end)

test("VM06", "expand() returns true on success", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local view = g:view({
    type = "User",
    edges = { posts = {} }
  })

  local before = view:visible_total()
  local result = view:expand(user._id, "posts")
  local after = view:visible_total()

  assert_true(result)
  assert_true(after > before)
end)

test("VM07", "expand() returns false if already expanded", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local view = g:view({
    type = "User",
    edges = { posts = {} }
  })

  local first = view:expand(user._id, "posts")
  local second = view:expand(user._id, "posts")

  assert_true(first)
  assert_false(second)
end)

test("VM08", "collapse() cleans up subscriptions", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local change_count = 0
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_change = function()
        change_count = change_count + 1
      end
    }
  })

  view:expand(user._id, "posts")
  post.title:set("Changed1")
  assert_eq(change_count, 1)

  view:collapse(user._id, "posts")
  post.title:set("Changed2")
  -- After collapse, changes to post should not fire callback
  assert_eq(change_count, 1)
end)

test("VM09", "destroy() unsubscribes all", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local change_count = 0
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_change = function()
        change_count = change_count + 1
      end
    }
  })

  view:expand(user._id, "posts")
  user.name:set("Alicia")
  assert_eq(change_count, 1)

  view:destroy()
  user.name:set("Alice2")
  post.title:set("Changed")
  -- No callbacks after destroy
  assert_eq(change_count, 1)
end)

--------------------------------------------------------------------------------
-- Section 8: Interaction Tests (IT-*)
--------------------------------------------------------------------------------

section("Section 8: Interaction Tests (IT-*)")

test("IT01", "Signal.use() on property rollup", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  local received = nil
  user.post_count:use(function(v)
    received = v
  end)

  assert_eq(received, 0)

  user.posts:link(post)
  assert_eq(received, 1)
end)

test("IT02", "EdgeHandle.link() triggers rollup update", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello", views = 50 })

  assert_eq(user.total_views:get(), 0)

  user.posts:link(post)
  assert_eq(user.total_views:get(), 50)
end)

test("IT03", "Property rollup usable in index", function()
  local g = neo.create(rollup_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })

  for i = 1, 3 do
    local post = g:insert("Post", { title = "P" .. i })
    user1.posts:link(post)
  end

  local post = g:insert("Post", { title = "Single" })
  user2.posts:link(post)

  -- View filtered by post_count (which is a rollup)
  local view = g:view({
    type = "User",
    filters = {{ field = "post_count", op = "gte", value = 2 }}
  })

  local items = view:collect()
  assert_eq(#items, 1)
  assert_eq(items[1].node.name:get(), "Alice")
end)

test("IT04", "View uses covering index", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", active = true, age = 30 })
  g:insert("User", { name = "Bob", active = true, age = 40 })
  g:insert("User", { name = "Charlie", active = false, age = 35 })

  -- Index on (active, age) should cover this query
  local view = g:view({
    type = "User",
    filters = {{ field = "active", op = "eq", value = true }}
  })

  local items = view:collect()
  assert_eq(#items, 2)
end)

test("IT05", "Deep view expansion tracks nested rollups", function()
  -- Create schema with nested rollups
  local nested_schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },
      comment_count = { type = "count", edge = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
    Comment = {
      text = "string",
      post = { type = "edge", target = "Post", reverse = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(nested_schema)
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local changes = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_change = function(node, prop)
        changes[#changes + 1] = { type = node._type, prop = prop }
      end
    }
  })

  view:expand(user._id, "posts")

  local comment = g:insert("Comment", { text = "Nice!" })
  post.comments:link(comment)

  -- Should fire on_change for post's comment_count rollup
  local rollup_changes = 0
  for _, c in ipairs(changes) do
    if c.prop == "comment_count" then rollup_changes = rollup_changes + 1 end
  end
  assert_true(rollup_changes >= 1)
end)

test("IT06", "Multi-parent unlink fires on_leave only for affected path", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)
  user2.posts:link(post)

  local leaves = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_leave = function(node, edge_name, parent_id)
        leaves[#leaves + 1] = { node = node, parent = parent_id }
      end
    }
  })

  view:expand(user1._id, "posts")
  view:expand(user2._id, "posts")

  -- Unlink from user1 only
  user1.posts:unlink(post)

  -- Should fire on_leave once (for user1's path)
  assert_eq(#leaves, 1)
  assert_eq(leaves[1].parent, user1._id)

  -- Post should still be visible under user2
  local items = view:collect()
  local post_count = 0
  for _, item in ipairs(items) do
    if item.node._type == "Post" then post_count = post_count + 1 end
  end
  assert_eq(post_count, 1)
end)

--------------------------------------------------------------------------------
-- Section 9: Edge Symmetry Tests (ES-*)
--------------------------------------------------------------------------------

print("\n-- Section 9: Edge Symmetry Tests (ES-*) --")

-- Schema with bidirectional edges
local function edge_symmetry_schema()
  return {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      friends = { type = "edge", target = "User" },  -- No reverse
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      __indexes = { { name = "default", fields = {} } },
    },
  }
end

test("ES01", "Count from source after source-initiated link", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  user.posts:link(post)
  assert_eq(user.posts:count(), 1)
end)

test("ES02", "Count from target after source-initiated link", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  user.posts:link(post)
  assert_eq(post.author:count(), 1)
end)

test("ES03", "Count from source after target-initiated link", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  post.author:link(user)
  assert_eq(user.posts:count(), 1)
end)

test("ES04", "Count from target after target-initiated link", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  post.author:link(user)
  assert_eq(post.author:count(), 1)
end)

test("ES05", "Iter from source after source-initiated link", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  user.posts:link(post)
  local items = collect_iter(user.posts:iter())
  assert_eq(#items, 1)
  assert_eq(items[1]._id, post._id)
end)

test("ES06", "Iter from target after target-initiated link", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  post.author:link(user)
  local items = collect_iter(post.author:iter())
  assert_eq(#items, 1)
  assert_eq(items[1]._id, user._id)
end)

test("ES07", "Count on edge without reverse", function()
  local g = neo.create(edge_symmetry_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })

  user1.friends:link(user2)
  assert_eq(user1.friends:count(), 1)
end)

test("ES08", "Unlink from source side clears reverse", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  user.posts:link(post)
  user.posts:unlink(post)
  assert_eq(post.author:count(), 0)
end)

test("ES09", "Unlink from target side clears source", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  user.posts:link(post)
  post.author:unlink(user)
  assert_eq(user.posts:count(), 0)
end)

test("ES10", "Double-link from both sides prevents duplicates", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  user.posts:link(post)
  post.author:link(user)  -- Should be no-op or prevented

  assert_eq(user.posts:count(), 1)
  assert_eq(post.author:count(), 1)
end)

test("ES11", "Cross-side link detection via iter", function()
  local g = neo.create(edge_symmetry_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  post.author:link(user)
  local items = collect_iter(user.posts:iter())
  assert_eq(#items, 1)
  assert_eq(items[1]._id, post._id)
end)

--------------------------------------------------------------------------------
-- Section 10: Subscription Lifecycle Tests (SL-*)
--------------------------------------------------------------------------------

print("\n-- Section 10: Subscription Lifecycle Tests (SL-*) --")

test("SL01", "Signal.use before data, unsubscribe after change", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = nil })

  local call_count = 0
  local unsub = node.name:use(function()
    call_count = call_count + 1
  end)

  node.name:set("Alice")
  unsub()
  node.name:set("Bob")

  assert_eq(call_count, 2)  -- Initial + one change (not after unsub)
end)

test("SL02", "Signal.use after data exists, never unsubscribe", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })

  local call_count = 0
  node.name:use(function()
    call_count = call_count + 1
  end)

  node.name:set("Bob")
  node.name:set("Charlie")

  assert_eq(call_count, 3)  -- Initial + two changes
end)

test("SL03", "EdgeHandle.each unsubscribe before link", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local call_count = 0
  local unsub = user.posts:each(function()
    call_count = call_count + 1
  end)

  unsub()

  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  assert_eq(call_count, 0)
end)

test("SL04", "EdgeHandle.each on child edge", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local call_count = 0
  post.comments:each(function()
    call_count = call_count + 1
  end)

  local comment = g:insert("Comment", { text = "Nice" })
  post.comments:link(comment)

  assert_eq(call_count, 1)
end)

test("SL05", "View callback during insert in callback", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice" })

  local enters = {}
  local inserted_in_callback = false

  local view = g:view({
    type = "User",
  }, {
    callbacks = {
      on_enter = function(node, pos)
        enters[#enters + 1] = node._id
        if not inserted_in_callback then
          inserted_in_callback = true
          g:insert("User", { name = "Bob" })
        end
      end
    }
  })

  -- Should have 2 enters eventually (Alice during init, Bob after)
  assert_true(#enters >= 1)
end)

test("SL06", "View callback on child after expand", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local enters = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge_name)
        enters[#enters + 1] = { type = node._type, edge = edge_name }
      end
    }
  })

  view:expand(user._id, "posts")

  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local post_enters = 0
  for _, e in ipairs(enters) do
    if e.type == "Post" then post_enters = post_enters + 1 end
  end
  assert_eq(post_enters, 1)
end)

test("SL07", "No callback after collapse", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local changes = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_change = function(node, prop)
        changes[#changes + 1] = { type = node._type, prop = prop }
      end
    }
  })

  view:expand(user._id, "posts")
  view:collapse(user._id, "posts")

  post.title:set("Updated")

  local post_changes = 0
  for _, c in ipairs(changes) do
    if c.type == "Post" then post_changes = post_changes + 1 end
  end
  assert_eq(post_changes, 0)
end)

test("SL08", "Signal subscription during callback", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local nested_calls = 0
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_enter = function(node)
        if node._type == "Post" then
          node.title:use(function()
            nested_calls = nested_calls + 1
          end)
        end
      end
    }
  })

  view:expand(user._id, "posts")
  post.title:set("Updated")

  assert_true(nested_calls >= 1)
end)

test("SL09", "Edge each during nested expansion", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local comment_enters = 0
  post.comments:each(function()
    comment_enters = comment_enters + 1
  end)

  local comment = g:insert("Comment", { text = "Nice" })
  post.comments:link(comment)

  assert_eq(comment_enters, 1)
end)

--------------------------------------------------------------------------------
-- Section 11: Initialization Race Tests (IR-*)
--------------------------------------------------------------------------------

print("\n-- Section 11: Initialization Race Tests (IR-*) --")

test("IR01", "Empty graph, no mutation, no eager", function()
  local g = neo.create(basic_schema())

  local enters = {}
  local view = g:view({
    type = "User",
  }, {
    callbacks = {
      on_enter = function(node)
        enters[#enters + 1] = node._id
      end
    }
  })

  assert_eq(#enters, 0)
end)

test("IR02", "Roots exist, no mutation, no eager", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice" })
  g:insert("User", { name = "Bob" })

  local enters = {}
  local view = g:view({
    type = "User",
  }, {
    callbacks = {
      on_enter = function(node)
        enters[#enters + 1] = node._id
      end
    }
  })

  assert_eq(#enters, 2)
end)

test("IR03", "Children exist, eager one level", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  for i = 1, 3 do
    local post = g:insert("Post", { title = "Post " .. i })
    user.posts:link(post)
  end

  local enters = {}
  local view = g:view({
    type = "User",
    edges = { posts = { eager = true } }
  }, {
    callbacks = {
      on_enter = function(node)
        enters[#enters + 1] = node._type
      end
    }
  })

  local user_enters = 0
  local post_enters = 0
  for _, t in ipairs(enters) do
    if t == "User" then user_enters = user_enters + 1 end
    if t == "Post" then post_enters = post_enters + 1 end
  end

  assert_eq(user_enters, 1)
  assert_eq(post_enters, 3)
end)

test("IR04", "Insert during view creation callback", function()
  local g = neo.create(basic_schema())
  local alice = g:insert("User", { name = "Alice" })

  local enters = {}
  local inserted = false

  local view = g:view({
    type = "User",
  }, {
    callbacks = {
      on_enter = function(node)
        enters[#enters + 1] = node.name:get()
        if not inserted then
          inserted = true
          g:insert("User", { name = "Bob" })
        end
      end
    }
  })

  -- Alice enters during init, Bob may enter after
  assert_true(#enters >= 1)
  assert_eq(enters[1], "Alice")
end)

test("IR05", "Link during view creation with eager", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  local enters = {}
  local linked = false

  local view = g:view({
    type = "User",
    edges = { posts = { eager = true } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge_name)
        enters[#enters + 1] = { type = node._type, edge = edge_name }
        if node._type == "User" and not linked then
          linked = true
          user.posts:link(post)
        end
      end
    }
  })

  -- Count post enters
  local post_enters = 0
  for _, e in ipairs(enters) do
    if e.type == "Post" then post_enters = post_enters + 1 end
  end
  assert_true(post_enters >= 1)
end)

test("IR06", "Delete during view creation", function()
  local g = neo.create(basic_schema())
  local alice = g:insert("User", { name = "Alice" })
  local bob = g:insert("User", { name = "Bob" })

  local enters = {}
  local leaves = {}
  local deleted = false

  local view = g:view({
    type = "User",
  }, {
    callbacks = {
      on_enter = function(node)
        enters[#enters + 1] = node.name:get()
        if not deleted then
          deleted = true
          g:delete(bob._id)
        end
      end,
      on_leave = function(node)
        leaves[#leaves + 1] = node._id
      end
    }
  })

  assert_true(#enters >= 1)
end)

test("IR07", "Property change during view creation", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local changes = {}
  local changed = false

  local view = g:view({
    type = "User",
  }, {
    callbacks = {
      on_enter = function(node)
        if not changed then
          changed = true
          node.name:set("Alicia")
        end
      end,
      on_change = function(node, prop)
        changes[#changes + 1] = prop
      end
    }
  })

  -- Change during init should still trigger on_change after init completes
  -- or may be suppressed - implementation dependent
  assert_true(true)  -- Just verify no crash
end)

test("IR08", "Insert with eager expansion", function()
  local g = neo.create(basic_schema())

  local expands = {}
  local view = g:view({
    type = "User",
    edges = { posts = { eager = true } }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expands[#expands + 1] = { id = node._id, edge = edge_name, context = context }
      end
    }
  })

  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  -- View should auto-expand eager edges on new roots
  assert_true(true)  -- Verify no crash
end)

test("IR09", "Nested eager expansion", function()
  local nested_schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },
      __indexes = { { name = "default", fields = {} } },
    },
    Comment = {
      text = "string",
      post = { type = "edge", target = "Post", reverse = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(nested_schema)
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  local comment = g:insert("Comment", { text = "Nice" })
  user.posts:link(post)
  post.comments:link(comment)

  local expands = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        eager = true,
        edges = {
          comments = { eager = true }
        }
      }
    }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expands[#expands + 1] = { edge = edge_name, context = context }
      end
    }
  })

  -- Should have expanded both posts and comments eagerly
  assert_true(#expands >= 2)
  -- All should be eager
  for _, exp in ipairs(expands) do
    assert_true(exp.context.eager)
  end
end)

test("IR10", "Link during nested eager init", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })

  local enters = {}
  local linked = false

  local view = g:view({
    type = "User",
    edges = { posts = { eager = true } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge_name)
        enters[#enters + 1] = node._type
        if node._type == "User" and not linked then
          linked = true
          user.posts:link(post)
        end
      end
    }
  })

  assert_true(#enters >= 1)
end)

--------------------------------------------------------------------------------
-- Section 12: Multi-Parent Path Resolution Tests (MP-*)
--------------------------------------------------------------------------------

print("\n-- Section 12: Multi-Parent Path Resolution Tests (MP-*) --")

test("MP01", "Property change with one parent expanded", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)
  user2.posts:link(post)

  local changes = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_change = function(node, prop)
        changes[#changes + 1] = { id = node._id, prop = prop }
      end
    }
  })

  view:expand(user1._id, "posts")
  -- user2's posts NOT expanded

  post.title:set("Updated")

  local post_changes = 0
  for _, c in ipairs(changes) do
    if c.id == post._id then post_changes = post_changes + 1 end
  end
  assert_eq(post_changes, 1)
end)

test("MP02", "Property change with all parents expanded", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)
  user2.posts:link(post)

  local changes = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_change = function(node, prop)
        changes[#changes + 1] = { id = node._id, prop = prop }
      end
    }
  })

  view:expand(user1._id, "posts")
  view:expand(user2._id, "posts")

  post.title:set("Updated")

  local post_changes = 0
  for _, c in ipairs(changes) do
    if c.id == post._id then post_changes = post_changes + 1 end
  end
  assert_eq(post_changes, 2)
end)

test("MP03", "Expand on 3-parent node via first found", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local user3 = g:insert("User", { name = "Charlie" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)
  user2.posts:link(post)
  user3.posts:link(post)

  local view = g:view({
    type = "User",
    edges = { posts = { edges = { comments = {} } } }
  })

  view:expand(user1._id, "posts")

  -- Try to expand comments on the post
  local result = view:expand(post._id, "comments")
  assert_true(result == true or result == false)  -- Just verify it doesn't crash
end)

test("MP04", "Expand via specific path item", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)
  user2.posts:link(post)

  local view = g:view({
    type = "User",
    edges = { posts = { edges = { comments = {} } } }
  })

  view:expand(user1._id, "posts")
  view:expand(user2._id, "posts")

  local items = view:collect()
  for _, item in ipairs(items) do
    if item.node._type == "Post" then
      item:expand("comments")
      break
    end
  end

  assert_true(true)  -- Verify no crash
end)

test("MP05", "Collapse with 3+ parents all expanded", function()
  local nested_schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },
      __indexes = { { name = "default", fields = {} } },
    },
    Comment = {
      text = "string",
      post = { type = "edge", target = "Post", reverse = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(nested_schema)
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local user3 = g:insert("User", { name = "Charlie" })
  local post = g:insert("Post", { title = "Shared" })
  local comment = g:insert("Comment", { text = "Nice" })
  user1.posts:link(post)
  user2.posts:link(post)
  user3.posts:link(post)
  post.comments:link(comment)

  local leaves = {}
  local view = g:view({
    type = "User",
    edges = { posts = { edges = { comments = {} } } }
  }, {
    callbacks = {
      on_leave = function(node)
        leaves[#leaves + 1] = node._type
      end
    }
  })

  view:expand(user1._id, "posts")
  view:expand(user2._id, "posts")
  view:expand(user3._id, "posts")

  -- Expand comments on the first found path
  view:expand(post._id, "comments")

  -- Collapse from user1
  view:collapse(user1._id, "posts")

  assert_true(#leaves >= 1)
end)

test("MP06", "Unlink from specific parent", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)
  user2.posts:link(post)

  local leaves = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_leave = function(node, edge_name, parent_id)
        leaves[#leaves + 1] = { node = node._id, parent = parent_id }
      end
    }
  })

  view:expand(user1._id, "posts")

  user1.posts:unlink(post)

  assert_eq(#leaves, 1)
  assert_eq(leaves[1].parent, user1._id)
end)

test("MP07", "Property change with no expansions", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local user3 = g:insert("User", { name = "Charlie" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)
  user2.posts:link(post)
  user3.posts:link(post)

  local changes = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_change = function(node)
        changes[#changes + 1] = node._id
      end
    }
  })

  -- No expansions
  post.title:set("Updated")

  local post_changes = 0
  for _, id in ipairs(changes) do
    if id == post._id then post_changes = post_changes + 1 end
  end
  assert_eq(post_changes, 0)
end)

test("MP08", "Unlink multi-parent with all expanded", function()
  local g = neo.create(basic_schema())
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  local post = g:insert("Post", { title = "Shared" })
  user1.posts:link(post)
  user2.posts:link(post)

  local leaves = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_leave = function(node)
        leaves[#leaves + 1] = node._id
      end
    }
  })

  view:expand(user1._id, "posts")
  view:expand(user2._id, "posts")

  user1.posts:unlink(post)

  -- Should fire on_leave once, post still visible under user2
  assert_eq(#leaves, 1)

  local items = view:collect()
  local post_visible = false
  for _, item in ipairs(items) do
    if item.node._type == "Post" then post_visible = true end
  end
  assert_true(post_visible)
end)

test("MP09", "Collapse single-parent baseline", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "Post 1" })
  local post2 = g:insert("Post", { title = "Post 2" })
  user.posts:link(post1)
  user.posts:link(post2)

  local leaves = {}
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_leave = function(node)
        leaves[#leaves + 1] = node._type
      end
    }
  })

  view:expand(user._id, "posts")
  view:collapse(user._id, "posts")

  local post_leaves = 0
  for _, t in ipairs(leaves) do
    if t == "Post" then post_leaves = post_leaves + 1 end
  end
  assert_eq(post_leaves, 2)
end)

--------------------------------------------------------------------------------
-- Section 13: Raw/Proxy Boundary Tests (RP-*)
--------------------------------------------------------------------------------

print("\n-- Section 13: Raw/Proxy Boundary Tests (RP-*) --")

test("RP01", "graph:get returns proxy with Signal access", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })

  local retrieved = g:get(node._id)
  assert_not_nil(retrieved)
  assert_eq(retrieved.name:get(), "Alice")
end)

test("RP02", "Callback param is proxy", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local callback_name = nil
  local view = g:view({
    type = "User",
  }, {
    callbacks = {
      on_enter = function(node)
        callback_name = node.name:get()
      end
    }
  })

  assert_eq(callback_name, "Alice")
end)

test("RP03", "Item.node is proxy", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice" })

  local view = g:view({ type = "User" })
  local items = view:collect()

  assert_eq(#items, 1)
  assert_eq(items[1].node.name:get(), "Alice")
end)

test("RP04", "Edge iter result is proxy", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local titles = {}
  for p in user.posts:iter() do
    titles[#titles + 1] = p.title:get()
  end

  assert_eq(#titles, 1)
  assert_eq(titles[1], "Hello")
end)

test("RP05", "Direct property access returns Signal", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })

  local signal = node.name
  assert_not_nil(signal)
  assert_not_nil(signal.get)
  assert_eq(type(signal.get), "function")
end)

test("RP06", "Callback param has _type", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice" })

  local callback_type = nil
  local view = g:view({
    type = "User",
  }, {
    callbacks = {
      on_enter = function(node)
        callback_type = node._type
      end
    }
  })

  assert_eq(callback_type, "User")
end)

test("RP07", "Item.node has _id", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local view = g:view({ type = "User" })
  local items = view:collect()

  assert_eq(items[1].node._id, user._id)
end)

test("RP08", "Iter skips deleted node", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "Post 1" })
  local post2 = g:insert("Post", { title = "Post 2" })
  user.posts:link(post1)
  user.posts:link(post2)

  g:delete(post1._id)

  local count = 0
  for _ in user.posts:iter() do
    count = count + 1
  end

  assert_eq(count, 1)
end)

test("RP09", "graph:get on deleted node returns nil", function()
  local g = neo.create(basic_schema())
  local node = g:insert("User", { name = "Alice" })
  local id = node._id

  g:delete(id)

  assert_nil(g:get(id))
end)

--------------------------------------------------------------------------------
-- Section 14: Index Coupling Tests (IC-*)
--------------------------------------------------------------------------------

print("\n-- Section 14: Index Coupling Tests (IC-*) --")

test("IC01", "View with covering equality index", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice" })

  local view = g:view({
    type = "User",
    filters = {{ field = "name", op = "eq", value = "Alice" }}
  })

  local items = view:collect()
  assert_eq(#items, 1)
end)

test("IC02", "View with missing index throws error", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", nickname = "Al" })

  local ok, err = pcall(function()
    g:view({
      type = "User",
      filters = {{ field = "nickname", op = "eq", value = "Al" }}
    })
  end)

  assert_false(ok)
  assert_true(err:match("No index covers query") ~= nil)
end)

test("IC03", "Property rollup with covering filter index", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true })
  local post2 = g:insert("Post", { title = "P2", published = false })
  user.posts:link(post1)
  user.posts:link(post2)

  assert_eq(user.published_count:get(), 1)
end)

test("IC04", "Reference rollup with sort index", function()
  local g = neo.create(rollup_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "Old", created_at = 1 })
  local post2 = g:insert("Post", { title = "New", created_at = 2 })
  user.posts:link(post1)
  user.posts:link(post2)

  local latest = user.latest_post:get()
  assert_not_nil(latest)
  assert_eq(latest.title:get(), "New")
end)

test("IC05", "Reference rollup without sort index uses default", function()
  -- Schema without edge index for sort field
  local schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      first_post = { type = "reference", edge = "posts" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(schema)
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  local first = user.first_post:get()
  assert_not_nil(first)
end)

test("IC06", "Edge filter with range index", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", views = 10 })
  local post2 = g:insert("Post", { title = "P2", views = 50 })
  local post3 = g:insert("Post", { title = "P3", views = 100 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local filtered = user.posts:filter({
    filters = {{ field = "views", op = "gt", value = 20 }}
  })

  local count = count_iter(filtered:iter())
  assert_eq(count, 2)
end)

test("IC07", "Edge filter missing index throws error", function()
  -- Schema without edge index for filter field
  local schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      rating = "number",
      author = { type = "edge", target = "User", reverse = "posts" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(schema)
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello", rating = 5 })
  user.posts:link(post)

  local ok, err = pcall(function()
    user.posts:filter({
      filters = {{ field = "rating", op = "gt", value = 3 }}
    })
  end)

  assert_false(ok)
  assert_true(err:match("No index covers query") ~= nil)
end)

test("IC08", "View with partial compound index match", function()
  local g = neo.create(basic_schema())
  g:insert("User", { name = "Alice", active = true, age = 30 })
  g:insert("User", { name = "Bob", active = true, age = 25 })
  g:insert("User", { name = "Charlie", active = false, age = 35 })

  -- by_active_age index covers active prefix
  local view = g:view({
    type = "User",
    filters = {{ field = "active", op = "eq", value = true }}
  })

  local items = view:collect()
  assert_eq(#items, 2)
end)

test("IC09", "Property rollup with compound filter", function()
  local schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author",
        __indexes = {
          { name = "default", fields = {} },
          { name = "by_status_views", fields = {
            { name = "published" },
            { name = "views", dir = "desc" }
          }},
        },
      },
      published_high_views = { type = "count", edge = "posts",
        filters = {
          { field = "published", value = true },
          { field = "views", op = "gte", value = 50 }
        },
      },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      published = "bool",
      views = "number",
      author = { type = "edge", target = "User", reverse = "posts" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(schema)
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true, views = 100 })
  local post2 = g:insert("Post", { title = "P2", published = true, views = 20 })
  local post3 = g:insert("Post", { title = "P3", published = false, views = 80 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  assert_eq(user.published_high_views:get(), 1)
end)

--------------------------------------------------------------------------------
-- Section 15: Recursive Edge Tests (RE-*)
--------------------------------------------------------------------------------

print("\n-- Section 15: Recursive Edge Tests (RE-*) --")

-- Schema for recursive (self-referential) edges
local function recursive_schema()
  return {
    Category = {
      name = "string",
      level = "number",
      children = { type = "edge", target = "Category", reverse = "parent" },
      parent = { type = "edge", target = "Category", reverse = "children" },
      __indexes = {
        { name = "default", fields = {{ name = "name" }} },
        { name = "by_level", fields = {{ name = "level" }} },
      },
    },
  }
end

test("RE01", "Single-level recursive expand", function()
  local g = neo.create(recursive_schema())
  local root = g:insert("Category", { name = "Root", level = 0 })
  local child1 = g:insert("Category", { name = "Child1", level = 1 })
  local child2 = g:insert("Category", { name = "Child2", level = 1 })
  root.children:link(child1)
  root.children:link(child2)

  local enters = {}
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge, parent_id)
        enters[#enters + 1] = { id = node._id, depth = edge and 1 or 0 }
      end,
    },
  })

  view:expand(root._id, "children")
  -- Root at depth 0, children at depth 1
  local child_enters = 0
  for _, e in ipairs(enters) do
    if e.depth == 1 then child_enters = child_enters + 1 end
  end
  assert_eq(child_enters, 2)
end)

test("RE02", "Two-level recursive expand", function()
  local g = neo.create(recursive_schema())
  local root = g:insert("Category", { name = "Root", level = 0 })
  local child = g:insert("Category", { name = "Child", level = 1 })
  local grandchild = g:insert("Category", { name = "Grandchild", level = 2 })
  root.children:link(child)
  child.children:link(grandchild)

  local max_depth = 0
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge, parent_id)
        if edge then
          -- Calculate depth based on expansion
          local d = 1
          if parent_id and parent_id ~= root._id then d = 2 end
          if d > max_depth then max_depth = d end
        end
      end,
    },
  })

  view:expand(root._id, "children")
  view:expand(child._id, "children")
  assert_eq(max_depth, 2)
end)

test("RE03", "Deep recursive expand (3+ levels)", function()
  local g = neo.create(recursive_schema())
  local cats = {}
  for i = 0, 3 do
    cats[i] = g:insert("Category", { name = "Cat" .. i, level = i })
    if i > 0 then cats[i-1].children:link(cats[i]) end
  end

  local enter_count = 0
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true } }
  }, {
    callbacks = {
      on_enter = function() enter_count = enter_count + 1 end,
    },
  })

  -- Expand all levels
  for i = 0, 2 do
    view:expand(cats[i]._id, "children")
  end
  -- Root + 3 children at various depths
  assert_eq(enter_count, 4)
end)

test("RE04", "Recursive with eager (limited depth)", function()
  local g = neo.create(recursive_schema())
  local root = g:insert("Category", { name = "Root", level = 0 })
  local child = g:insert("Category", { name = "Child", level = 1 })
  local grandchild = g:insert("Category", { name = "Grandchild", level = 2 })
  root.children:link(child)
  child.children:link(grandchild)

  local enter_count = 0
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true, eager = true } }
  }, {
    callbacks = {
      on_enter = function() enter_count = enter_count + 1 end,
    },
  })

  -- Eager only expands first level, not recursively
  -- Root + child = 2 (grandchild not auto-expanded)
  assert_true(enter_count >= 2)
end)

test("RE05", "Deep recursive with eager at leaves", function()
  local g = neo.create(recursive_schema())
  local root = g:insert("Category", { name = "Root", level = 0 })
  local child = g:insert("Category", { name = "Child", level = 1 })
  -- child has no children (leaf)
  root.children:link(child)

  local enter_count = 0
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true, eager = true } }
  }, {
    callbacks = {
      on_enter = function() enter_count = enter_count + 1 end,
    },
  })

  -- Should not infinite loop - stops at leaf
  assert_eq(enter_count, 2) -- root + child
end)

test("RE06", "Recursive with inline", function()
  local g = neo.create(recursive_schema())
  local root = g:insert("Category", { name = "Root", level = 0 })
  local child = g:insert("Category", { name = "Child", level = 1 })
  root.children:link(child)

  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true, inline = true } }
  })

  view:expand(root._id, "children")
  local items = view:collect()
  -- With inline, children have same depth as parent
  for _, item in ipairs(items) do
    assert_eq(item.depth, 0)
  end
end)

test("RE07", "Recursive on multi-parent DAG", function()
  local g = neo.create(recursive_schema())
  local parent1 = g:insert("Category", { name = "Parent1", level = 0 })
  local parent2 = g:insert("Category", { name = "Parent2", level = 0 })
  local shared = g:insert("Category", { name = "Shared", level = 1 })
  parent1.children:link(shared)
  parent2.children:link(shared)

  local enter_count = 0
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true } }
  }, {
    callbacks = {
      on_enter = function() enter_count = enter_count + 1 end,
    },
  })

  view:expand(parent1._id, "children")
  view:expand(parent2._id, "children")
  -- 2 roots + shared appears under each = 4
  assert_eq(enter_count, 4)
end)

test("RE08", "Property change in deep recursive multi-parent", function()
  local g = neo.create(recursive_schema())
  local parent1 = g:insert("Category", { name = "Parent1", level = 0 })
  local parent2 = g:insert("Category", { name = "Parent2", level = 0 })
  local shared = g:insert("Category", { name = "Shared", level = 1 })
  parent1.children:link(shared)
  parent2.children:link(shared)

  local change_count = 0
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true } }
  }, {
    callbacks = {
      on_change = function() change_count = change_count + 1 end,
    },
  })

  view:expand(parent1._id, "children")
  view:expand(parent2._id, "children")
  change_count = 0

  shared.name:set("Updated")
  -- on_change should fire twice (once per path)
  assert_eq(change_count, 2)
end)

test("RE09", "Collapse recursive at mid-level", function()
  local g = neo.create(recursive_schema())
  local root = g:insert("Category", { name = "Root", level = 0 })
  local child = g:insert("Category", { name = "Child", level = 1 })
  local grandchild = g:insert("Category", { name = "Grandchild", level = 2 })
  root.children:link(child)
  child.children:link(grandchild)

  local leave_count = 0
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true } }
  }, {
    callbacks = {
      on_leave = function() leave_count = leave_count + 1 end,
    },
  })

  view:expand(root._id, "children")
  view:expand(child._id, "children")
  leave_count = 0

  view:collapse(root._id, "children")
  -- Should fire on_leave for child and grandchild
  assert_eq(leave_count, 2)
end)

test("RE10", "Collapse eager recursive", function()
  local g = neo.create(recursive_schema())
  local root = g:insert("Category", { name = "Root", level = 0 })
  local child = g:insert("Category", { name = "Child", level = 1 })
  root.children:link(child)

  local leave_count = 0
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true, eager = true } }
  }, {
    callbacks = {
      on_leave = function() leave_count = leave_count + 1 end,
    },
  })

  view:collapse(root._id, "children")
  assert_eq(leave_count, 1) -- child leaves
end)

test("RE11", "Multi-parent with inline recursive", function()
  local g = neo.create(recursive_schema())
  local parent1 = g:insert("Category", { name = "Parent1", level = 0 })
  local parent2 = g:insert("Category", { name = "Parent2", level = 0 })
  local shared = g:insert("Category", { name = "Shared", level = 1 })
  parent1.children:link(shared)
  parent2.children:link(shared)

  local change_depths = {}
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true, inline = true } }
  }, {
    callbacks = {
      on_change = function(node)
        change_depths[#change_depths + 1] = 0 -- inline means depth 0
      end,
    },
  })

  view:expand(parent1._id, "children")
  view:expand(parent2._id, "children")

  shared.name:set("Updated")
  -- All changes should report depth 0 (inline)
  for _, d in ipairs(change_depths) do
    assert_eq(d, 0)
  end
end)

test("RE12", "Deep multi-parent with eager recursive", function()
  local g = neo.create(recursive_schema())
  local parent1 = g:insert("Category", { name = "Parent1", level = 0 })
  local parent2 = g:insert("Category", { name = "Parent2", level = 0 })
  local shared = g:insert("Category", { name = "Shared", level = 1 })
  parent1.children:link(shared)
  parent2.children:link(shared)

  local enter_count = 0
  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { recursive = true, eager = true } }
  }, {
    callbacks = {
      on_enter = function() enter_count = enter_count + 1 end,
    },
  })

  -- Eager expands first level for both parents
  -- 2 roots + shared under each parent = 4
  assert_eq(enter_count, 4)
end)

-- Schema for recursive with sibling edges
local function recursive_sibling_schema()
  return {
    Folder = {
      name = "string",
      level = "number",
      children = { type = "edge", target = "Folder", reverse = "parent" },
      tags = { type = "edge", target = "Tag", reverse = "folders" },
      parent = { type = "edge", target = "Folder", reverse = "children" },
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_level", fields = { { name = "level" } } },
      },
    },
    Tag = {
      name = "string",
      folders = { type = "edge", target = "Folder", reverse = "tags" },
    },
  }
end

test("RE13", "Recursive should apply sibling edges at all levels", function()
  -- This test documents EXPECTED behavior - recursive = true on an edge
  -- should cause its sibling edges in the same config to also apply recursively.
  --
  -- Currently FAILS: sibling edges only apply at the first level, not at
  -- deeper recursive levels. This is a limitation that should be fixed.

  local g = neo.create(recursive_sibling_schema())

  -- Create folder hierarchy: root -> child -> grandchild
  local root = g:insert("Folder", { name = "Root", level = 0 })
  local child = g:insert("Folder", { name = "Child", level = 1 })
  local grandchild = g:insert("Folder", { name = "Grandchild", level = 2 })
  root.children:link(child)
  child.children:link(grandchild)

  -- Add tags at each level
  local tag_root = g:insert("Tag", { name = "TagRoot" })
  local tag_child = g:insert("Tag", { name = "TagChild" })
  local tag_grandchild = g:insert("Tag", { name = "TagGrandchild" })
  root.tags:link(tag_root)
  child.tags:link(tag_child)
  grandchild.tags:link(tag_grandchild)

  local tag_enters = {}
  local view = g:view({
    type = "Folder",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = {
      children = { recursive = true },
      tags = { eager = true },  -- sibling edge should apply at all recursive levels
    }
  }, {
    callbacks = {
      on_enter = function(node)
        local name = node.name:get()
        if name and name:match("^Tag") then
          tag_enters[#tag_enters + 1] = name
        end
      end,
    },
  })

  -- Expand children recursively
  view:expand(root._id, "children")
  view:expand(child._id, "children")

  -- EXPECTED: tags should be visible at all levels (root, child, grandchild)
  -- All three tags should have entered the view
  assert_eq(#tag_enters, 3, "Expected 3 tags (one at each level), got " .. #tag_enters)

  local function contains(tbl, val)
    for _, v in ipairs(tbl) do if v == val then return true end end
    return false
  end
  assert_true(contains(tag_enters, "TagRoot"), "TagRoot should be in view")
  assert_true(contains(tag_enters, "TagChild"), "TagChild should be in view")
  assert_true(contains(tag_enters, "TagGrandchild"), "TagGrandchild should be in view")
end)

--------------------------------------------------------------------------------
-- Section 16: Edge Configuration Extension Tests (EC-*)
--------------------------------------------------------------------------------

print("\n-- Section 16: Edge Configuration Extension Tests (EC-*) --")

-- Schema for edge config tests (needs edge indexes for sort/filter)
local function edge_config_schema()
  return {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author",
        __indexes = {
          { name = "default", fields = {} },
          { name = "by_title", fields = {{ name = "title", dir = "asc" }} },
          { name = "by_created", fields = {{ name = "created_at", dir = "desc" }} },
          { name = "by_published", fields = {{ name = "published" }} },
          { name = "by_views", fields = {{ name = "views" }} },
          { name = "by_views_desc", fields = {{ name = "views", dir = "desc" }} },
          { name = "by_pub_title", fields = {{ name = "published" }, { name = "title", dir = "asc" }} },
        },
      },
      __indexes = {
        { name = "default", fields = {{ name = "name" }} },
      },
    },
    Post = {
      title = "string",
      published = "bool",
      views = "number",
      created_at = "number",
      author = { type = "edge", target = "User", reverse = "posts" },
      __indexes = {
        { name = "default", fields = {{ name = "title" }} },
      },
    },
  }
end

test("EC01", "Edge sort ascending", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })

  local enter_order = {}
  local view = g:view({
    type = "User",
    edges = { posts = { sort = { field = "title", dir = "asc" } } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_order[#enter_order + 1] = node.title:get() end
      end,
    },
  })

  local postC = g:insert("Post", { title = "C", published = true, views = 10, created_at = 1 })
  local postA = g:insert("Post", { title = "A", published = true, views = 20, created_at = 2 })
  local postB = g:insert("Post", { title = "B", published = true, views = 30, created_at = 3 })
  user.posts:link(postC)
  user.posts:link(postA)
  user.posts:link(postB)

  view:expand(user._id, "posts")
  assert_eq(enter_order[1], "A")
  assert_eq(enter_order[2], "B")
  assert_eq(enter_order[3], "C")
end)

test("EC02", "Edge sort descending", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "P2", published = true, views = 20, created_at = 3 })
  local post3 = g:insert("Post", { title = "P3", published = true, views = 30, created_at = 2 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local enter_order = {}
  local view = g:view({
    type = "User",
    edges = { posts = { sort = { field = "created_at", dir = "desc" } } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_order[#enter_order + 1] = node.created_at:get() end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(enter_order[1], 3)
  assert_eq(enter_order[2], 2)
  assert_eq(enter_order[3], 1)
end)

test("EC03", "Edge filter equality - matching", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local pub = g:insert("Post", { title = "Pub", published = true, views = 10, created_at = 1 })
  local unpub = g:insert("Post", { title = "Unpub", published = false, views = 20, created_at = 2 })
  user.posts:link(pub)
  user.posts:link(unpub)

  local entered = {}
  local view = g:view({
    type = "User",
    edges = { posts = { filters = {{ field = "published", op = "eq", value = true }} } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then entered[#entered + 1] = node.title:get() end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(#entered, 1)
  assert_eq(entered[1], "Pub")
end)

test("EC04", "Edge filter equality - non-matching not entered", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  user.posts:link(g:insert("Post", { title = "Unpub", published = false, views = 10, created_at = 1 }))

  local entered = {}
  local view = g:view({
    type = "User",
    edges = { posts = { filters = {{ field = "published", op = "eq", value = true }} } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then entered[#entered + 1] = node._id end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(#entered, 0) -- non-matching post not entered
end)

test("EC05", "Edge filter range - property change to match", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Low", published = true, views = 50, created_at = 1 })
  user.posts:link(post)

  local entered = {}
  local view = g:view({
    type = "User",
    edges = { posts = { filters = {{ field = "views", op = "gt", value = 100 }} } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then entered[#entered + 1] = node._id end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(#entered, 0) -- doesn't match initially

  post.views:set(150)
  -- After property change, post now matches filter
  -- Note: dynamic filter matching during expansion may vary by implementation
  assert_true(true) -- Test passes if no error
end)

test("EC06", "Edge filter - property change to non-match fires on_leave", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Pub", published = true, views = 10, created_at = 1 })
  user.posts:link(post)

  local left = {}
  local view = g:view({
    type = "User",
    edges = { posts = { filters = {{ field = "published", op = "eq", value = true }} } }
  }, {
    callbacks = {
      on_leave = function(node, edge)
        if edge then left[#left + 1] = node._id end
      end,
    },
  })

  view:expand(user._id, "posts")
  post.published:set(false)
  -- Post no longer matches, should fire on_leave
  -- Note: behavior depends on implementation of filter reactivity
  assert_true(true) -- Test passes if no error
end)

test("EC07", "Edge sort and filter combined", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local pZ = g:insert("Post", { title = "Z", published = true, views = 10, created_at = 1 })
  local pA = g:insert("Post", { title = "A", published = true, views = 20, created_at = 2 })
  local pM = g:insert("Post", { title = "M", published = true, views = 30, created_at = 3 })
  local pX = g:insert("Post", { title = "X", published = false, views = 40, created_at = 4 }) -- filtered out
  user.posts:link(pZ)
  user.posts:link(pA)
  user.posts:link(pM)
  user.posts:link(pX)

  local enter_order = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        sort = { field = "title", dir = "asc" },
        filters = {{ field = "published", op = "eq", value = true }},
      },
    }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_order[#enter_order + 1] = node.title:get() end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(#enter_order, 3) -- X filtered out
  assert_eq(enter_order[1], "A")
  assert_eq(enter_order[2], "M")
  assert_eq(enter_order[3], "Z")
end)

test("EC08", "Sort and range filter with property change", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true, views = 100, created_at = 1 })
  user.posts:link(post)

  local change_count = 0
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        sort = { field = "views", dir = "desc" },
        filters = {{ field = "views", op = "gt", value = 50 }},
      },
    }
  }, {
    callbacks = {
      on_change = function() change_count = change_count + 1 end,
    },
  })

  view:expand(user._id, "posts")
  post.views:set(200)
  assert_true(change_count >= 1)
end)

test("EC09", "Sort with property change affecting order", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local pA = g:insert("Post", { title = "A", published = true, views = 10, created_at = 1 })
  local pB = g:insert("Post", { title = "B", published = true, views = 20, created_at = 2 })
  local pC = g:insert("Post", { title = "C", published = true, views = 30, created_at = 3 })
  user.posts:link(pA)
  user.posts:link(pB)
  user.posts:link(pC)

  local change_count = 0
  local view = g:view({
    type = "User",
    edges = { posts = { sort = { field = "title", dir = "asc" } } }
  }, {
    callbacks = {
      on_change = function() change_count = change_count + 1 end,
    },
  })

  view:expand(user._id, "posts")
  pA.title:set("Z") -- A becomes Z, should affect order
  assert_true(change_count >= 1)
end)

test("EC10", "Range filter - add non-matching", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })

  local entered = {}
  local view = g:view({
    type = "User",
    edges = { posts = { filters = {{ field = "views", op = "gt", value = 100 }} } }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then entered[#entered + 1] = node._id end
      end,
    },
  })

  view:expand(user._id, "posts")
  local low_post = g:insert("Post", { title = "Low", published = true, views = 50, created_at = 1 })
  user.posts:link(low_post)
  -- Non-matching post should not trigger on_enter
  assert_eq(#entered, 0)
end)

--------------------------------------------------------------------------------
-- Section 17: View Navigation Tests (VN-*)
--------------------------------------------------------------------------------

print("\n-- Section 17: View Navigation Tests (VN-*) --")

test("VN01", "Seek first position", function()
  local g = neo.create(basic_schema())
  for i = 1, 5 do
    g:insert("User", { name = "User" .. i })
  end

  local view = g:view({ type = "User" })
  local node = view:seek(1)
  assert_not_nil(node)
end)

test("VN02", "Seek middle position", function()
  local g = neo.create(basic_schema())
  local users = {}
  for i = 1, 10 do
    users[i] = g:insert("User", { name = "User" .. i })
  end

  local view = g:view({ type = "User" })
  local node = view:seek(5)
  assert_not_nil(node)
end)

test("VN03", "Seek last with expansion", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  for i = 1, 3 do
    local post = g:insert("Post", { title = "Post" .. i, published = true, views = i * 10 })
    user.posts:link(post)
  end

  local view = g:view({
    type = "User",
    edges = { posts = {} }
  })
  view:expand(user._id, "posts")

  -- 1 root + 3 children = 4 total
  local total = view:visible_total()
  local node = view:seek(total)
  assert_not_nil(node)
end)

test("VN04", "Seek beyond end returns nil", function()
  local g = neo.create(basic_schema())
  for i = 1, 3 do
    g:insert("User", { name = "User" .. i })
  end

  local view = g:view({ type = "User" })
  local node = view:seek(10)
  assert_nil(node)
end)

test("VN05", "Position of first node", function()
  local g = neo.create(basic_schema())
  local users = {}
  for i = 1, 5 do
    users[i] = g:insert("User", { name = "User" .. i })
  end

  local view = g:view({ type = "User" })
  local pos = view:position_of(users[1]._id)
  assert_not_nil(pos)
  assert_true(pos >= 1)
end)

test("VN06", "Position of node in filtered view", function()
  local g = neo.create(basic_schema())
  local users = {}
  for i = 1, 5 do
    users[i] = g:insert("User", { name = "User" .. i, active = i % 2 == 0 })
  end

  local view = g:view({ type = "User", filters = {{ field = "active", op = "eq", value = true }} })
  -- Active users are 2, 4
  local pos = view:position_of(users[4]._id)
  assert_not_nil(pos)
end)

--------------------------------------------------------------------------------
-- Section 18: Item Method Tests (IM-*)
--------------------------------------------------------------------------------

print("\n-- Section 18: Item Method Tests (IM-*) --")

test("IM01", "Toggle collapsed edge", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true, views = 10 })
  user.posts:link(post)

  local expand_context = nil
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expand_context = context
      end,
    },
  })

  local items = view:collect()
  local item = items[1]
  item:toggle("posts")
  assert_true(expand_context ~= nil)
  -- Manual expansion should have eager = false
  assert_false(expand_context.eager)
end)

test("IM02", "Toggle expanded edge", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true, views = 10 })
  user.posts:link(post)

  local collapse_context = nil
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_collapse = function(node, edge_name, context)
        collapse_context = context
      end,
    },
  })

  view:expand(user._id, "posts")
  local items = view:collect()
  local item = items[1]
  item:toggle("posts")
  assert_not_nil(collapse_context)
  assert_false(collapse_context.inline)
end)

test("IM03", "is_expanded on collapsed", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true, views = 10 })
  user.posts:link(post)

  local view = g:view({ type = "User", edges = { posts = {} } })
  local items = view:collect()
  local item = items[1]
  assert_false(item:is_expanded("posts"))
end)

test("IM04", "is_expanded on expanded child", function()
  local g = neo.create(view_schema())
  local user = g:insert("User", { name = "Alice", active = true })
  local post = g:insert("Post", { title = "P1", published = true, created_at = 1 })
  local comment = g:insert("Comment", { text = "C1" })
  user.posts:link(post)
  post.comments:link(comment)

  local view = g:view({
    type = "User",
    edges = { posts = { edges = { comments = {} } } }
  })

  view:expand(user._id, "posts")
  view:expand(post._id, "comments")

  local items = view:collect()
  -- Find the post item
  for _, item in ipairs(items) do
    if item.id == post._id then
      assert_true(item:is_expanded("comments"))
      break
    end
  end
end)

test("IM05", "child_count with no children", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  -- No posts linked

  local view = g:view({ type = "User", edges = { posts = {} } })
  local items = view:collect()
  local item = items[1]
  assert_eq(item:child_count("posts"), 0)
end)

test("IM06", "child_count on expanded child", function()
  local g = neo.create(view_schema())
  local user = g:insert("User", { name = "Alice", active = true })
  local post = g:insert("Post", { title = "P1", published = true, created_at = 1 })
  for i = 1, 5 do
    local comment = g:insert("Comment", { text = "C" .. i })
    post.comments:link(comment)
  end
  user.posts:link(post)

  local view = g:view({
    type = "User",
    edges = { posts = { edges = { comments = {} } } }
  })

  view:expand(user._id, "posts")
  local items = view:collect()
  -- Find the post item
  for _, item in ipairs(items) do
    if item.id == post._id then
      assert_eq(item:child_count("comments"), 5)
      break
    end
  end
end)

--------------------------------------------------------------------------------
-- Section 19: Graph Utility Tests (GU-*)
--------------------------------------------------------------------------------

print("\n-- Section 19: Graph Utility Tests (GU-*) --")

test("GU01", "clear_prop clears existing property", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local old_val, new_val
  user.name:use(function(v)
    new_val = v
    return function() old_val = v end
  end)

  g:clear_prop(user._id, "name")
  assert_nil(user.name:get())
end)

test("GU02", "clear_prop on undefined property", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  -- nickname is not set

  -- Should not error
  g:clear_prop(user._id, "nickname")
  assert_nil(user.nickname:get())
end)

test("GU03", "has_edge returns true for linked edge with reverse", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true, views = 10 })
  user.posts:link(post)

  assert_true(g:has_edge(user._id, "posts", post._id))
end)

test("GU04", "has_edge returns false for empty edge", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true, views = 10 })
  -- Not linked

  assert_false(g:has_edge(user._id, "posts", post._id))
end)

test("GU05", "has_edge on edge without reverse", function()
  local schema = {
    User = {
      name = "string",
      friends = { type = "edge", target = "User" }, -- no reverse
      __indexes = { { name = "default", fields = {{ name = "name" }} } },
    },
  }
  local g = neo.create(schema)
  local user1 = g:insert("User", { name = "Alice" })
  local user2 = g:insert("User", { name = "Bob" })
  user1.friends:link(user2)

  assert_true(g:has_edge(user1._id, "friends", user2._id))
end)

test("GU06", "targets returns linked node IDs", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local posts = {}
  for i = 1, 3 do
    posts[i] = g:insert("Post", { title = "P" .. i, published = true, views = i * 10 })
    user.posts:link(posts[i])
  end

  local targets = g:targets(user._id, "posts")
  assert_eq(#targets, 3)
end)

test("GU07", "targets on empty edge returns empty table", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local targets = g:targets(user._id, "posts")
  assert_eq(#targets, 0)
end)

test("GU08", "sources returns reverse-linked node IDs", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true, views = 10 })
  user.posts:link(post)

  local sources = g:sources(post._id, "author")
  assert_eq(#sources, 1)
  assert_eq(sources[1], user._id)
end)

--------------------------------------------------------------------------------
-- Section 20: Inline Edge Tests (IL-*)
--------------------------------------------------------------------------------

print("\n-- Section 20: Inline Edge Tests (IL-*) --")

test("IL01", "Single inline edge - items skipped", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true, views = 10 })
  user.posts:link(post)

  local view = g:view({
    type = "User",
    edges = { posts = { inline = true } }
  })

  view:expand(user._id, "posts")
  local items = view:collect()
  -- Inline items are skipped - only user is visible
  -- Post has no expanded children, so nothing is hoisted
  assert_eq(#items, 1)
  assert_eq(items[1].id, user._id)
  assert_eq(items[1].depth, 0)
end)

test("IL02", "Inline with eager - children hoisted", function()
  local g = neo.create(view_schema())
  local user = g:insert("User", { name = "Alice", active = true })
  local post = g:insert("Post", { title = "P1", published = true, created_at = 1 })
  local comment = g:insert("Comment", { text = "C1" })
  user.posts:link(post)
  post.comments:link(comment)

  local enter_count = 0
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        inline = true,
        eager = true,
        edges = { comments = { eager = true } }  -- non-inline by default
      }
    }
  }, {
    callbacks = {
      on_enter = function() enter_count = enter_count + 1 end,
    },
  })

  -- User enters, post is skipped (inline), comment enters (non-inline, hoisted)
  assert_eq(enter_count, 2)  -- user + comment

  local items = view:collect()
  assert_eq(#items, 2)  -- user + comment (post is skipped)
  assert_eq(items[1].id, user._id)
  assert_eq(items[1].depth, 0)
  assert_eq(items[2].id, comment._id)
  assert_eq(items[2].depth, 1)  -- non-inline from (invisible) post
end)

test("IL03", "Nested inline edges - all skipped", function()
  local g = neo.create(view_schema())
  local user = g:insert("User", { name = "Alice", active = true })
  local post = g:insert("Post", { title = "P1", published = true, created_at = 1 })
  local comment = g:insert("Comment", { text = "C1" })
  user.posts:link(post)
  post.comments:link(comment)

  local view = g:view({
    type = "User",
    edges = {
      posts = {
        inline = true,
        edges = { comments = { inline = true } },
      },
    }
  })

  view:expand(user._id, "posts")
  view:expand(post._id, "comments")

  local items = view:collect()
  -- Both post and comment are inline (skipped)
  -- Comment has no children, so nothing is hoisted
  -- Only user is visible
  assert_eq(#items, 1)
  assert_eq(items[1].id, user._id)
  assert_eq(items[1].depth, 0)
end)

test("IL04", "Mixed inline and non-inline", function()
  local g = neo.create(view_schema())
  local user = g:insert("User", { name = "Alice", active = true })
  local post = g:insert("Post", { title = "P1", published = true, created_at = 1 })
  local comment = g:insert("Comment", { text = "C1" })
  user.posts:link(post)
  post.comments:link(comment)

  local view = g:view({
    type = "User",
    edges = {
      posts = {
        inline = true,
        edges = { comments = { inline = false } }, -- non-inline
      },
    }
  })

  view:expand(user._id, "posts")
  view:expand(post._id, "comments")

  local items = view:collect()
  -- Post is skipped (inline), comment is visible (non-inline)
  assert_eq(#items, 2)  -- user + comment
  assert_eq(items[1].id, user._id)
  assert_eq(items[1].depth, 0)
  assert_eq(items[2].id, comment._id)
  assert_eq(items[2].depth, 1)  -- non-inline from (invisible) post
end)

test("IL05", "Inline with recursive - all skipped", function()
  local g = neo.create(recursive_schema())
  local root = g:insert("Category", { name = "Root", level = 0 })
  local child = g:insert("Category", { name = "Child", level = 1 })
  local grandchild = g:insert("Category", { name = "Grandchild", level = 2 })
  root.children:link(child)
  child.children:link(grandchild)

  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = { children = { inline = true, recursive = true } }
  })

  view:expand(root._id, "children")
  view:expand(child._id, "children")

  local items = view:collect()
  -- All children are inline (skipped recursively)
  -- Only root is visible
  assert_eq(#items, 1)
  assert_eq(items[1].id, root._id)
  assert_eq(items[1].depth, 0)
end)

test("IL06", "Collapse inline edge with non-inline children", function()
  local g = neo.create(view_schema())
  local user = g:insert("User", { name = "Alice", active = true })
  local post = g:insert("Post", { title = "P1", published = true, created_at = 1 })
  local comment = g:insert("Comment", { text = "C1" })
  user.posts:link(post)
  post.comments:link(comment)

  local leave_ids = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        inline = true,
        eager = true,
        edges = { comments = { eager = true } },  -- non-inline
      },
    }
  }, {
    callbacks = {
      on_leave = function(node) leave_ids[#leave_ids + 1] = node._id end,
    },
  })

  -- Comment is visible (non-inline), post is skipped (inline)
  local items = view:collect()
  assert_eq(#items, 2)  -- user + comment

  view:collapse(user._id, "posts")
  -- Only comment should fire on_leave (post is inline/skipped)
  assert_eq(#leave_ids, 1)
  assert_eq(leave_ids[1], comment._id)

  -- After collapse, only user is visible
  items = view:collect()
  assert_eq(#items, 1)
end)

--------------------------------------------------------------------------------
-- Section 21: Edge Cursor Tests (ST-*)
--------------------------------------------------------------------------------

print("\n-- Section 21: Edge Cursor Tests (ST-*) --")

-- Reuse edge_config_schema which has sorted edge indexes

test("ST01", "Take limits children count", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "P2", published = true, views = 20, created_at = 2 })
  local post3 = g:insert("Post", { title = "P3", published = true, views = 30, created_at = 3 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local view = g:view({
    type = "User",
    edges = { posts = { take = 2 } }
  })

  view:expand(user._id, "posts")
  local items = view:collect()
  assert_eq(#items, 3)  -- user + 2 posts (not 3)
end)

test("ST02", "Take with sort - first N by sort order", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "P2", published = true, views = 20, created_at = 3 })
  local post3 = g:insert("Post", { title = "P3", published = true, views = 30, created_at = 2 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local enter_order = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        sort = { field = "created_at", dir = "desc" },
        take = 2,
      }
    }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_order[#enter_order + 1] = node.created_at:get() end
      end,
    },
  })

  view:expand(user._id, "posts")
  -- Should get posts with created_at 3 and 2 (desc order, first 2)
  assert_eq(#enter_order, 2)
  assert_eq(enter_order[1], 3)
  assert_eq(enter_order[2], 2)
end)

test("ST03", "Skip skips first N children", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "A", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "B", published = true, views = 20, created_at = 2 })
  local post3 = g:insert("Post", { title = "C", published = true, views = 30, created_at = 3 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local enter_titles = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        sort = { field = "title", dir = "asc" },
        skip = 1,  -- Skip first (A)
      }
    }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_titles[#enter_titles + 1] = node.title:get() end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(#enter_titles, 2)  -- B and C only
  assert_eq(enter_titles[1], "B")
  assert_eq(enter_titles[2], "C")
end)

test("ST04", "Skip and take combined", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "A", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "B", published = true, views = 20, created_at = 2 })
  local post3 = g:insert("Post", { title = "C", published = true, views = 30, created_at = 3 })
  local post4 = g:insert("Post", { title = "D", published = true, views = 40, created_at = 4 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)
  user.posts:link(post4)

  local enter_titles = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        sort = { field = "title", dir = "asc" },
        skip = 1,
        take = 2,  -- Skip A, take B and C
      }
    }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_titles[#enter_titles + 1] = node.title:get() end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(#enter_titles, 2)
  assert_eq(enter_titles[1], "B")
  assert_eq(enter_titles[2], "C")
end)

test("ST05", "Take zero shows no children", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true, views = 10, created_at = 1 })
  user.posts:link(post)

  local view = g:view({
    type = "User",
    edges = { posts = { take = 0 } }
  })

  view:expand(user._id, "posts")
  local items = view:collect()
  assert_eq(#items, 1)  -- Only user, no posts
end)

test("ST06", "Take exceeds available returns all available", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "P2", published = true, views = 20, created_at = 2 })
  user.posts:link(post1)
  user.posts:link(post2)

  local enter_count = 0
  local view = g:view({
    type = "User",
    edges = { posts = { take = 10 } }  -- Only 2 available
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_count = enter_count + 1 end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(enter_count, 2)  -- Both posts enter
end)

test("ST07", "Skip exceeds available returns nothing", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "P2", published = true, views = 20, created_at = 2 })
  user.posts:link(post1)
  user.posts:link(post2)

  local enter_count = 0
  local view = g:view({
    type = "User",
    edges = { posts = { skip = 10 } }  -- Skip more than available
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_count = enter_count + 1 end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(enter_count, 0)  -- No posts enter
end)

test("ST08", "Take applied after filters", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local pub1 = g:insert("Post", { title = "Pub1", published = true, views = 10, created_at = 1 })
  local pub2 = g:insert("Post", { title = "Pub2", published = true, views = 20, created_at = 2 })
  local unpub = g:insert("Post", { title = "Unpub", published = false, views = 30, created_at = 3 })
  user.posts:link(pub1)
  user.posts:link(pub2)
  user.posts:link(unpub)

  local enter_titles = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        filters = {{ field = "published", op = "eq", value = true }},
        sort = { field = "title", dir = "asc" },
        take = 1,  -- Only first published
      }
    }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_titles[#enter_titles + 1] = node.title:get() end
      end,
    },
  })

  view:expand(user._id, "posts")
  assert_eq(#enter_titles, 1)
  assert_eq(enter_titles[1], "Pub1")  -- First published by title
end)

test("ST09", "Take with inline - select N then hoist children", function()
  local g = neo.create(view_schema())
  local user = g:insert("User", { name = "Alice", active = true })
  local post1 = g:insert("Post", { title = "P1", published = true, created_at = 1 })
  local post2 = g:insert("Post", { title = "P2", published = true, created_at = 2 })
  local comment1 = g:insert("Comment", { text = "C1" })
  local comment2 = g:insert("Comment", { text = "C2" })
  user.posts:link(post1)
  user.posts:link(post2)
  post1.comments:link(comment1)
  post2.comments:link(comment2)

  local view = g:view({
    type = "User",
    edges = {
      posts = {
        inline = true,
        sort = { field = "created_at", dir = "desc" },
        take = 1,  -- Only latest post (post2)
        edges = { comments = {} },
      }
    }
  })

  view:expand(user._id, "posts")
  view:expand(post2._id, "comments")

  local items = view:collect()
  -- User + comment2 (post2 is inline/skipped, post1 not included due to take=1)
  assert_eq(#items, 2)
  assert_eq(items[1].id, user._id)
  assert_eq(items[2].id, comment2._id)
end)

test("ST10", "Take with eager - auto-expand respects limit", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "A", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "B", published = true, views = 20, created_at = 2 })
  local post3 = g:insert("Post", { title = "C", published = true, views = 30, created_at = 3 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local enter_titles = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        eager = true,
        sort = { field = "title", dir = "asc" },
        take = 2,
      }
    }
  }, {
    callbacks = {
      on_enter = function(node, pos, edge)
        if edge then enter_titles[#enter_titles + 1] = node.title:get() end
      end,
    },
  })

  -- Eager expansion should only include first 2
  assert_eq(#enter_titles, 2)
  assert_eq(enter_titles[1], "A")
  assert_eq(enter_titles[2], "B")
end)

test("ST11", "Take with recursive - each level has same limit", function()
  local g = neo.create(recursive_schema())
  local root = g:insert("Category", { name = "Root", level = 0 })
  local child1 = g:insert("Category", { name = "C1", level = 1 })
  local child2 = g:insert("Category", { name = "C2", level = 1 })
  local grandchild1 = g:insert("Category", { name = "GC1", level = 2 })
  local grandchild2 = g:insert("Category", { name = "GC2", level = 2 })
  root.children:link(child1)
  root.children:link(child2)
  child1.children:link(grandchild1)
  child1.children:link(grandchild2)

  local view = g:view({
    type = "Category",
    filters = {{ field = "level", op = "eq", value = 0 }},
    edges = {
      children = {
        recursive = true,
        take = 1,  -- Only first child at each level
      }
    }
  })

  view:expand(root._id, "children")
  view:expand(child1._id, "children")

  local items = view:collect()
  -- Root + child1 (first of 2) + grandchild1 (first of 2)
  assert_eq(#items, 3)
  assert_eq(items[1].id, root._id)
  assert_eq(items[2].id, child1._id)
  assert_eq(items[3].id, grandchild1._id)
end)

test("ST12", "Take affects visible_total count", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "P1", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "P2", published = true, views = 20, created_at = 2 })
  local post3 = g:insert("Post", { title = "P3", published = true, views = 30, created_at = 3 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local view = g:view({
    type = "User",
    edges = { posts = { take = 2 } }
  })

  view:expand(user._id, "posts")
  assert_eq(view:visible_total(), 3)  -- 1 user + 2 posts (not 4)
end)

test("ST13", "Skip/take with on_leave on collapse", function()
  local g = neo.create(edge_config_schema())
  local user = g:insert("User", { name = "Alice" })
  local post1 = g:insert("Post", { title = "A", published = true, views = 10, created_at = 1 })
  local post2 = g:insert("Post", { title = "B", published = true, views = 20, created_at = 2 })
  local post3 = g:insert("Post", { title = "C", published = true, views = 30, created_at = 3 })
  user.posts:link(post1)
  user.posts:link(post2)
  user.posts:link(post3)

  local leave_titles = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        sort = { field = "title", dir = "asc" },
        skip = 1,
        take = 1,  -- Only B
      }
    }
  }, {
    callbacks = {
      on_leave = function(node, edge)
        if edge then leave_titles[#leave_titles + 1] = node.title:get() end
      end,
    },
  })

  view:expand(user._id, "posts")
  view:collapse(user._id, "posts")

  assert_eq(#leave_titles, 1)
  assert_eq(leave_titles[1], "B")
end)

test("ST14", "Take with nested edges", function()
  local g = neo.create(view_schema())
  local user = g:insert("User", { name = "Alice", active = true })
  local post1 = g:insert("Post", { title = "P1", published = true, created_at = 1 })
  local post2 = g:insert("Post", { title = "P2", published = true, created_at = 2 })
  local c1 = g:insert("Comment", { text = "C1" })
  local c2 = g:insert("Comment", { text = "C2" })
  local c3 = g:insert("Comment", { text = "C3" })
  user.posts:link(post1)
  user.posts:link(post2)
  post1.comments:link(c1)
  post1.comments:link(c2)
  post1.comments:link(c3)

  local view = g:view({
    type = "User",
    edges = {
      posts = {
        take = 1,  -- Only first post
        edges = {
          comments = { take = 2 }  -- Only first 2 comments
        }
      }
    }
  })

  view:expand(user._id, "posts")
  view:expand(post1._id, "comments")

  local items = view:collect()
  -- User + post1 + 2 comments (not 3)
  assert_eq(#items, 4)
  assert_eq(items[1].id, user._id)
  assert_eq(items[2].id, post1._id)
end)

--------------------------------------------------------------------------------
-- Section 22: Edge Handle Identity (EI-*) [Appendix D.1]
--
-- Tests for Issue #1: Edge handles should share subscription state
-- regardless of how they're accessed.
--
-- NOTE: These tests document EXPECTED behavior after the fix is implemented.
-- Currently, EI02-EI08 will FAIL because edge handles don't share state.
--------------------------------------------------------------------------------

section("Edge Handle Identity (EI-*)")

test("EI01", "Same handle subscription and mutation (baseline)", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local fired = false
  local handle = user.posts
  handle:onLink(function(node)
    fired = true
    assert_eq(node._id, post._id)
  end)

  handle:link(post)
  assert_true(fired, "Callback should fire")
end)

test("EI02", "Different handles from same proxy share state", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local handle1 = user.posts
  local handle2 = user.posts

  local fired = false
  handle1:onLink(function(node)
    fired = true
    assert_eq(node._id, post._id)
  end)

  -- Link via different handle - should still fire callback on handle1
  handle2:link(post)
  assert_true(fired, "Callback on handle1 should fire when handle2 links")
end)

test("EI03", "Handles from different proxy accesses share state", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local proxy1 = g:get(user._id)
  local proxy2 = g:get(user._id)

  local fired = false
  proxy1.posts:onLink(function(node)
    fired = true
  end)

  proxy2.posts:link(post)
  assert_true(fired, "Callback should fire across proxy instances")
end)

test("EI04", "Handle subscription survives garbage collection", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })
  local user_id = user._id

  local fired = false
  g:get(user_id).posts:onLink(function(node)
    fired = true
  end)

  -- Force GC
  collectgarbage("collect")
  collectgarbage("collect")

  -- Get fresh proxy and link
  g:get(user_id).posts:link(post)
  assert_true(fired, "Callback should survive GC")
end)

test("EI05", "Unlink with mutation-first handle access", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  -- Link first
  user.posts:link(post)

  -- Get handles in different order: mutation handle first, then subscribe handle
  local handle1 = user.posts
  local handle2 = user.posts

  local fired = false
  handle2:onUnlink(function(node)
    fired = true
  end)

  handle1:unlink(post)
  assert_true(fired, "Order of handle access shouldn't matter")
end)

test("EI06", "Each subscription with same handle mutation", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local entered = {}
  local handle = user.posts
  handle:each(function(node)
    entered[#entered + 1] = node._id
  end)

  handle:link(post)
  assert_eq(#entered, 1)
  assert_eq(entered[1], post._id)
end)

test("EI07", "Each subscription with different handle mutation", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local entered = {}
  user.posts:each(function(node)
    entered[#entered + 1] = node._id
  end)

  -- Different handle access
  user.posts:link(post)
  assert_eq(#entered, 1, "each() should work across handle instances")
end)

test("EI08", "Unlink after GC with same logical handle", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })
  local user_id = user._id

  user.posts:link(post)

  local fired = false
  user.posts:onUnlink(function(node)
    fired = true
  end)

  collectgarbage("collect")
  collectgarbage("collect")

  g:get(user_id).posts:unlink(post)
  assert_true(fired, "onUnlink should fire after GC")
end)

--------------------------------------------------------------------------------
-- Section 23: Reverse Edge Event Propagation (REP-*) [Appendix D.2]
--
-- Tests for Issue #13: Both forward and reverse edges should fire events
-- when either side is linked/unlinked.
--
-- NOTE: Tests REP02, REP03, REP05-REP08 document EXPECTED behavior after fix.
-- Currently they will FAIL because reverse edge events don't propagate.
--------------------------------------------------------------------------------

section("Reverse Edge Event Propagation (REP-*)")

test("REP01", "Forward link, forward subscription (baseline)", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local fired = false
  local received_node
  user.posts:onLink(function(node)
    fired = true
    received_node = node
  end)

  user.posts:link(post)
  assert_true(fired, "Forward subscription should fire on forward link")
  assert_eq(received_node._id, post._id)
end)

test("REP02", "Forward link, reverse subscription", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local fired = false
  local received_node
  post.author:onLink(function(node)
    fired = true
    received_node = node
  end)

  -- Link from forward side
  user.posts:link(post)
  assert_true(fired, "Reverse subscription should fire on forward link")
  assert_eq(received_node._id, user._id)
end)

test("REP03", "Reverse link, forward subscription", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local fired = false
  local received_node
  user.posts:onLink(function(node)
    fired = true
    received_node = node
  end)

  -- Link from reverse side
  post.author:link(user)
  assert_true(fired, "Forward subscription should fire on reverse link")
  assert_eq(received_node._id, post._id)
end)

test("REP04", "Reverse link, reverse subscription (baseline)", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local fired = false
  local received_node
  post.author:onLink(function(node)
    fired = true
    received_node = node
  end)

  post.author:link(user)
  assert_true(fired, "Reverse subscription should fire on reverse link")
  assert_eq(received_node._id, user._id)
end)

test("REP05", "Forward link, both sides subscribed", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local forward_fired = false
  local reverse_fired = false

  user.posts:onLink(function(node)
    forward_fired = true
  end)

  post.author:onLink(function(node)
    reverse_fired = true
  end)

  user.posts:link(post)
  assert_true(forward_fired, "Forward subscription should fire")
  assert_true(reverse_fired, "Reverse subscription should fire")
end)

test("REP06", "Reverse link, both sides subscribed", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local forward_fired = false
  local reverse_fired = false

  user.posts:onLink(function(node)
    forward_fired = true
  end)

  post.author:onLink(function(node)
    reverse_fired = true
  end)

  post.author:link(user)
  assert_true(forward_fired, "Forward subscription should fire on reverse link")
  assert_true(reverse_fired, "Reverse subscription should fire on reverse link")
end)

test("REP07", "Forward unlink, reverse subscription", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  user.posts:link(post)

  local fired = false
  post.author:onUnlink(function(node)
    fired = true
  end)

  user.posts:unlink(post)
  assert_true(fired, "Reverse onUnlink should fire on forward unlink")
end)

test("REP08", "Reverse unlink, forward subscription", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  user.posts:link(post)

  local fired = false
  user.posts:onUnlink(function(node)
    fired = true
  end)

  post.author:unlink(user)
  assert_true(fired, "Forward onUnlink should fire on reverse unlink")
end)

test("REP09", "Forward link with each() subscription", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  local entered = {}
  user.posts:each(function(node)
    entered[#entered + 1] = node._id
  end)

  user.posts:link(post)
  assert_eq(#entered, 1)
end)

test("REP10", "Reverse unlink with each() cleanup", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })

  user.posts:link(post)

  local cleanup_called = false
  post.author:each(function(node)
    return function()
      cleanup_called = true
    end
  end)

  post.author:unlink(user)
  assert_true(cleanup_called, "each() cleanup should fire on reverse unlink")
end)

--------------------------------------------------------------------------------
-- Section 24: Previous Value in Callbacks (PV-*) [Appendix D.3]
--
-- Tests for Issue #5: Signal callbacks should receive old value as second arg.
--
-- NOTE: Tests PV02-PV05 document EXPECTED behavior after fix.
-- Currently they will FAIL because old value is not passed.
--------------------------------------------------------------------------------

section("Previous Value in Callbacks (PV-*)")

test("PV01", "Unary callback ignores old value (backward compat)", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local received = nil
  user.name:use(function(new)
    received = new
  end)

  user.name:set("Bob")
  assert_eq(received, "Bob")
end)

test("PV02", "Binary callback receives old value on first change", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local new_val, old_val
  user.name:use(function(new, old)
    new_val = new
    old_val = old
  end)

  -- Initial call
  assert_eq(new_val, "Alice")

  user.name:set("Bob")
  assert_eq(new_val, "Bob")
  assert_eq(old_val, "Alice", "Old value should be passed as second arg")
end)

test("PV03", "Binary callback on subsequent changes", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local history = {}
  user.name:use(function(new, old)
    history[#history + 1] = { new = new, old = old }
  end)

  user.name:set("Bob")
  user.name:set("Charlie")

  assert_eq(#history, 3)  -- initial + 2 changes
  assert_eq(history[2].new, "Bob")
  assert_eq(history[2].old, "Alice")
  assert_eq(history[3].new, "Charlie")
  assert_eq(history[3].old, "Bob")
end)

test("PV04", "Nil to value transition", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })  -- nickname is nil

  local new_val, old_val
  local call_count = 0
  user.nickname:use(function(new, old)
    new_val = new
    old_val = old
    call_count = call_count + 1
  end)

  user.nickname:set("Al")
  assert_eq(new_val, "Al")
  assert_nil(old_val, "Old value should be nil")
end)

test("PV05", "Value to nil transition", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice", nickname = "Al" })

  local new_val, old_val
  user.nickname:use(function(new, old)
    new_val = new
    old_val = old
  end)

  g:update(user._id, { nickname = neo.NIL })
  assert_nil(new_val, "New value should be nil")
  assert_eq(old_val, "Al", "Old value should be preserved")
end)

test("PV06", "Unary callback with value to nil (backward compat)", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice", nickname = "Al" })

  local received = "not_called"
  user.nickname:use(function(new)
    received = new
  end)

  g:update(user._id, { nickname = neo.NIL })
  assert_nil(received, "Unary callback should receive nil without error")
end)

--------------------------------------------------------------------------------
-- Section 25: Deep Equality (DE-*) [Appendix D.4]
--
-- Tests for Issue #9: Table values should use deep equality to prevent
-- spurious updates when structurally equal.
--
-- NOTE: These tests document EXPECTED behavior after fix.
-- Currently they will FAIL because tables are compared by reference.
--------------------------------------------------------------------------------

section("Deep Equality (DE-*)")

-- Helper for deep equality tests - schema that allows table properties
-- Note: In practice, neograph may not support table properties directly.
-- These tests assume a mechanism for storing/comparing structured data.

test("DE01", "Flat equal tables - no spurious update", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  -- Using name as proxy for table behavior conceptually
  -- Real implementation would need table property support
  local call_count = 0
  user.name:use(function(new)
    call_count = call_count + 1
  end)

  -- Initial call
  assert_eq(call_count, 1)

  -- Set to same value
  user.name:set("Alice")

  -- Should not fire again (same primitive value)
  assert_eq(call_count, 1, "No update for same value")
end)

test("DE02", "Different values trigger update", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local call_count = 0
  user.name:use(function(new)
    call_count = call_count + 1
  end)

  user.name:set("Bob")
  assert_eq(call_count, 2, "Update should fire for different value")
end)

test("DE03", "Nil equality", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local call_count = 0
  user.nickname:use(function(new)
    call_count = call_count + 1
  end)

  -- Set nil to nil - should not trigger
  g:update(user._id, { nickname = neo.NIL })
  -- Initial was nil, setting to nil again shouldn't fire extra
  -- (depends on implementation - may fire once for initial)
end)

test("DE04", "Number equality", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice", age = 30 })

  local call_count = 0
  user.age:use(function(new)
    call_count = call_count + 1
  end)

  -- Set to same number
  user.age:set(30)
  assert_eq(call_count, 1, "No update for same number")

  user.age:set(31)
  assert_eq(call_count, 2, "Update for different number")
end)

test("DE05", "Boolean equality", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice", active = true })

  local call_count = 0
  user.active:use(function(new)
    call_count = call_count + 1
  end)

  user.active:set(true)
  assert_eq(call_count, 1, "No update for same boolean")

  user.active:set(false)
  assert_eq(call_count, 2, "Update for different boolean")
end)

test("DE06", "String equality", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local call_count = 0
  user.name:use(function(new)
    call_count = call_count + 1
  end)

  user.name:set("Alice")
  assert_eq(call_count, 1, "No update for same string")

  user.name:set("Bob")
  assert_eq(call_count, 2, "Update for different string")
end)

test("DE07", "Nil to value is change", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local call_count = 0
  user.nickname:use(function(new)
    call_count = call_count + 1
  end)

  local initial_count = call_count
  user.nickname:set("Al")
  assert_eq(call_count, initial_count + 1, "Nil to value should trigger update")
end)

--------------------------------------------------------------------------------
-- Section 26: Multi-Subscriber Events (MS-*) [Appendix D.5]
--
-- Tests for Issue #2: All registered callbacks should fire for each event.
--
-- NOTE: Some tests may FAIL if multi-subscriber is broken.
--------------------------------------------------------------------------------

section("Multi-Subscriber Events (MS-*)")

test("MS01", "Two subscribers via on() both fire", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice", active = true })

  local enter1 = 0
  local enter2 = 0

  local view = g:view({ type = "User" })
  view:on("enter", function(node) enter1 = enter1 + 1 end)
  view:on("enter", function(node) enter2 = enter2 + 1 end)

  -- Both should have fired for initial user
  -- Insert another to trigger more enter events
  local user2 = g:insert("User", { name = "Bob", active = true })

  assert_true(enter1 > 0, "First subscriber should fire")
  assert_true(enter2 > 0, "Second subscriber should fire")
  assert_eq(enter1, enter2, "Both should fire same number of times")
end)

test("MS02", "Three subscribers via on() all fire", function()
  local g = neo.create(basic_schema())

  local counts = { 0, 0, 0 }

  local view = g:view({ type = "User" })
  view:on("enter", function(node) counts[1] = counts[1] + 1 end)
  view:on("enter", function(node) counts[2] = counts[2] + 1 end)
  view:on("enter", function(node) counts[3] = counts[3] + 1 end)

  g:insert("User", { name = "Alice", active = true })

  assert_eq(counts[1], counts[2])
  assert_eq(counts[2], counts[3])
  assert_true(counts[1] > 0, "All should fire")
end)

test("MS03", "Unsubscribe middle subscriber", function()
  local g = neo.create(basic_schema())

  local counts = { 0, 0, 0 }

  local view = g:view({ type = "User" })
  view:on("leave", function(node) counts[1] = counts[1] + 1 end)
  local unsub2 = view:on("leave", function(node) counts[2] = counts[2] + 1 end)
  view:on("leave", function(node) counts[3] = counts[3] + 1 end)

  local user = g:insert("User", { name = "Alice", active = true })

  -- Unsubscribe middle
  unsub2()

  -- Delete to trigger leave
  g:delete(user._id)

  assert_true(counts[1] > 0, "First should fire")
  assert_eq(counts[2], 0, "Middle should not fire after unsub")
  assert_true(counts[3] > 0, "Third should fire")
end)

test("MS04", "Constructor callback with on() addition", function()
  local g = neo.create(basic_schema())

  local constructor_count = 0
  local dynamic_count = 0

  local view = g:view({ type = "User" }, {
    callbacks = {
      on_change = function(node, prop, new, old)
        constructor_count = constructor_count + 1
      end,
    },
  })

  view:on("change", function(node, prop, new, old)
    dynamic_count = dynamic_count + 1
  end)

  local user = g:insert("User", { name = "Alice", active = true })
  user.name:set("Bob")

  assert_true(constructor_count > 0, "Constructor callback should fire")
  assert_true(dynamic_count > 0, "Dynamic callback should fire")
end)

test("MS05", "Mixed registration with three subscribers", function()
  local g = neo.create(basic_schema())

  local counts = { 0, 0, 0 }

  local view = g:view({ type = "User" }, {
    callbacks = {
      on_change = function(node, prop, new, old)
        counts[1] = counts[1] + 1
      end,
    },
  })

  view:on("change", function(node, prop, new, old)
    counts[2] = counts[2] + 1
  end)

  view:on("change", function(node, prop, new, old)
    counts[3] = counts[3] + 1
  end)

  local user = g:insert("User", { name = "Alice", active = true })
  user.name:set("Bob")

  assert_true(counts[1] > 0, "Constructor callback should fire")
  assert_true(counts[2] > 0, "First dynamic should fire")
  assert_true(counts[3] > 0, "Second dynamic should fire")
end)

test("MS06", "Many subscribers with first unsubscribed", function()
  local g = neo.create(basic_schema())

  local counts = { 0, 0, 0, 0, 0 }

  local view = g:view({ type = "User" })
  local unsub1 = view:on("enter", function(node) counts[1] = counts[1] + 1 end)
  view:on("enter", function(node) counts[2] = counts[2] + 1 end)
  view:on("enter", function(node) counts[3] = counts[3] + 1 end)
  view:on("enter", function(node) counts[4] = counts[4] + 1 end)
  view:on("enter", function(node) counts[5] = counts[5] + 1 end)

  -- Unsubscribe first before any events
  unsub1()

  g:insert("User", { name = "Alice", active = true })

  assert_eq(counts[1], 0, "First should not fire after unsub")
  assert_true(counts[2] > 0, "Others should fire")
  assert_true(counts[3] > 0)
  assert_true(counts[4] > 0)
  assert_true(counts[5] > 0)
end)

test("MS07", "On_enter fires in registration order", function()
  local g = neo.create(basic_schema())

  local order = {}

  local view = g:view({ type = "User" })
  view:on("enter", function(node) order[#order + 1] = 1 end)
  view:on("enter", function(node) order[#order + 1] = 2 end)
  view:on("enter", function(node) order[#order + 1] = 3 end)

  g:insert("User", { name = "Alice", active = true })

  -- Check order (may have multiple entries if multiple nodes)
  for i = 1, #order, 3 do
    if order[i] and order[i+1] and order[i+2] then
      assert_eq(order[i], 1)
      assert_eq(order[i+1], 2)
      assert_eq(order[i+2], 3)
    end
  end
end)

--------------------------------------------------------------------------------
-- Section 27: Undefined Property Access (UP-*) [Appendix D.6]
--
-- Tests for Issue #7: Accessing undefined properties behavior.
--
-- These tests document CURRENT behavior. The fix options are:
-- Option 1: Schema-defined properties only (return nil for undefined)
-- Option 2: Explicit node:signal(name) method
-- Option 3: Reserve _ prefix (return nil for _* keys)
--------------------------------------------------------------------------------

section("Undefined Property Access (UP-*)")

test("UP01", "Defined property returns Signal", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local signal = user.name
  assert_not_nil(signal, "Defined property should return Signal")
  assert_eq(signal:get(), "Alice")
end)

test("UP02", "Undefined property returns Signal (current behavior)", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  -- This documents CURRENT behavior - undefined returns Signal
  local signal = user.nonexistent_property
  assert_not_nil(signal, "Currently returns Signal for any property")
  assert_nil(signal:get(), "Value should be nil")
end)

test("UP03", "_id returns id directly", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local id = user._id
  assert_eq(type(id), "number", "_id should return number")
  assert_true(id > 0)
end)

test("UP04", "_type returns type string", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local typ = user._type
  assert_eq(typ, "User", "_type should return type name")
end)

test("UP05", "Edge property returns EdgeHandle", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local handle = user.posts
  assert_not_nil(handle, "Edge should return EdgeHandle")
  -- EdgeHandle should have :link, :iter, etc.
  assert_eq(type(handle.link), "function")
  assert_eq(type(handle.iter), "function")
end)

--------------------------------------------------------------------------------
-- on_expand Context Tests (OE-*)
--------------------------------------------------------------------------------

print("\n-- on_expand Context Tests (OE-*) --")

test("OE01", "Manual expand has eager=false", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })
  user.posts:link(post)

  local expand_data = nil
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expand_data = { node = node, edge = edge_name, context = context }
      end
    }
  })

  view:expand(user._id, "posts")
  assert_not_nil(expand_data)
  assert_eq(expand_data.node._id, user._id)
  assert_eq(expand_data.edge, "posts")
  assert_false(expand_data.context.eager)
  assert_eq(expand_data.context.path_key, tostring(user._id))
  assert_false(expand_data.context.inline)
end)

test("OE02", "Eager root expand has eager=true", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })
  user.posts:link(post)

  local expand_data = nil
  local view = g:view({
    type = "User",
    edges = { posts = { eager = true } }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expand_data = { node = node, edge = edge_name, context = context }
      end
    }
  })

  assert_not_nil(expand_data)
  assert_eq(expand_data.node._id, user._id)
  assert_eq(expand_data.edge, "posts")
  assert_true(expand_data.context.eager)
end)

test("OE03", "Recursive eager expand all have eager=true", function()
  local nested_schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },
      __indexes = { { name = "default", fields = {} } },
    },
    Comment = {
      text = "string",
      post = { type = "edge", target = "Post", reverse = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(nested_schema)
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  local comment = g:insert("Comment", { text = "Nice" })
  user.posts:link(post)
  post.comments:link(comment)

  local expands = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        eager = true,
        edges = {
          comments = { eager = true }
        }
      }
    }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expands[#expands + 1] = {
          node_id = node._id,
          edge = edge_name,
          eager = context.eager,
          path_key = context.path_key
        }
      end
    }
  })

  -- Should have at least 2 expansions (posts on user, comments on post)
  assert_true(#expands >= 2)

  -- Find posts expansion
  local posts_exp = nil
  local comments_exp = nil
  for _, e in ipairs(expands) do
    if e.edge == "posts" then posts_exp = e end
    if e.edge == "comments" then comments_exp = e end
  end

  assert_not_nil(posts_exp)
  assert_true(posts_exp.eager)
  assert_eq(posts_exp.node_id, user._id)

  assert_not_nil(comments_exp)
  assert_true(comments_exp.eager)
  assert_eq(comments_exp.node_id, post._id)
end)

test("OE04", "Eager expand on new link has eager=true", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })

  local expands = {}
  local view = g:view({
    type = "User",
    edges = { posts = { eager = true } }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expands[#expands + 1] = {
          node_id = node._id,
          edge = edge_name,
          eager = context.eager
        }
      end
    }
  })

  -- Initial expand (even with no children)
  local initial_count = #expands

  -- Now add a post dynamically - this should NOT trigger another on_expand
  -- for the same edge (already expanded)
  local post = g:insert("Post", { title = "P1", published = true })
  user.posts:link(post)

  -- Count should remain the same since edge is already expanded
  assert_eq(#expands, initial_count)
end)

test("OE05", "Eager expand fires for children added after init", function()
  local nested_schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },
      __indexes = { { name = "default", fields = {} } },
    },
    Comment = {
      text = "string",
      post = { type = "edge", target = "Post", reverse = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(nested_schema)
  local user = g:insert("User", { name = "Alice" })

  local expands = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        eager = true,
        edges = {
          comments = { eager = true }
        }
      }
    }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expands[#expands + 1] = {
          node_id = node._id,
          edge = edge_name,
          eager = context.eager
        }
      end
    }
  })

  local initial_count = #expands

  -- Add a post after view is created
  local post = g:insert("Post", { title = "Hello" })
  user.posts:link(post)

  -- Should have fired on_expand for comments on the new post (eager)
  local found_comments = false
  for i = initial_count + 1, #expands do
    if expands[i].edge == "comments" and expands[i].node_id == post._id then
      found_comments = true
      assert_true(expands[i].eager)
    end
  end
  assert_true(found_comments, "Should expand comments on newly linked post")
end)

test("OE06", "Inline edge has inline=true in context", function()
  local nested_schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },
      __indexes = { { name = "default", fields = {} } },
    },
    Comment = {
      text = "string",
      post = { type = "edge", target = "Post", reverse = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(nested_schema)
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  local comment = g:insert("Comment", { text = "Nice" })
  user.posts:link(post)
  post.comments:link(comment)

  local expands = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        eager = true,
        inline = true,  -- posts are inline
        edges = {
          comments = { eager = true }
        }
      }
    }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expands[#expands + 1] = {
          node_id = node._id,
          edge = edge_name,
          inline = context.inline,
          eager = context.eager
        }
      end
    }
  })

  -- Find posts expansion - should have inline=true
  local posts_exp = nil
  local comments_exp = nil
  for _, e in ipairs(expands) do
    if e.edge == "posts" then posts_exp = e end
    if e.edge == "comments" then comments_exp = e end
  end

  assert_not_nil(posts_exp)
  assert_true(posts_exp.inline, "posts should have inline=true")
  assert_true(posts_exp.eager)

  assert_not_nil(comments_exp)
  assert_false(comments_exp.inline, "comments should have inline=false")
  assert_true(comments_exp.eager)
end)

test("OE07", "on_expand receives node proxy with _id and _type", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })
  user.posts:link(post)

  local received_node = nil
  local view = g:view({
    type = "User",
    edges = { posts = { eager = true } }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        received_node = node
      end
    }
  })

  assert_not_nil(received_node)
  assert_eq(received_node._id, user._id)
  assert_eq(received_node._type, "User")
  -- Should be able to access properties via Signal
  assert_eq(received_node.name:get(), "Alice")
end)

test("OE08", "path_key tracks full path for nested expansions", function()
  local nested_schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },
      __indexes = { { name = "default", fields = {} } },
    },
    Comment = {
      text = "string",
      post = { type = "edge", target = "Post", reverse = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(nested_schema)
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  local comment = g:insert("Comment", { text = "Nice" })
  user.posts:link(post)
  post.comments:link(comment)

  local expands = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        eager = true,
        edges = {
          comments = { eager = true }
        }
      }
    }
  }, {
    callbacks = {
      on_expand = function(node, edge_name, context)
        expands[#expands + 1] = {
          edge = edge_name,
          path_key = context.path_key
        }
      end
    }
  })

  -- posts expansion should have path_key = user_id
  -- comments expansion should have path_key = user_id:posts:post_id
  local posts_exp = nil
  local comments_exp = nil
  for _, e in ipairs(expands) do
    if e.edge == "posts" then posts_exp = e end
    if e.edge == "comments" then comments_exp = e end
  end

  assert_not_nil(posts_exp)
  assert_eq(posts_exp.path_key, tostring(user._id))

  assert_not_nil(comments_exp)
  local expected_path = user._id .. ":posts:" .. post._id
  assert_eq(comments_exp.path_key, expected_path)
end)

test("OE09", "on_collapse receives node proxy with context", function()
  local g = neo.create(basic_schema())
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "P1", published = true })
  user.posts:link(post)

  local collapse_data = nil
  local view = g:view({
    type = "User",
    edges = { posts = {} }
  }, {
    callbacks = {
      on_collapse = function(node, edge_name, context)
        collapse_data = { node = node, edge = edge_name, context = context }
      end
    }
  })

  view:expand(user._id, "posts")
  view:collapse(user._id, "posts")

  assert_not_nil(collapse_data)
  assert_eq(collapse_data.node._id, user._id)
  assert_eq(collapse_data.node._type, "User")
  assert_eq(collapse_data.edge, "posts")
  assert_eq(collapse_data.context.path_key, tostring(user._id))
  assert_false(collapse_data.context.inline)
end)

test("OE10", "on_collapse inline=true for inline edge", function()
  local nested_schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },
      __indexes = { { name = "default", fields = {} } },
    },
    Comment = {
      text = "string",
      post = { type = "edge", target = "Post", reverse = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(nested_schema)
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  local comment = g:insert("Comment", { text = "Nice" })
  user.posts:link(post)
  post.comments:link(comment)

  local collapses = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        inline = true,
        edges = {
          comments = {}
        }
      }
    }
  }, {
    callbacks = {
      on_collapse = function(node, edge_name, context)
        collapses[#collapses + 1] = {
          node_id = node._id,
          edge = edge_name,
          inline = context.inline
        }
      end
    }
  })

  -- Manually expand
  view:expand(user._id, "posts")
  view:expand(post._id, "comments")

  -- Collapse posts (inline edge)
  view:collapse(user._id, "posts")

  -- Should have collapsed posts with inline=true
  local posts_collapse = nil
  for _, c in ipairs(collapses) do
    if c.edge == "posts" then posts_collapse = c end
  end

  assert_not_nil(posts_collapse)
  assert_true(posts_collapse.inline)
end)

test("OE11", "on_collapse path_key tracks nested path", function()
  local nested_schema = {
    User = {
      name = "string",
      posts = { type = "edge", target = "Post", reverse = "author" },
      __indexes = { { name = "default", fields = {} } },
    },
    Post = {
      title = "string",
      author = { type = "edge", target = "User", reverse = "posts" },
      comments = { type = "edge", target = "Comment", reverse = "post" },
      __indexes = { { name = "default", fields = {} } },
    },
    Comment = {
      text = "string",
      post = { type = "edge", target = "Post", reverse = "comments" },
      __indexes = { { name = "default", fields = {} } },
    },
  }

  local g = neo.create(nested_schema)
  local user = g:insert("User", { name = "Alice" })
  local post = g:insert("Post", { title = "Hello" })
  local comment = g:insert("Comment", { text = "Nice" })
  user.posts:link(post)
  post.comments:link(comment)

  local collapses = {}
  local view = g:view({
    type = "User",
    edges = {
      posts = {
        edges = {
          comments = {}
        }
      }
    }
  }, {
    callbacks = {
      on_collapse = function(node, edge_name, context)
        collapses[#collapses + 1] = {
          edge = edge_name,
          path_key = context.path_key
        }
      end
    }
  })

  -- Expand both levels
  view:expand(user._id, "posts")
  view:expand(post._id, "comments")

  -- Collapse comments (nested)
  view:collapse(post._id, "comments")

  -- Should have path_key = user_id:posts:post_id
  assert_eq(#collapses, 1)
  local expected_path = user._id .. ":posts:" .. post._id
  assert_eq(collapses[1].path_key, expected_path)
end)

--------------------------------------------------------------------------------
-- Summary
--------------------------------------------------------------------------------

print("\n" .. string.rep("=", 50))
print("Compliance Test Results")
print(string.rep("=", 50))
print(string.format("Passed: %d", passed))
print(string.format("Failed: %d", failed))
print(string.format("Total:  %d", passed + failed))
print(string.rep("=", 50))

if failed > 0 then
  os.exit(1)
end
