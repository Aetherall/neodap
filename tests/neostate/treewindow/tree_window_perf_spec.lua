--[[
  TreeWindow Performance Tests

  This file measures TreeWindow performance on various graph topologies and sizes:
  - Wide trees (many siblings at each level)
  - Deep trees (long chains)
  - Diamond patterns (shared descendants)
  - DAP-like hierarchies (realistic debugging scenario)

  Tests measure:
  - Window creation time
  - Navigation speed (move_up, move_down, move_into, move_out)
  - Collapse/expand reactivity
  - Viewport refresh performance

  Run with: make test treewindow
]]

local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")
local TreeWindow = require("neostate.tree_window")

-- =============================================================================
-- Performance Utilities
-- =============================================================================

local function measure_once(name, fn)
  collectgarbage("collect")
  local start = vim.loop.hrtime()
  local result = fn()
  local elapsed = (vim.loop.hrtime() - start) / 1e6
  print(string.format("\t%s: %.3f ms", name, elapsed))
  return elapsed, result
end

local function measure_avg(name, iterations, fn)
  -- Warmup
  fn()

  collectgarbage("collect")
  local start = vim.loop.hrtime()
  for _ = 1, iterations do
    fn()
  end
  local elapsed = (vim.loop.hrtime() - start) / 1e6
  local avg = elapsed / iterations
  print(string.format("\t%s (%d iter): %.3f ms/iter", name, iterations, avg))
  return avg
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
---@return number entity_count
local function generate_wide_tree(store, width, depth)
  local count = 0

  local root = make_entity("node:root", { name = "root", key = "root", depth = 0 })
  store:add(root, "node")
  count = count + 1

  local function add_children(parent_uri, current_depth)
    if current_depth >= depth then return end

    for i = 1, width do
      local uri = parent_uri .. "/" .. i
      local node = make_entity(uri, {
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
---@return number entity_count
local function generate_deep_tree(store, depth, branch_factor)
  local count = 0

  local root = make_entity("node:0", { name = "root", key = "0", depth = 0 })
  store:add(root, "node")
  count = count + 1

  for d = 1, depth do
    local parent_uri = "node:" .. (d - 1)
    for b = 1, branch_factor do
      local uri = "node:" .. d .. (b > 1 and ("_" .. b) or "")
      local node = make_entity(uri, {
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

describe("TreeWindow Performance", function()
  local store, window

  before_each(function()
    store = EntityStore.new("PerfTestStore")
  end)

  after_each(function()
    if window then
      window:dispose()
      window = nil
    end
    if store then
      store:dispose()
      store = nil
    end
  end)

  -- ===========================================================================
  -- WINDOW CREATION PERFORMANCE
  -- ===========================================================================
  describe("Window Creation", function()
    it("PERF: create window on wide tree (width=10, depth=4, ~11k nodes)", function()
      local entity_count = generate_wide_tree(store, 10, 4)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local elapsed
      elapsed, window = measure_once("Window creation", function()
        return TreeWindow:new(store, "node:root", { edge_type = "child" })
      end)

      -- O(window) implementation: _window_items is windowed view (items is windowed viewport)
      print(string.format("\tDFS collection: %d, viewport: %d", #window._window_items, #window.items._items))
      assert.is_true(elapsed < 1000, "Window creation should complete in under 1 second")
      assert.is_true(#window._window_items > 0, "Window should have items")
    end)

    it("PERF: create window on deep tree (depth=500)", function()
      local entity_count = generate_deep_tree(store, 500, 1)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local elapsed
      elapsed, window = measure_once("Window creation", function()
        return TreeWindow:new(store, "node:0", { edge_type = "child" })
      end)

      print(string.format("\tDFS collection: %d, viewport: %d", #window._window_items, #window.items._items))
      assert.is_true(elapsed < 500, "Deep tree window should create quickly")
      assert.is_true(#window._window_items > 0, "Window should have items")
    end)

    it("PERF: create window on diamond lattice (8 levels, width 5)", function()
      local entity_count = generate_diamond_lattice(store, 8, 5, 0.3)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local elapsed
      elapsed, window = measure_once("Window creation", function()
        return TreeWindow:new(store, "node:root", { edge_type = "child" })
      end)

      -- Diamond creates multiple paths, so more items than entities
      local dfs_count = #window._window_items
      print(string.format("\tDFS collection: %d (path explosion: %.1fx), viewport: %d",
        dfs_count, dfs_count / entity_count, #window.items._items))
      assert.is_true(elapsed < 2000)
    end)

    it("PERF: create window on DAP hierarchy (realistic)", function()
      -- 2 sessions, 4 threads, 10 frames, 3 scopes, 5 vars = 1531 entities
      local entity_count = generate_dap_hierarchy(store, 2, 4, 10, 3, 5)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local elapsed
      elapsed, window = measure_once("Window creation", function()
        return TreeWindow:new(store, "dap:debugger", { edge_type = "child" })
      end)

      print(string.format("\tDFS collection: %d, viewport: %d", #window._window_items, #window.items._items))
      assert.is_true(elapsed < 500, "DAP window should create quickly")
      assert.is_true(#window._window_items > 0, "Window should have items")
    end)

    it("PERF: create window on large DAP hierarchy", function()
      -- 3 sessions, 5 threads, 15 frames, 3 scopes, 8 vars = ~6k entities
      local entity_count = generate_dap_hierarchy(store, 3, 5, 15, 3, 8)
      print(string.format("\n\tGenerated %d entities", entity_count))

      local elapsed
      elapsed, window = measure_once("Window creation", function()
        return TreeWindow:new(store, "dap:debugger", { edge_type = "child" })
      end)

      print(string.format("\tDFS collection: %d, viewport: %d", #window._window_items, #window.items._items))
      assert.is_true(elapsed < 1000, "Large DAP window should create in under 1s")
      assert.is_true(#window._window_items > 0, "Window should have items")
    end)
  end)

  -- ===========================================================================
  -- NAVIGATION PERFORMANCE
  -- ===========================================================================
  describe("Navigation", function()
    it("PERF: move_down on wide tree (1000 iterations)", function()
      generate_wide_tree(store, 10, 3) -- ~1111 nodes
      window = TreeWindow:new(store, "node:root", { edge_type = "child" })
      print(string.format("\n\tDFS collection: %d, viewport: %d", #window._window_items, #window.items._items))

      local avg = measure_avg("move_down", 1000, function()
        window:move_down()
      end)

      assert.is_true(avg < 1, "move_down should be under 1ms per call")
    end)

    it("PERF: move_up on wide tree (1000 iterations)", function()
      generate_wide_tree(store, 10, 3)
      window = TreeWindow:new(store, "node:root", { edge_type = "child" })

      -- Move to end of viewport
      for _ = 1, #window.items._items - 1 do
        window:move_down()
      end

      local avg = measure_avg("move_up", 1000, function()
        window:move_up()
      end)

      assert.is_true(avg < 1, "move_up should be under 1ms per call")
    end)

    it("PERF: move_into on deep tree (100 iterations)", function()
      generate_deep_tree(store, 200, 1)
      window = TreeWindow:new(store, "node:0", { edge_type = "child" })
      print(string.format("\n\tDFS collection: %d", #window._window_items))

      -- move_into involves DFS lookup - measure fewer iterations
      local avg = measure_avg("move_into", 100, function()
        window:move_into()
      end)

      -- move_into can be slower as it searches for first child
      assert.is_true(avg < 10, "move_into should be under 10ms per call")
    end)

    it("PERF: move_out on deep tree (100 iterations)", function()
      generate_deep_tree(store, 200, 1)
      window = TreeWindow:new(store, "node:0", { edge_type = "child" })

      -- Move to middle depth first
      for _ = 1, 100 do
        window:move_into()
      end

      local avg = measure_avg("move_out", 100, function()
        window:move_out()
      end)

      -- move_out can be slower as it parses path
      assert.is_true(avg < 10, "move_out should be under 10ms per call")
    end)

    it("PERF: focus_on random access (100 iterations)", function()
      generate_wide_tree(store, 10, 3)
      window = TreeWindow:new(store, "node:root", { edge_type = "child" })

      -- Collect all vuris from DFS collection
      local vuris = {}
      for _, item in ipairs(window._window_items) do
        table.insert(vuris, item._virtual.uri)
      end

      math.randomseed(42)
      local avg = measure_avg("focus_on (random)", 100, function()
        local idx = math.random(1, #vuris)
        window:focus_on(vuris[idx])
      end)

      assert.is_true(avg < 5, "focus_on should be under 5ms per call")
    end)

    it("PERF: mixed navigation on DAP hierarchy", function()
      generate_dap_hierarchy(store, 2, 4, 10, 3, 5)
      window = TreeWindow:new(store, "dap:debugger", { edge_type = "child" })
      print(string.format("\n\tDFS collection: %d, viewport: %d", #window._window_items, #window.items._items))

      -- Simulate typical DAP navigation pattern (fewer ops for reasonable time)
      local total_time = 0
      local ops = 0

      local function timed(fn)
        local start = vim.loop.hrtime()
        fn()
        total_time = total_time + (vim.loop.hrtime() - start) / 1e6
        ops = ops + 1
      end

      -- Drill down through hierarchy (fewer iterations)
      for _ = 1, 20 do
        timed(function() window:move_into() end)
        timed(function() window:move_down() end)
        timed(function() window:move_down() end)
      end

      -- Navigate back up
      for _ = 1, 20 do
        timed(function() window:move_out() end)
        timed(function() window:move_up() end)
      end

      print(string.format("\t%d navigation ops: %.3f ms total (%.3f ms/op)", ops, total_time, total_time / ops))
      -- Relaxed threshold - move_into/move_out involve DFS lookups
      assert.is_true(total_time / ops < 20, "Average navigation should be under 20ms")
    end)
  end)

  -- ===========================================================================
  -- COLLAPSE/EXPAND PERFORMANCE
  -- ===========================================================================
  describe("Collapse/Expand", function()
    it("PERF: collapse on wide tree", function()
      generate_wide_tree(store, 10, 3)
      window = TreeWindow:new(store, "node:root", { edge_type = "child" })
      local initial_dfs = #window._window_items
      print(string.format("\n\tInitial DFS: %d, viewport: %d", initial_dfs, #window.items._items))

      -- Collapse root
      local elapsed = measure_once("Collapse root", function()
        window:collapse("root")
      end)

      print(string.format("\tAfter collapse: DFS: %d, viewport: %d", #window._window_items, #window.items._items))
      assert.is_true(elapsed < 100, "Collapse should be fast")
      assert.is_true(#window._window_items >= 1, "Window should have at least 1 item") -- Only root in DFS
    end)

    it("PERF: expand on wide tree", function()
      generate_wide_tree(store, 10, 3)
      window = TreeWindow:new(store, "node:root", { edge_type = "child" })
      local initial_dfs = #window._window_items

      -- Collapse then expand
      window:collapse("root")

      local elapsed = measure_once("Expand root", function()
        window:expand("root")
      end)

      print(string.format("\n\tAfter expand: DFS: %d", #window._window_items))
      assert.is_true(elapsed < 500, "Expand should be reasonably fast")
      assert.are.equal(initial_dfs, #window._window_items)
    end)

    it("PERF: collapse multiple nodes in DAP hierarchy", function()
      -- Use smaller hierarchy so all threads fit in window
      -- 2 sessions * 2 threads * 3 frames * 2 scopes * 2 vars = 49 items + 2 sessions + 1 debugger = ~100 items
      generate_dap_hierarchy(store, 2, 2, 3, 2, 2)
      window = TreeWindow:new(store, "dap:debugger", { edge_type = "child", above = 100, below = 100 })
      local initial_dfs = #window._window_items
      print(string.format("\n\tInitial DFS: %d", initial_dfs))

      -- Find all thread vuris from DFS collection
      local thread_vuris = {}
      for _, item in ipairs(window._window_items) do
        local vuri = item._virtual.uri
        if vuri:match("/thread:") and not vuri:match("/frame:") then
          table.insert(thread_vuris, vuri)
        end
      end
      print(string.format("\tFound %d threads to collapse", #thread_vuris))

      -- Collapse all threads
      local elapsed = measure_once("Collapse " .. #thread_vuris .. " threads", function()
        for _, vuri in ipairs(thread_vuris) do
          window:collapse(vuri)
        end
      end)

      print(string.format("\tAfter collapse: DFS: %d", #window._window_items))
      assert.is_true(#window._window_items < initial_dfs)
    end)

    it("PERF: toggle collapse rapidly", function()
      generate_wide_tree(store, 5, 3)
      window = TreeWindow:new(store, "node:root", { edge_type = "child" })

      -- Toggle collapse 100 times
      local avg = measure_avg("toggle collapse", 100, function()
        window:toggle("root")
      end)

      assert.is_true(avg < 50, "Toggle should be reasonably fast")
    end)
  end)

  -- ===========================================================================
  -- REACTIVE UPDATE PERFORMANCE
  -- ===========================================================================
  describe("Reactive Updates", function()
    it("PERF: add nodes reactively", function()
      generate_wide_tree(store, 5, 2)
      window = TreeWindow:new(store, "node:root", { edge_type = "child" })
      local initial_dfs = #window._window_items
      print(string.format("\n\tInitial DFS: %d, viewport: %d", initial_dfs, #window.items._items))

      -- Add 100 new nodes
      local elapsed = measure_once("Add 100 nodes reactively", function()
        for i = 1, 100 do
          local uri = "node:new_" .. i
          local node = make_entity(uri, { name = "new_" .. i, key = "new_" .. i })
          store:add(node, "node", { { type = "child", to = "node:root" } })
        end
      end)

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      print(string.format("\tAfter additions: DFS: %d, viewport: %d", #window._window_items, #window.items._items))
      assert.is_true(#window._window_items > 0, "Window should have items")
      assert.is_true(elapsed < 500, "Reactive additions should be efficient")
    end)

    it("PERF: remove nodes reactively", function()
      generate_wide_tree(store, 5, 2)
      window = TreeWindow:new(store, "node:root", { edge_type = "child" })
      local initial_dfs = #window._window_items
      print(string.format("\n\tInitial DFS: %d, viewport: %d", initial_dfs, #window.items._items))

      -- Remove first level children (cascades to grandchildren)
      local elapsed = measure_once("Remove 5 subtrees reactively", function()
        for i = 1, 5 do
          local uri = "node:root/" .. i
          store:remove_edge(uri, "child", "node:root")
        end
      end)

      -- Wait for debounced refresh
      vim.wait(50, function() return false end)

      print(string.format("\tAfter removals: DFS: %d, viewport: %d", #window._window_items, #window.items._items))
      assert.is_true(#window._window_items >= 1, "Window should have at least 1 item") -- Only root in DFS
      assert.is_true(elapsed < 100, "Reactive removals should be fast")
    end)

    it("PERF: update with window on large collection", function()
      -- Create large flat tree
      local root = make_entity("node:root", { name = "root", key = "root" })
      store:add(root, "node")
      for i = 1, 2000 do
        local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
        store:add(node, "node", { { type = "child", to = "node:root" } })
      end

      window = TreeWindow:new(store, "node:root", { edge_type = "child" })
      print(string.format("\n\tInitial DFS: %d, viewport: %d", #window._window_items, #window.items._items))

      -- Add 200 more nodes
      local elapsed = measure_once("Add 200 nodes to large collection", function()
        for i = 2001, 2200 do
          local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
          store:add(node, "node", { { type = "child", to = "node:root" } })
        end
      end)

      vim.wait(50, function() return false end)

      print(string.format("\tAfter additions: DFS: %d, viewport: %d", #window._window_items, #window.items._items))
      assert.is_true(#window._window_items > 0, "Window should have items")
    end)
  end)

  -- ===========================================================================
  -- LARGE SCALE TESTS
  -- ===========================================================================
  describe("Large Scale (10k entities)", function()
    it("PERF: create 100-item window on 10k flat tree", function()
      -- Create 10k children under root
      local root = make_entity("node:root", { name = "root", key = "root" })
      store:add(root, "node")

      local gen_elapsed = measure_once("Generate 10k entities", function()
        for i = 1, 10000 do
          local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
          store:add(node, "node", { { type = "child", to = "node:root" } })
        end
      end)

      local elapsed
      elapsed, window = measure_once("Create window (100 item viewport)", function()
        return TreeWindow:new(store, "node:root", {
          edge_type = "child",
          above = 50,
          below = 50,
        })
      end)

      print(string.format("\n\tDFS collection: %d, viewport: %d", #window._window_items, #window.items._items))
      assert.is_true(#window._window_items > 0, "Window should have items")
      assert.is_true(#window.items._items <= 101) -- viewport limited
    end)

    it("PERF: navigate 100-item window on 10k flat tree", function()
      -- Create 10k children under root
      local root = make_entity("node:root", { name = "root", key = "root" })
      store:add(root, "node")
      for i = 1, 10000 do
        local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
        store:add(node, "node", { { type = "child", to = "node:root" } })
      end

      window = TreeWindow:new(store, "node:root", {
        edge_type = "child",
        above = 50,
        below = 50,
      })
      print(string.format("\n\tDFS: %d, viewport: %d", #window._window_items, #window.items._items))

      -- Navigate down 1000 times
      local avg = measure_avg("move_down", 1000, function()
        window:move_down()
      end)

      print(string.format("\tFinal focus index: ~%d", window:focus_viewport_index() or 0))
      -- Note: Flat trees with 10k siblings have slower navigation due to correct vuri construction.
      -- This is acceptable since real-world trees (like DAP) are hierarchical, not flat.
      assert.is_true(avg < 5, "move_down should be under 5ms even on 10k flat tree")
    end)

    it("PERF: focus_on random access on 10k tree", function()
      -- Create 10k children under root
      local root = make_entity("node:root", { name = "root", key = "root" })
      store:add(root, "node")
      for i = 1, 10000 do
        local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
        store:add(node, "node", { { type = "child", to = "node:root" } })
      end

      window = TreeWindow:new(store, "node:root", {
        edge_type = "child",
        above = 50,
        below = 50,
      })

      -- Collect sample vuris (every 100th)
      local vuris = {}
      for i, item in ipairs(window._window_items) do
        if i % 100 == 0 then
          table.insert(vuris, item._virtual.uri)
        end
      end
      print(string.format("\n\tSampled %d vuris for random access", #vuris))

      math.randomseed(42)
      local avg = measure_avg("focus_on (random)", 100, function()
        local idx = math.random(1, #vuris)
        window:focus_on(vuris[idx])
      end)

      assert.is_true(avg < 10, "focus_on should be under 10ms on 10k tree")
    end)

    it("PERF: reactive add on 10k tree with window", function()
      -- Create 10k children under root
      local root = make_entity("node:root", { name = "root", key = "root" })
      store:add(root, "node")
      for i = 1, 10000 do
        local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
        store:add(node, "node", { { type = "child", to = "node:root" } })
      end

      window = TreeWindow:new(store, "node:root", {
        edge_type = "child",
        above = 50,
        below = 50,
      })
      print(string.format("\n\tInitial DFS: %d", #window._window_items))

      -- Add 100 more nodes
      local elapsed = measure_once("Add 100 nodes to 10k tree", function()
        for i = 10001, 10100 do
          local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
          store:add(node, "node", { { type = "child", to = "node:root" } })
        end
      end)

      vim.wait(50, function() return false end)

      print(string.format("\tAfter additions: DFS: %d", #window._window_items))
      assert.is_true(#window._window_items > 0, "Window should have items")
    end)
  end)

  -- ===========================================================================
  -- SCALING TESTS
  -- ===========================================================================
  describe("Scaling", function()
    it("PERF: window creation scaling with size", function()
      local sizes = { 100, 500, 1000, 2000 }
      local times = {}

      for _, size in ipairs(sizes) do
        -- Clean up previous
        if window then window:dispose() end
        if store then store:dispose() end

        store = EntityStore.new("ScaleTest")
        local root = make_entity("node:root", { name = "root", key = "root" })
        store:add(root, "node")
        for i = 1, size do
          local node = make_entity("node:" .. i, { name = "n" .. i, key = tostring(i) })
          store:add(node, "node", { { type = "child", to = "node:root" } })
        end

        local elapsed
        elapsed, window = measure_once("Create window (" .. size .. " nodes)", function()
          return TreeWindow:new(store, "node:root", { edge_type = "child" })
        end)

        table.insert(times, { size = size, time = elapsed })
      end

      -- Print scaling summary
      print("\n\tScaling summary:")
      for i = 2, #times do
        local ratio = times[i].time / times[i - 1].time
        local size_ratio = times[i].size / times[i - 1].size
        print(string.format("\t  %d -> %d nodes: %.2fx time (%.2fx size)",
          times[i - 1].size, times[i].size, ratio, size_ratio))
      end
    end)

    it("PERF: navigation scaling with depth", function()
      local depths = { 50, 100, 200, 500 }

      for _, depth in ipairs(depths) do
        if window then window:dispose() end
        if store then store:dispose() end

        store = EntityStore.new("DepthTest")
        generate_deep_tree(store, depth, 1)
        window = TreeWindow:new(store, "node:0", { edge_type = "child" })

        -- Time 100 move_down operations
        local start = vim.loop.hrtime()
        for _ = 1, 100 do
          window:move_down()
        end
        local elapsed = (vim.loop.hrtime() - start) / 1e6

        print(string.format("\n\tDepth %d: 100 move_down in %.3f ms (%.3f ms/op)",
          depth, elapsed, elapsed / 100))
      end
    end)
  end)
end)
