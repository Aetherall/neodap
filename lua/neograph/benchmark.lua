--[[
  Performance Benchmark: init.lua vs init_2.lua

  Tests:
  - Node insertion (bulk)
  - Property updates (bulk)
  - Edge linking (bulk)
  - Edge unlinking (bulk)
  - View creation
  - View iteration
  - View expand/collapse
  - Rollup computation
  - Signal subscriptions
  - EdgeHandle iteration
--]]

local function get_time()
  return os.clock()
end

local function format_time(seconds)
  if seconds < 0.001 then
    return string.format("%.2f µs", seconds * 1000000)
  elseif seconds < 1 then
    return string.format("%.2f ms", seconds * 1000)
  else
    return string.format("%.2f s", seconds)
  end
end

local function format_ops(count, seconds)
  local ops = count / seconds
  if ops > 1000000 then
    return string.format("%.2f M/s", ops / 1000000)
  elseif ops > 1000 then
    return string.format("%.2f K/s", ops / 1000)
  else
    return string.format("%.2f /s", ops)
  end
end

local function benchmark(name, iterations, fn)
  -- Warmup
  for _ = 1, math.min(100, iterations / 10) do
    fn()
  end

  -- Collect garbage before timing
  collectgarbage("collect")

  local start = get_time()
  for _ = 1, iterations do
    fn()
  end
  local elapsed = get_time() - start

  return {
    name = name,
    iterations = iterations,
    elapsed = elapsed,
    per_op = elapsed / iterations,
  }
end

local function run_benchmarks(neo, impl_name, schema)
  print("\n" .. string.rep("=", 60))
  print("Benchmarking: " .. impl_name)
  print(string.rep("=", 60))

  local results = {}

  -- Use provided schema
  local schema = schema or {
    types = {
      {
        name = "User",
        properties = {
          { name = "name", type = "string" },
          { name = "age", type = "number" },
          { name = "active", type = "bool" },
        },
        edges = {
          {
            name = "posts",
            target = "Post",
            reverse = "author",
            indexes = {
              { name = "default", fields = {} },
              { name = "by_created", fields = {{ name = "created_at", dir = "desc" }} },
            },
          },
          {
            name = "friends",
            target = "User",
            reverse = "friends",
            indexes = {
              { name = "default", fields = {} },
            },
          },
        },
        indexes = {
          { name = "default", fields = {{ name = "name" }} },
          { name = "by_age", fields = {{ name = "age", dir = "desc" }} },
        },
        rollups = {
          { kind = "property", name = "post_count", edge = "posts", compute = "count" },
          { kind = "property", name = "total_views", edge = "posts", compute = "sum", property = "views" },
          { kind = "reference", name = "latest_post", edge = "posts", sort = { field = "created_at", dir = "desc" } },
        },
      },
      {
        name = "Post",
        properties = {
          { name = "title", type = "string" },
          { name = "views", type = "number" },
          { name = "published", type = "bool" },
          { name = "created_at", type = "number" },
        },
        edges = {
          {
            name = "author",
            target = "User",
            reverse = "posts",
            indexes = {
              { name = "default", fields = {} },
            },
          },
          {
            name = "comments",
            target = "Comment",
            reverse = "post",
            indexes = {
              { name = "default", fields = {} },
            },
          },
        },
        indexes = {
          { name = "default", fields = {{ name = "title" }} },
          { name = "by_views", fields = {{ name = "views", dir = "desc" }} },
          { name = "by_created", fields = {{ name = "created_at", dir = "desc" }} },
        },
        rollups = {
          { kind = "property", name = "comment_count", edge = "comments", compute = "count" },
        },
      },
      {
        name = "Comment",
        properties = {
          { name = "text", type = "string" },
          { name = "created_at", type = "number" },
        },
        edges = {
          {
            name = "post",
            target = "Post",
            reverse = "comments",
            indexes = {
              { name = "default", fields = {} },
            },
          },
        },
        indexes = {
          { name = "default", fields = {{ name = "created_at" }} },
        },
      },
    },
  }

  --============================================================================
  -- Benchmark 1: Node Insertion
  --============================================================================
  local function bench_insert()
    local graph = neo.create(schema)
    local r = benchmark("Insert 1000 nodes", 1000, function()
      graph:insert("User", { name = "User", age = 25, active = true })
    end)
    results[#results + 1] = r
  end
  bench_insert()

  --============================================================================
  -- Benchmark 2: Property Updates
  --============================================================================
  local function bench_update()
    local graph = neo.create(schema)
    local nodes = {}
    for i = 1, 1000 do
      nodes[i] = graph:insert("User", { name = "User" .. i, age = 20 + (i % 50), active = true })
    end

    local idx = 0
    local r = benchmark("Update 1000 properties", 1000, function()
      idx = (idx % 1000) + 1
      graph:update(nodes[idx]._id, { age = 30 + idx })
    end)
    results[#results + 1] = r
  end
  bench_update()

  --============================================================================
  -- Benchmark 3: Edge Linking
  --============================================================================
  local function bench_link()
    local graph = neo.create(schema)
    local users = {}
    local posts = {}
    for i = 1, 100 do
      users[i] = graph:insert("User", { name = "User" .. i, age = 25, active = true })
    end
    for i = 1, 1000 do
      posts[i] = graph:insert("Post", { title = "Post" .. i, views = i * 10, published = true, created_at = i })
    end

    local user_idx = 0
    local post_idx = 0
    local r = benchmark("Link 1000 edges", 1000, function()
      user_idx = (user_idx % 100) + 1
      post_idx = (post_idx % 1000) + 1
      users[user_idx].posts:link(posts[post_idx])
    end)
    results[#results + 1] = r
  end
  bench_link()

  --============================================================================
  -- Benchmark 4: Edge Unlinking
  --============================================================================
  local function bench_unlink()
    local graph = neo.create(schema)
    local user = graph:insert("User", { name = "User", age = 25, active = true })
    local posts = {}
    for i = 1, 1000 do
      posts[i] = graph:insert("Post", { title = "Post" .. i, views = i * 10, published = true, created_at = i })
      user.posts:link(posts[i])
    end

    local idx = 0
    local r = benchmark("Unlink 1000 edges", 1000, function()
      idx = idx + 1
      user.posts:unlink(posts[idx])
    end)
    results[#results + 1] = r
  end
  bench_unlink()

  --============================================================================
  -- Benchmark 5: View Creation
  --============================================================================
  local function bench_view_create()
    local graph = neo.create(schema)
    for i = 1, 100 do
      graph:insert("User", { name = "User" .. i, age = 20 + (i % 50), active = i % 2 == 0 })
    end

    local r = benchmark("Create 100 views", 100, function()
      local view = graph:view({
        type = "User",
        edges = { posts = { edges = { comments = {} } } },
      }, {
        limit = 50,
      })
      view:destroy()
    end)
    results[#results + 1] = r
  end
  bench_view_create()

  --============================================================================
  -- Benchmark 6: View Iteration
  --============================================================================
  local function bench_view_iter()
    local graph = neo.create(schema)
    for i = 1, 1000 do
      graph:insert("User", { name = "User" .. i, age = 20 + (i % 50), active = true })
    end

    local view = graph:view({
      type = "User",
      edges = { posts = {} },
    }, {
      limit = 100,
    })

    local r = benchmark("Iterate view 1000x", 1000, function()
      local count = 0
      for item in view:items() do
        count = count + 1
      end
    end)
    results[#results + 1] = r
    view:destroy()
  end
  bench_view_iter()

  --============================================================================
  -- Benchmark 7: View Expand/Collapse
  --============================================================================
  local function bench_expand_collapse()
    local graph = neo.create(schema)
    local users = {}
    for i = 1, 10 do
      users[i] = graph:insert("User", { name = "User" .. i, age = 25, active = true })
      for j = 1, 100 do
        local post = graph:insert("Post", { title = "Post" .. j, views = j * 10, published = true, created_at = j })
        users[i].posts:link(post)
      end
    end

    local view = graph:view({
      type = "User",
      edges = { posts = {} },
    }, {
      limit = 500,
    })

    local idx = 0
    local r = benchmark("Expand/collapse 100x", 100, function()
      idx = (idx % 10) + 1
      view:expand(users[idx]._id, "posts")
      view:collapse(users[idx]._id, "posts")
    end)
    results[#results + 1] = r
    view:destroy()
  end
  bench_expand_collapse()

  --============================================================================
  -- Benchmark 8: Rollup Reads
  --============================================================================
  local function bench_rollup_read()
    local graph = neo.create(schema)
    local user = graph:insert("User", { name = "User", age = 25, active = true })
    for i = 1, 100 do
      local post = graph:insert("Post", { title = "Post" .. i, views = i * 10, published = true, created_at = i })
      user.posts:link(post)
    end

    local r = benchmark("Read rollup 10000x", 10000, function()
      local _ = user.post_count:get()
      local _ = user.total_views:get()
    end)
    results[#results + 1] = r
  end
  bench_rollup_read()

  --============================================================================
  -- Benchmark 9: Signal Subscriptions
  --============================================================================
  local function bench_signal_sub()
    local graph = neo.create(schema)
    local user = graph:insert("User", { name = "User", age = 25, active = true })

    local r = benchmark("Subscribe/unsub 1000x", 1000, function()
      local unsub = user.name:use(function(val)
        return function() end
      end)
      unsub()
    end)
    results[#results + 1] = r
  end
  bench_signal_sub()

  --============================================================================
  -- Benchmark 10: EdgeHandle Iteration
  --============================================================================
  local function bench_edge_iter()
    local graph = neo.create(schema)
    local user = graph:insert("User", { name = "User", age = 25, active = true })
    for i = 1, 100 do
      local post = graph:insert("Post", { title = "Post" .. i, views = i * 10, published = true, created_at = i })
      user.posts:link(post)
    end

    local r = benchmark("Iterate edge 1000x", 1000, function()
      local count = 0
      for post in user.posts:iter() do
        count = count + 1
      end
    end)
    results[#results + 1] = r
  end
  bench_edge_iter()

  --============================================================================
  -- Benchmark 11: Filtered Edge Iteration
  --============================================================================
  local function bench_filtered_edge()
    local graph = neo.create(schema)
    local user = graph:insert("User", { name = "User", age = 25, active = true })
    for i = 1, 100 do
      local post = graph:insert("Post", { title = "Post" .. i, views = i * 10, published = i % 2 == 0, created_at = i })
      user.posts:link(post)
    end

    local r = benchmark("Filtered edge iter 1000x", 1000, function()
      local count = 0
      for post in user.posts:iter() do
        if post.published:get() then
          count = count + 1
        end
      end
    end)
    results[#results + 1] = r
  end
  bench_filtered_edge()

  --============================================================================
  -- Benchmark 12: Items iteration scaling (O(n) vs O(n²))
  --============================================================================
  local function bench_items_scaling()
    local graph = neo.create(schema)

    -- Create users with posts (enough for 200 visible items)
    local users = {}
    for i = 1, 100 do
      users[i] = graph:insert("User", { name = "User" .. i, age = 25, active = true })
      for j = 1, 10 do
        local post = graph:insert("Post", { title = "Post" .. j, views = j * 10, published = true, created_at = j })
        users[i].posts:link(post)
      end
    end

    -- Test with different limits to see scaling behavior
    local limits = { 10, 25, 50, 75, 100, 200 }
    local times = {}

    for _, limit in ipairs(limits) do
      local view = graph:view({
        type = "User",
        edges = { posts = {} },
      }, {
        limit = limit,
      })

      -- Expand all users' posts
      for i = 1, math.min(limit, 100) do
        view:expand(users[i]._id, "posts")
      end

      local start = get_time()
      local iterations = 100
      for _ = 1, iterations do
        local count = 0
        for item in view:items() do
          count = count + 1
        end
      end
      local elapsed = get_time() - start

      times[limit] = elapsed / iterations
      view:destroy()
    end

    -- For O(n), doubling n should double time (ratio ~2)
    -- For O(n²), doubling n should quadruple time (ratio ~4)
    print(string.format("\n  Items scaling test:"))
    print(string.format("    %-12s %12s %12s %12s", "limit", "time", "ratio", "expected O(n)"))
    print(string.format("    %s", string.rep("-", 52)))

    local prev_limit = nil
    for _, limit in ipairs(limits) do
      if prev_limit then
        local ratio = times[limit] / times[prev_limit]
        local expected_ratio = limit / prev_limit  -- O(n) expectation
        local expected_ratio_sq = (limit / prev_limit) ^ 2  -- O(n²) expectation
        print(string.format("    %-12d %12s %11.2fx %11.2fx",
          limit, format_time(times[limit]), ratio, expected_ratio))
      else
        print(string.format("    %-12d %12s %12s %12s",
          limit, format_time(times[limit]), "-", "-"))
      end
      prev_limit = limit
    end

    -- Check if scaling is closer to O(n²) than O(n)
    local ratio_50_to_100 = times[100] / times[50]
    local ratio_100_to_200 = times[200] / times[100]
    if ratio_50_to_100 > 3 or ratio_100_to_200 > 3 then
      print("\n    ⚠️  WARNING: Scaling appears to be O(n²) instead of O(n)")
      print(string.format("       50→100 ratio: %.2fx (expected ~2x for O(n), ~4x for O(n²))", ratio_50_to_100))
      print(string.format("       100→200 ratio: %.2fx (expected ~2x for O(n), ~4x for O(n²))", ratio_100_to_200))
    else
      print("\n    ✓ Scaling appears to be O(n)")
    end

    -- Return average for results table
    local r = {
      name = "Items scaling (visible=200)",
      iterations = 100,
      elapsed = times[200] * 100,
      per_op = times[200],
    }
    results[#results + 1] = r
  end
  bench_items_scaling()

  --============================================================================
  -- Benchmark 13: Items scaling with deeply nested tree (10 levels)
  --============================================================================
  local function bench_items_scaling_deep()
    -- Create a schema with 10 levels of nesting using self-referential edges
    local deep_schema = {
      Node = {
        name = "string",
        depth = "number",
        children = { type = "edge", target = "Node", reverse = "parent",
          __indexes = { { name = "default", fields = {} } },
        },
        parent = { type = "edge", target = "Node", reverse = "children",
          __indexes = { { name = "default", fields = {} } },
        },
        __indexes = {
          { name = "default", fields = {{ name = "name" }} },
        },
      },
    }

    local graph = neo.create(deep_schema)

    -- Create a tree with 10 levels of depth
    -- Structure: root -> 2 children -> 2 children each -> ... (10 levels)
    -- Total nodes per root: 2^10 - 1 = 1023
    local DEPTH = 10
    local CHILDREN_PER_NODE = 2

    local function create_subtree(parent, current_depth)
      if current_depth > DEPTH then return end
      for i = 1, CHILDREN_PER_NODE do
        local child = graph:insert("Node", {
          name = string.format("L%d-N%d", current_depth, i),
          depth = current_depth
        })
        if parent then
          parent.children:link(child)
        end
        create_subtree(child, current_depth + 1)
      end
    end

    -- Create root nodes
    local roots = {}
    for i = 1, 3 do
      roots[i] = graph:insert("Node", { name = "Root" .. i, depth = 0 })
      create_subtree(roots[i], 1)
    end

    -- Build nested edge query for 10 levels
    local function build_edge_query(depth)
      if depth <= 0 then return {} end
      return { children = { edges = build_edge_query(depth - 1) } }
    end

    -- Test with different limits (smaller due to deep tree overhead)
    local limits = { 10, 20, 30, 40, 50 }
    local times = {}

    for _, limit in ipairs(limits) do
      local view = graph:view({
        type = "Node",
        filter = function(node) return node.depth:get() == 0 end,  -- Only root nodes
        edges = build_edge_query(DEPTH),
      }, {
        limit = limit,
      })

      -- Recursively expand the tree
      local function expand_recursive(node_id, path, depth)
        if depth > DEPTH then return end
        pcall(function()
          view:expand(node_id, "children", { path = path })
        end)
        local node = graph:get(node_id)
        if node then
          local new_path = {}
          for _, p in ipairs(path) do new_path[#new_path + 1] = p end
          new_path[#new_path + 1] = node_id
          new_path[#new_path + 1] = "children"
          for child in node.children:iter() do
            expand_recursive(child._id, new_path, depth + 1)
          end
        end
      end

      -- Expand from roots
      for _, root in ipairs(roots) do
        expand_recursive(root._id, {}, 1)
      end

      local start = get_time()
      local iterations = 5
      for _ = 1, iterations do
        local count = 0
        for item in view:items() do
          count = count + 1
        end
      end
      local elapsed = get_time() - start

      times[limit] = elapsed / iterations
      view:destroy()
    end

    print(string.format("\n  Items scaling (DEEP nested tree - %d levels, %d children/node):", DEPTH, CHILDREN_PER_NODE))
    print(string.format("    %-12s %12s %12s %12s", "limit", "time", "ratio", "expected O(n)"))
    print(string.format("    %s", string.rep("-", 52)))

    local prev_limit = nil
    for _, limit in ipairs(limits) do
      if prev_limit then
        local ratio = times[limit] / times[prev_limit]
        local expected_ratio = limit / prev_limit
        print(string.format("    %-12d %12s %11.2fx %11.2fx",
          limit, format_time(times[limit]), ratio, expected_ratio))
      else
        print(string.format("    %-12d %12s %12s %12s",
          limit, format_time(times[limit]), "-", "-"))
      end
      prev_limit = limit
    end

    -- Check scaling
    local ratio_20_to_40 = times[40] / times[20]
    if ratio_20_to_40 > 3 then
      print("\n    ⚠️  WARNING: Deep tree scaling appears to be O(n²) or worse")
      print(string.format("       20→40 ratio: %.2fx (expected ~2x for O(n), ~4x for O(n²))", ratio_20_to_40))
    else
      print("\n    ✓ Scaling appears to be O(n)")
    end

    -- Measure _expansion_size_at calls for deep tree
    local view = graph:view({
      type = "Node",
      filter = function(node) return node.depth:get() == 0 end,
      edges = build_edge_query(DEPTH),
    }, {
      limit = 50,
    })

    -- Expand tree
    local function expand_recursive2(node_id, path, depth)
      if depth > DEPTH then return end
      pcall(function()
        view:expand(node_id, "children", { path = path })
      end)
      local node = graph:get(node_id)
      if node then
        local new_path = {}
        for _, p in ipairs(path) do new_path[#new_path + 1] = p end
        new_path[#new_path + 1] = node_id
        new_path[#new_path + 1] = "children"
        for child in node.children:iter() do
          expand_recursive2(child._id, new_path, depth + 1)
        end
      end
    end
    for _, root in ipairs(roots) do
      expand_recursive2(root._id, {}, 1)
    end

    -- Count calls
    local call_count = 0
    local orig = neo.View._expansion_size_at
    neo.View._expansion_size_at = function(self, ...)
      call_count = call_count + 1
      return orig(self, ...)
    end

    local item_count = 0
    for item in view:items() do
      item_count = item_count + 1
    end

    neo.View._expansion_size_at = orig
    view:destroy()

    local calls_per_item = call_count / math.max(1, item_count)
    print(string.format("\n    Deep tree _expansion_size_at calls:"))
    print(string.format("      Visible items: %d", item_count))
    print(string.format("      _expansion_size_at calls: %d", call_count))
    print(string.format("      Calls per item: %.1f", calls_per_item))

    local r = {
      name = "Items deep 10-level",
      iterations = 5,
      elapsed = times[50] * 5,
      per_op = times[50],
    }
    results[#results + 1] = r
  end
  bench_items_scaling_deep()

  --============================================================================
  -- Benchmark 14: _expansion_size_at call count
  --============================================================================
  local function bench_expansion_calls()
    local graph = neo.create(schema)

    -- Create users with posts
    local users = {}
    for i = 1, 20 do
      users[i] = graph:insert("User", { name = "User" .. i, age = 25, active = true })
      for j = 1, 5 do
        local post = graph:insert("Post", { title = "Post" .. j, views = j * 10, published = true, created_at = j })
        users[i].posts:link(post)
      end
    end

    local view = graph:view({
      type = "User",
      edges = { posts = {} },
    }, {
      limit = 50,
    })

    -- Expand all users' posts
    for i = 1, 20 do
      view:expand(users[i]._id, "posts")
    end

    -- Instrument _expansion_size_at
    local call_count = 0
    local orig = neo.View._expansion_size_at
    neo.View._expansion_size_at = function(self, ...)
      call_count = call_count + 1
      return orig(self, ...)
    end

    -- Single iteration
    local item_count = 0
    for item in view:items() do
      item_count = item_count + 1
    end

    -- Restore
    neo.View._expansion_size_at = orig

    local calls_per_item = call_count / math.max(1, item_count)

    print(string.format("\n  _expansion_size_at calls per items():"))
    print(string.format("    Visible items: %d", item_count))
    print(string.format("    _expansion_size_at calls: %d", call_count))
    print(string.format("    Calls per item: %.1f", calls_per_item))

    if calls_per_item > 5 then
      print("    ⚠️  WARNING: Too many _expansion_size_at calls (O(n²) issue)")
    else
      print("    ✓ Call count is reasonable")
    end

    view:destroy()

    local r = {
      name = "_expansion_size_at calls",
      iterations = 1,
      elapsed = 0,
      per_op = calls_per_item,  -- Store calls per item as "time" for comparison
    }
    results[#results + 1] = r
  end
  bench_expansion_calls()

  --============================================================================
  -- Benchmark 14: Deep Tree Traversal
  --============================================================================
  local function bench_deep_tree()
    local graph = neo.create(schema)
    local user = graph:insert("User", { name = "User", age = 25, active = true })
    for i = 1, 10 do
      local post = graph:insert("Post", { title = "Post" .. i, views = i * 10, published = true, created_at = i })
      user.posts:link(post)
      for j = 1, 10 do
        local comment = graph:insert("Comment", { text = "Comment" .. j, created_at = j })
        post.comments:link(comment)
      end
    end

    local view = graph:view({
      type = "User",
      edges = {
        posts = {
          eager = true,
          edges = {
            comments = { eager = true }
          }
        }
      },
    }, {
      limit = 200,
    })

    local r = benchmark("Deep tree collect 100x", 100, function()
      local items = view:collect()
    end)
    results[#results + 1] = r
    view:destroy()
  end
  bench_deep_tree()

  return results
end

local function print_results(results1, results2, name1, name2)
  print("\n" .. string.rep("=", 80))
  print("COMPARISON: " .. name1 .. " vs " .. name2)
  print(string.rep("=", 80))
  print(string.format("%-35s %15s %15s %10s", "Benchmark", name1, name2, "Diff"))
  print(string.rep("-", 80))

  for i, r1 in ipairs(results1) do
    local r2 = results2[i]
    local diff = ((r2.per_op / r1.per_op) - 1) * 100
    local diff_str
    if diff > 0 then
      diff_str = string.format("+%.1f%%", diff)
    else
      diff_str = string.format("%.1f%%", diff)
    end

    print(string.format("%-35s %15s %15s %10s",
      r1.name,
      format_time(r1.per_op),
      format_time(r2.per_op),
      diff_str
    ))
  end

  print(string.rep("=", 80))

  -- Summary
  local total1, total2 = 0, 0
  for i, r1 in ipairs(results1) do
    total1 = total1 + r1.elapsed
    total2 = total2 + results2[i].elapsed
  end

  local overall_diff = ((total2 / total1) - 1) * 100
  print(string.format("\nTotal time: %s vs %s (%.1f%% %s)",
    format_time(total1),
    format_time(total2),
    math.abs(overall_diff),
    overall_diff > 0 and "slower" or "faster"
  ))
end

-- Schema in new flat format for init_2.lua
local flat_schema = {
  User = {
    name = "string",
    age = "number",
    active = "bool",

    posts = { type = "edge", target = "Post", reverse = "author",
      __indexes = {
        { name = "default", fields = {} },
        { name = "by_created", fields = {{ name = "created_at", dir = "desc" }} },
      },
    },
    friends = { type = "edge", target = "User", reverse = "friends",
      __indexes = { { name = "default", fields = {} } },
    },

    post_count = { type = "count", edge = "posts" },
    total_views = { type = "sum", edge = "posts", property = "views" },
    latest_post = { type = "reference", edge = "posts", sort = { field = "created_at", dir = "desc" } },

    __indexes = {
      { name = "default", fields = {{ name = "name" }} },
      { name = "by_age", fields = {{ name = "age", dir = "desc" }} },
    },
  },

  Post = {
    title = "string",
    views = "number",
    published = "bool",
    created_at = "number",

    author = { type = "edge", target = "User", reverse = "posts",
      __indexes = { { name = "default", fields = {} } },
    },
    comments = { type = "edge", target = "Comment", reverse = "post",
      __indexes = { { name = "default", fields = {} } },
    },

    comment_count = { type = "count", edge = "comments" },

    __indexes = {
      { name = "default", fields = {{ name = "title" }} },
      { name = "by_views", fields = {{ name = "views", dir = "desc" }} },
      { name = "by_created", fields = {{ name = "created_at", dir = "desc" }} },
    },
  },

  Comment = {
    text = "string",
    created_at = "number",

    post = { type = "edge", target = "Post", reverse = "comments",
      __indexes = { { name = "default", fields = {} } },
    },

    __indexes = {
      { name = "default", fields = {{ name = "created_at" }} },
    },
  },
}

-- Main
print("\n" .. string.rep("=", 80))
print("NEOGRAPH PERFORMANCE BENCHMARK")
print(string.rep("=", 80))

local neo = dofile('init.lua')
local results = run_benchmarks(neo, "init.lua", flat_schema)

-- Print results
print("\n" .. string.rep("=", 60))
print("Results")
print(string.rep("=", 60))
for _, r in ipairs(results) do
  print(string.format("%-35s %15s", r.name, format_time(r.per_op)))
end
print(string.rep("=", 60))
