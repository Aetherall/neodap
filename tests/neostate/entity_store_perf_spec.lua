--[[
  EntityStore Performance Tests

  This file measures performance on large graphs with various topologies:
  - Wide trees (many siblings at each level)
  - Deep trees (long chains)
  - Diamond patterns (shared descendants)
  - Dense graphs (high edge connectivity)
  - Random graphs

  Tests measure:
  - Initial BFS/DFS traversal time
  - Reactive edge addition
  - Reactive entity addition
  - Prune/unprune reactivity
  - Filter reactivity
  - Memory efficiency (entity count vs wrapper count)

  Run with: make test neostate
  Or: nvim --headless -u tests/helpers/minimal_init.lua -c "PlenaryBustedFile tests/neostate/entity_store_perf_spec.lua"
]]

local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")

-- =============================================================================
-- Performance Utilities
-- =============================================================================

local function measure(name, iterations, fn)
  -- Warmup
  fn()

  local start = vim.loop.hrtime()
  for _ = 1, iterations do
    fn()
  end
  local elapsed = (vim.loop.hrtime() - start) / 1e6 -- Convert to ms

  local avg = elapsed / iterations
  print(string.format("\t%s (%d iterations): %.3f ms/iter", name, iterations, avg))
  return avg
end

local function measure_once(name, fn)
  collectgarbage("collect")
  local start = vim.loop.hrtime()
  local result = fn()
  local elapsed = (vim.loop.hrtime() - start) / 1e6
  print(string.format("\t%s: %.3f ms", name, elapsed))
  return elapsed, result
end

-- =============================================================================
-- Graph Generators
-- =============================================================================

local function make_entity(uri, props)
  local entity = neostate.Disposable(props or {}, nil, uri)
  entity.uri = uri
  return entity
end

local function make_collapsible(uri, props)
  local entity = make_entity(uri, props)
  entity.collapsed = neostate.Signal(false, uri .. ":collapsed")
  entity.collapsed:set_parent(entity)
  return entity
end

---Generate a wide tree: root with many children, each with some grandchildren
---@param store table EntityStore
---@param width number Children per node
---@param depth number Tree depth
---@param collapsible boolean Whether nodes are collapsible
---@return number entity_count
local function generate_wide_tree(store, width, depth, collapsible)
  local count = 0
  local make = collapsible and make_collapsible or make_entity

  local root = make("node:root", { name = "root", key = "root", depth = 0 })
  store:add(root, "node")
  count = count + 1

  local function add_children(parent_uri, current_depth)
    if current_depth >= depth then return end

    for i = 1, width do
      local uri = parent_uri .. "/" .. i
      local node = make(uri, {
        name = "node_" .. current_depth .. "_" .. i,
        key = tostring(i),
        depth = current_depth,
      })
      store:add(node, "node", { { type = "child", to = parent_uri } })
      count = count + 1
      add_children(uri, current_depth + 1)
    end
  end

  add_children("node:root", 1)
  return count
end

---Generate a deep tree: linear chain with optional branching
---@param store table EntityStore
---@param depth number Chain depth
---@param branch_factor number Branches at each level (1 = pure chain)
---@param collapsible boolean Whether nodes are collapsible
---@return number entity_count
local function generate_deep_tree(store, depth, branch_factor, collapsible)
  local count = 0
  local make = collapsible and make_collapsible or make_entity

  local root = make("node:0", { name = "root", key = "0", depth = 0 })
  store:add(root, "node")
  count = count + 1

  for d = 1, depth do
    local parent_uri = "node:" .. (d - 1)
    for b = 1, branch_factor do
      local uri = "node:" .. d .. (b > 1 and ("_" .. b) or "")
      local node = make(uri, {
        name = "node_" .. d,
        key = tostring(d) .. (b > 1 and ("_" .. b) or ""),
        depth = d,
      })
      store:add(node, "node", { { type = "child", to = parent_uri } })
      count = count + 1
    end
  end

  return count
end

---Generate a diamond lattice: creates many paths to shared nodes
---@param store table EntityStore
---@param levels number Number of levels
---@param width number Width of each level
---@param connect_ratio number? Ratio of parents to connect (0-1, default 1.0 = all)
---@return number entity_count
local function generate_diamond_lattice(store, levels, width, connect_ratio)
  connect_ratio = connect_ratio or 1.0
  local count = 0

  -- Root
  local root = make_entity("node:root", { name = "root", key = "root" })
  store:add(root, "node")
  count = count + 1

  local prev_level = { "node:root" }

  for level = 1, levels do
    local current_level = {}
    for i = 1, width do
      local uri = "node:L" .. level .. "_" .. i
      local node = make_entity(uri, {
        name = "L" .. level .. "_" .. i,
        key = "L" .. level .. "_" .. i,
      })

      -- Connect to subset of parents from previous level (controlled diamond)
      local edges = {}
      local connect_count = math.max(1, math.floor(#prev_level * connect_ratio))
      for j = 1, connect_count do
        local parent_idx = ((i + j - 2) % #prev_level) + 1
        table.insert(edges, { type = "child", to = prev_level[parent_idx] })
      end

      store:add(node, "node", edges)
      count = count + 1
      table.insert(current_level, uri)
    end
    prev_level = current_level
  end

  return count
end

---Generate a random graph with specified density
---@param store table EntityStore
---@param node_count number Number of nodes
---@param edge_probability number Probability of edge between any two nodes (0-1)
---@return number entity_count, number edge_count
local function generate_random_graph(store, node_count, edge_probability)
  local count = 0
  local edge_count = 0

  -- Create all nodes first
  for i = 1, node_count do
    local uri = "node:" .. i
    local node = make_entity(uri, { name = "node_" .. i, key = tostring(i) })
    store:add(node, "node")
    count = count + 1
  end

  -- Add random edges (avoiding cycles by only going forward)
  for i = 1, node_count do
    for j = i + 1, node_count do
      if math.random() < edge_probability then
        store:add_edge("node:" .. j, "child", "node:" .. i)
        edge_count = edge_count + 1
      end
    end
  end

  return count, edge_count
end

---Generate a DAP-like hierarchy
---@param store table EntityStore
---@param sessions number Number of sessions
---@param threads_per_session number Threads per session
---@param frames_per_thread number Frames per thread
---@param scopes_per_frame number Scopes per frame
---@param vars_per_scope number Variables per scope
---@return number entity_count
local function generate_dap_hierarchy(store, sessions, threads_per_session, frames_per_thread, scopes_per_frame, vars_per_scope)
  local count = 0

  -- Debugger root
  local debugger = make_collapsible("dap:debugger", { name = "Debugger", key = "debugger" })
  store:add(debugger, "debugger")
  count = count + 1

  for s = 1, sessions do
    local session_uri = "dap:session:" .. s
    local session = make_collapsible(session_uri, {
      name = "Session " .. s,
      key = "session:" .. s,
    })
    store:add(session, "session", { { type = "child", to = "dap:debugger" } })
    count = count + 1

    for t = 1, threads_per_session do
      local thread_uri = session_uri .. "/thread:" .. t
      local thread = make_collapsible(thread_uri, {
        name = "Thread " .. t,
        key = "thread:" .. t,
      })
      thread.state = neostate.Signal("stopped", thread_uri .. ":state")
      thread.state:set_parent(thread)
      store:add(thread, "thread", { { type = "child", to = session_uri } })
      count = count + 1

      for f = 1, frames_per_thread do
        local frame_uri = thread_uri .. "/frame:" .. f
        local frame = make_collapsible(frame_uri, {
          name = "Frame " .. f,
          key = "frame:" .. f,
        })
        store:add(frame, "frame", { { type = "child", to = thread_uri } })
        count = count + 1

        for sc = 1, scopes_per_frame do
          local scope_uri = frame_uri .. "/scope:" .. sc
          local scope = make_collapsible(scope_uri, {
            name = "Scope " .. sc,
            key = "scope:" .. sc,
          })
          store:add(scope, "scope", { { type = "child", to = frame_uri } })
          count = count + 1

          for v = 1, vars_per_scope do
            local var_uri = scope_uri .. "/var:" .. v
            local var = make_collapsible(var_uri, {
              name = "var_" .. v,
              value = tostring(v),
              key = "var:" .. v,
            })
            store:add(var, "variable", { { type = "child", to = scope_uri } })
            count = count + 1
          end
        end
      end
    end
  end

  return count
end

-- =============================================================================
-- Performance Tests
-- =============================================================================

describe("EntityStore Performance", function()
  local store

  before_each(function()
    store = EntityStore.new("PerfTestStore")
  end)

  after_each(function()
    if store then
      store:dispose()
    end
  end)

  -- ===========================================================================
  -- WIDE TREE PERFORMANCE
  -- ===========================================================================
  describe("Wide Tree", function()
    it("PERF: BFS on wide tree (width=10, depth=4, ~11k nodes)", function()
      local entity_count = generate_wide_tree(store, 10, 4, false)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local collection
      local elapsed = measure_once("Initial BFS traversal", function()
        collection = store:bfs("node:root", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      assert.are.equal(entity_count, #collection._items)
      assert.is_true(elapsed < 1000, "BFS should complete in under 1 second")
    end)

    it("PERF: DFS on wide tree (width=10, depth=4, ~11k nodes)", function()
      local entity_count = generate_wide_tree(store, 10, 4, false)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local collection
      local elapsed = measure_once("Initial DFS traversal", function()
        collection = store:dfs("node:root", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      assert.are.equal(entity_count, #collection._items)
      assert.is_true(elapsed < 1000, "DFS should complete in under 1 second")
    end)

    it("PERF: reactive edge addition on wide tree", function()
      generate_wide_tree(store, 10, 3, false)

      local collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
      })

      local initial_count = #collection._items
      print(string.format("\n\tInitial collection size: %d", initial_count))

      -- Add 100 new edges
      local elapsed = measure_once("Adding 100 edges reactively", function()
        for i = 1, 100 do
          local new_uri = "node:new_" .. i
          local node = make_entity(new_uri, { name = "new_" .. i, key = "new_" .. i })
          store:add(node, "node", { { type = "child", to = "node:root" } })
        end
      end)

      assert.are.equal(initial_count + 100, #collection._items)
      assert.is_true(elapsed < 500, "Adding 100 edges should take under 500ms")
    end)
  end)

  -- ===========================================================================
  -- DEEP TREE PERFORMANCE
  -- ===========================================================================
  describe("Deep Tree", function()
    it("PERF: BFS on deep tree (depth=1000, pure chain)", function()
      local entity_count = generate_deep_tree(store, 1000, 1, false)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local collection
      local elapsed = measure_once("Initial BFS traversal", function()
        collection = store:bfs("node:0", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      assert.are.equal(entity_count, #collection._items)
      assert.is_true(elapsed < 500, "BFS on deep chain should complete quickly")
    end)

    it("PERF: DFS on deep tree (depth=1000, pure chain)", function()
      local entity_count = generate_deep_tree(store, 1000, 1, false)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local collection
      local elapsed = measure_once("Initial DFS traversal", function()
        collection = store:dfs("node:0", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      assert.are.equal(entity_count, #collection._items)
      assert.is_true(elapsed < 500, "DFS on deep chain should complete quickly")
    end)

    it("PERF: path tracking on deep tree", function()
      generate_deep_tree(store, 500, 1, false)

      local collection
      local elapsed = measure_once("BFS with path tracking", function()
        collection = store:bfs("node:0", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      -- Verify path length grows correctly
      local deepest = collection._items[#collection._items]
      assert.are.equal(500, deepest._virtual.depth)
      assert.are.equal(500, #deepest._virtual.path)
    end)
  end)

  -- ===========================================================================
  -- DIAMOND LATTICE PERFORMANCE (path explosion)
  -- ===========================================================================
  describe("Diamond Lattice", function()
    it("PERF: BFS on small diamond (5 levels, width 3, 50% connect)", function()
      -- Use 50% connection ratio to limit path explosion
      local entity_count = generate_diamond_lattice(store, 5, 3, 0.5)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local collection
      local elapsed = measure_once("Initial BFS traversal", function()
        collection = store:bfs("node:root", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      -- With diamonds, we get more wrappers than entities due to multiple paths
      print(string.format("\tCollection size: %d (path explosion: %.1fx)",
        #collection._items, #collection._items / entity_count))

      assert.is_true(#collection._items >= entity_count, "Should have at least as many wrappers as entities")
    end)

    it("PERF: BFS on medium diamond (8 levels, width 5, 30% connect)", function()
      -- Limited connection ratio prevents exponential explosion
      local entity_count = generate_diamond_lattice(store, 8, 5, 0.3)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local collection
      local elapsed = measure_once("Initial BFS traversal", function()
        collection = store:bfs("node:root", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      print(string.format("\tCollection size: %d (path explosion: %.1fx)",
        #collection._items, #collection._items / entity_count))
      assert.is_true(elapsed < 2000, "Diamond BFS should complete in reasonable time")
    end)

    it("PERF: full diamond with max_depth limit", function()
      -- Full connectivity but depth-limited
      local entity_count = generate_diamond_lattice(store, 6, 4, 1.0)
      print(string.format("\n\tGenerated %d entities (full connectivity)", entity_count))

      local collection
      local elapsed = measure_once("BFS with max_depth=4", function()
        collection = store:bfs("node:root", {
          direction = "in",
          edge_types = { "child" },
          max_depth = 4,
        })
        return collection
      end)

      print(string.format("\tCollection size (depth<=4): %d", #collection._items))
      assert.is_true(elapsed < 1000)
    end)
  end)

  -- ===========================================================================
  -- RANDOM GRAPH PERFORMANCE
  -- ===========================================================================
  describe("Random Graph", function()
    it("PERF: BFS on sparse random graph (500 nodes, 2% edges)", function()
      math.randomseed(42) -- Reproducible
      local node_count, edge_count = generate_random_graph(store, 500, 0.02)
      print(string.format("\n\tGenerated %d nodes, %d edges", node_count, edge_count))

      local collection
      local elapsed = measure_once("Initial BFS from node 1 (max_depth=6)", function()
        collection = store:bfs("node:1", {
          direction = "in",
          edge_types = { "child" },
          max_depth = 6,
        })
        return collection
      end)

      print(string.format("\tReachable paths: %d", #collection._items))
      assert.is_true(elapsed < 1000)
    end)

    it("PERF: BFS on medium random graph (300 nodes, 5% edges)", function()
      math.randomseed(42)
      local node_count, edge_count = generate_random_graph(store, 300, 0.05)
      print(string.format("\n\tGenerated %d nodes, %d edges", node_count, edge_count))

      local collection
      local elapsed = measure_once("Initial BFS from node 1 (max_depth=4)", function()
        collection = store:bfs("node:1", {
          direction = "in",
          edge_types = { "child" },
          max_depth = 4,
        })
        return collection
      end)

      print(string.format("\tReachable paths (depth <= 4): %d", #collection._items))
      assert.is_true(elapsed < 1000)
    end)

    it("PERF: DFS on random graph for comparison", function()
      math.randomseed(42)
      local node_count, edge_count = generate_random_graph(store, 300, 0.03)
      print(string.format("\n\tGenerated %d nodes, %d edges", node_count, edge_count))

      local bfs_collection, dfs_collection

      local bfs_elapsed = measure_once("BFS (max_depth=5)", function()
        bfs_collection = store:bfs("node:1", {
          direction = "in",
          edge_types = { "child" },
          max_depth = 5,
        })
        return bfs_collection
      end)

      -- Recreate store for fair DFS comparison
      store:dispose()
      store = EntityStore.new("PerfTestStore")
      math.randomseed(42)
      generate_random_graph(store, 300, 0.03)

      local dfs_elapsed = measure_once("DFS (max_depth=5)", function()
        dfs_collection = store:dfs("node:1", {
          direction = "in",
          edge_types = { "child" },
          max_depth = 5,
        })
        return dfs_collection
      end)

      print(string.format("\tBFS: %d paths, DFS: %d paths", #bfs_collection._items, #dfs_collection._items))
    end)
  end)

  -- ===========================================================================
  -- DAP-LIKE HIERARCHY PERFORMANCE
  -- ===========================================================================
  describe("DAP Hierarchy", function()
    it("PERF: BFS on realistic DAP structure", function()
      -- 2 sessions, 4 threads each, 10 frames, 3 scopes, 5 vars
      -- Total: 1 + 2 + 8 + 80 + 240 + 1200 = 1531 entities
      local entity_count = generate_dap_hierarchy(store, 2, 4, 10, 3, 5)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local collection
      local elapsed = measure_once("Initial BFS traversal", function()
        collection = store:bfs("dap:debugger", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      assert.are.equal(entity_count, #collection._items)
      assert.is_true(elapsed < 500, "DAP BFS should complete quickly")
    end)

    it("PERF: collapse/uncollapse reactivity", function()
      -- Smaller hierarchy for reactivity test
      generate_dap_hierarchy(store, 2, 4, 5, 2, 3)

      local collection = store:bfs("dap:debugger", {
        direction = "in",
        edge_types = { "child" },
        prune = function(entity)
          return entity.collapsed and entity.collapsed:get()
        end,
        prune_watch = function(entity)
          return entity.collapsed
        end,
      })

      local initial_count = #collection._items
      print(string.format("\n\tInitial collection size: %d", initial_count))

      -- Collapse all threads (should hide frames, scopes, vars)
      local threads = {}
      for _, item in ipairs(collection._items) do
        if item.uri and item.uri:match("thread:") and not item.uri:match("frame:") then
          table.insert(threads, item)
        end
      end

      local elapsed = measure_once("Collapsing " .. #threads .. " threads", function()
        for _, thread in ipairs(threads) do
          thread.collapsed:set(true)
        end
      end)

      local collapsed_count = #collection._items
      print(string.format("\tAfter collapse: %d items (removed %d)", collapsed_count, initial_count - collapsed_count))

      -- Uncollapse all
      local elapsed2 = measure_once("Uncollapsing " .. #threads .. " threads", function()
        for _, thread in ipairs(threads) do
          thread.collapsed:set(false)
        end
      end)

      assert.are.equal(initial_count, #collection._items)
    end)

    it("PERF: filter reactivity with state changes", function()
      generate_dap_hierarchy(store, 2, 3, 5, 2, 3)

      -- Track threads for state changes
      local threads = {}
      for uri, entity in pairs(store._entities) do
        if uri:match("thread:") and not uri:match("frame:") then
          table.insert(threads, entity)
        end
      end

      -- Set half the threads to running initially
      for i, thread in ipairs(threads) do
        if i % 2 == 0 then
          thread.state:set("running")
        end
      end

      local collection = store:bfs("dap:debugger", {
        direction = "in",
        edge_types = { "child" },
        filter = function(entity)
          if entity.state then
            return entity.state:get() == "stopped"
          end
          return true
        end,
        filter_watch = function(entity)
          return entity.state
        end,
        prune = function(entity)
          if entity.state then
            return entity.state:get() == "running"
          end
          return false
        end,
        prune_watch = function(entity)
          return entity.state
        end,
      })

      local initial_count = #collection._items
      print(string.format("\n\tInitial (half running): %d items", initial_count))

      -- Stop all running threads
      local running_count = 0
      for i, thread in ipairs(threads) do
        if i % 2 == 0 then running_count = running_count + 1 end
      end

      local elapsed = measure_once("Stopping " .. running_count .. " threads", function()
        for i, thread in ipairs(threads) do
          if i % 2 == 0 then
            thread.state:set("stopped")
          end
        end
      end)

      local after_stop = #collection._items
      print(string.format("\tAfter stopping all: %d items", after_stop))

      assert.is_true(after_stop > initial_count)
    end)

    it("PERF: large DAP hierarchy BFS", function()
      -- Larger test: 3 sessions, 5 threads, 15 frames, 3 scopes, 8 vars
      -- Total: 1 + 3 + 15 + 225 + 675 + 5400 = 6319 entities
      local entity_count = generate_dap_hierarchy(store, 3, 5, 15, 3, 8)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local collection
      local elapsed = measure_once("Initial BFS traversal", function()
        collection = store:bfs("dap:debugger", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      assert.are.equal(entity_count, #collection._items)
      assert.is_true(elapsed < 1000, "Large DAP BFS should complete in under 1s")
    end)
  end)

  -- ===========================================================================
  -- MEMORY AND SCALE TESTS
  -- ===========================================================================
  describe("Scale Tests", function()
    it("PERF: very large flat tree (10k children)", function()
      local root = make_entity("node:root", { name = "root", key = "root" })
      store:add(root, "node")

      local elapsed = measure_once("Adding 10000 children", function()
        for i = 1, 10000 do
          local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
          store:add(node, "node", { { type = "child", to = "node:root" } })
        end
      end)

      print(string.format("\n\tAdded 10000 children in %.1f ms", elapsed))

      local collection
      elapsed = measure_once("BFS traversal of 10001 nodes", function()
        collection = store:bfs("node:root", {
          direction = "in",
          edge_types = { "child" },
        })
        return collection
      end)

      assert.are.equal(10001, #collection._items)
    end)

    it("PERF: reactive additions to large collection", function()
      local root = make_entity("node:root", { name = "root", key = "root" })
      store:add(root, "node")

      -- Pre-populate with 2000 nodes
      for i = 1, 2000 do
        local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
        store:add(node, "node", { { type = "child", to = "node:root" } })
      end

      local collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
      })

      assert.are.equal(2001, #collection._items)
      print(string.format("\n\tInitial collection: 2001 items"))

      -- Measure time to add 500 more reactively
      local elapsed = measure_once("Adding 500 more reactively", function()
        for i = 2001, 2500 do
          local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
          store:add(node, "node", { { type = "child", to = "node:root" } })
        end
      end)

      assert.are.equal(2501, #collection._items)
      -- Note: Reactive additions scale linearly with collection size
      -- This is a known characteristic of the current implementation
      assert.is_true(elapsed < 500, "Reactive additions should be reasonably efficient")
    end)

    it("PERF: reactive additions scaling (measures overhead)", function()
      -- This test documents the scaling behavior of reactive additions
      local root = make_entity("node:root", { name = "root", key = "root" })
      store:add(root, "node")

      local collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
      })

      -- Measure time to add batches of 100 nodes
      local batch_times = {}
      for batch = 1, 5 do
        local start_i = (batch - 1) * 500 + 1
        local end_i = batch * 500

        local start = vim.loop.hrtime()
        for i = start_i, end_i do
          local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
          store:add(node, "node", { { type = "child", to = "node:root" } })
        end
        local elapsed = (vim.loop.hrtime() - start) / 1e6

        table.insert(batch_times, elapsed)
        print(string.format("\n\tBatch %d (items %d-%d): %.1f ms, collection size: %d",
          batch, start_i, end_i, elapsed, #collection._items))
      end

      -- Final collection should have root + 2500 nodes
      assert.are.equal(2501, #collection._items)

      -- Document scaling: later batches should take roughly similar time if O(1) per add
      -- or increase linearly if O(n) per add
      local ratio = batch_times[5] / batch_times[1]
      print(string.format("\tScaling ratio (batch5/batch1): %.2fx", ratio))
    end)

    it("PERF: edge removal cascade", function()
      -- Create a tree where removing root's edges cascades to many nodes
      generate_wide_tree(store, 5, 4, false) -- ~781 nodes

      local collection = store:bfs("node:root", {
        direction = "in",
        edge_types = { "child" },
      })

      local initial = #collection._items
      print(string.format("\n\tInitial collection: %d items", initial))

      -- Remove edges from root to all direct children
      local elapsed = measure_once("Removing edges to 5 children (cascades)", function()
        for i = 1, 5 do
          store:remove_edge("node:root/" .. i, "child", "node:root")
        end
      end)

      -- Only root should remain
      assert.are.equal(1, #collection._items)
      print(string.format("\tAfter cascade removal: %d items", #collection._items))
    end)
  end)

  -- ===========================================================================
  -- COMPARISON: BFS vs DFS
  -- ===========================================================================
  describe("BFS vs DFS Comparison", function()
    it("PERF: compare BFS and DFS on same graph", function()
      generate_wide_tree(store, 8, 4, false) -- ~4681 nodes
      print("\n")

      local bfs_collection, dfs_collection

      local bfs_time = measure_once("BFS traversal", function()
        bfs_collection = store:bfs("node:root", {
          direction = "in",
          edge_types = { "child" },
        })
        return bfs_collection
      end)

      local dfs_time = measure_once("DFS traversal", function()
        dfs_collection = store:dfs("node:root", {
          direction = "in",
          edge_types = { "child" },
        })
        return dfs_collection
      end)

      assert.are.equal(#bfs_collection._items, #dfs_collection._items)
      print(string.format("\tBoth traversed %d items", #bfs_collection._items))
      print(string.format("\tBFS/DFS ratio: %.2f", bfs_time / dfs_time))
    end)
  end)

  -- ===========================================================================
  -- WITH FILTER AND PRUNE
  -- ===========================================================================
  describe("Filter and Prune Performance", function()
    it("PERF: BFS with filter (no prune)", function()
      generate_wide_tree(store, 8, 4, false)

      local collection
      local elapsed = measure_once("BFS with 50% filter", function()
        local count = 0
        collection = store:bfs("node:root", {
          direction = "in",
          edge_types = { "child" },
          filter = function(entity)
            count = count + 1
            return count % 2 == 0 -- Filter out half
          end,
        })
        return collection
      end)

      print(string.format("\n\tFiltered collection: %d items", #collection._items))
    end)

    it("PERF: BFS with prune (early termination)", function()
      generate_wide_tree(store, 8, 4, true) -- Collapsible nodes

      -- Collapse half the first-level children
      for i = 1, 4 do
        local uri = "node:root/" .. i
        local entity = store._entities[uri]
        if entity then
          entity.collapsed:set(true)
        end
      end

      local collection
      local elapsed = measure_once("BFS with prune", function()
        collection = store:bfs("node:root", {
          direction = "in",
          edge_types = { "child" },
          prune = function(entity)
            return entity.collapsed and entity.collapsed:get()
          end,
        })
        return collection
      end)

      print(string.format("\n\tPruned collection: %d items (vs ~4681 unpruned)", #collection._items))
      assert.is_true(#collection._items < 4681)
    end)

    it("PERF: BFS with both filter and prune", function()
      generate_wide_tree(store, 8, 4, true)

      -- Collapse some nodes
      for i = 1, 4 do
        local uri = "node:root/" .. i
        local entity = store._entities[uri]
        if entity then
          entity.collapsed:set(true)
        end
      end

      local collection
      local elapsed = measure_once("BFS with filter + prune", function()
        local count = 0
        collection = store:bfs("node:root", {
          direction = "in",
          edge_types = { "child" },
          filter = function(entity)
            count = count + 1
            return count % 2 == 0
          end,
          prune = function(entity)
            return entity.collapsed and entity.collapsed:get()
          end,
        })
        return collection
      end)

      print(string.format("\n\tFiltered + pruned collection: %d items", #collection._items))
    end)
  end)
end)
