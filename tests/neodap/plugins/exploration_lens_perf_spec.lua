--[[
  ExplorationLens Performance Tests

  This file measures ExplorationLens performance across various scenarios:
  - Pattern syncing from window state
  - Burn mechanism (materializing pattern to old context)
  - Transpose mechanism (applying pattern to new context)
  - Context change overhead (full cycle)
  - Graceful degradation with missing paths
  - Scaling with tree size and pattern complexity

  Run with: make test plugins
]]

local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")
local TreeWindow = require("neostate.tree_window")
local ExplorationLens = require("neodap.lib.exploration_lens")

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
-- DAP-like Hierarchy Generator
-- =============================================================================

---Generate a DAP-like hierarchy with frames as contexts
---@param store table EntityStore
---@param stacks number Number of stacks (context switches)
---@param frames_per_stack number Frames per stack
---@param scopes_per_frame number Scopes per frame
---@param vars_per_scope number Variables per scope
---@return table { root: string, frames: string[], scopes: table<string, string[]> }
local function generate_dap_tree(store, stacks, frames_per_stack, scopes_per_frame, vars_per_scope)
  local frames = {}
  local scopes = {}

  -- Root
  store:add({ uri = "root", key = "Debugger", name = "Debugger" }, "root")

  -- Session
  store:add({ uri = "session:1", key = "session:1", name = "Session 1" }, "session",
    { { type = "parent", to = "root" } })

  -- Thread
  store:add({ uri = "thread:1", key = "thread:1", name = "Thread 1" }, "thread",
    { { type = "parent", to = "session:1" } })

  -- Stacks with frames
  for s = 1, stacks do
    local stack_uri = "stack:" .. s
    store:add({ uri = stack_uri, key = "stack:" .. s, name = "Stack " .. s }, "stack",
      { { type = "parent", to = "thread:1" } })

    for f = 1, frames_per_stack do
      local frame_uri = stack_uri .. "/frame:" .. f
      store:add({
        uri = frame_uri,
        key = "frame:" .. f,
        name = "frame_" .. f,
        _type = "frame"
      }, "frame", { { type = "parent", to = stack_uri } })
      table.insert(frames, frame_uri)

      scopes[frame_uri] = {}

      for sc = 1, scopes_per_frame do
        local scope_name = sc == 1 and "Locals" or (sc == 2 and "Globals" or "Scope" .. sc)
        local scope_uri = frame_uri .. "/" .. scope_name
        store:add({
          uri = scope_uri,
          key = scope_name,
          name = scope_name,
          _type = "scope"
        }, "scope", { { type = "parent", to = frame_uri } })
        table.insert(scopes[frame_uri], scope_uri)

        for v = 1, vars_per_scope do
          local var_uri = scope_uri .. "/var" .. v
          store:add({
            uri = var_uri,
            key = "var" .. v,
            name = "var" .. v,
            value = tostring(v),
            _type = "variable"
          }, "variable", { { type = "parent", to = scope_uri } })
        end
      end
    end
  end

  return {
    root = "root",
    frames = frames,
    scopes = scopes,
  }
end

-- =============================================================================
-- Performance Tests
-- =============================================================================

describe("ExplorationLens Performance", function()
  local store, window, lens, context_signal

  local function cleanup()
    if lens then
      lens:dispose()
      lens = nil
    end
    if window then
      window:dispose()
      window = nil
    end
    if context_signal then
      context_signal:dispose()
      context_signal = nil
    end
    if store then
      store:dispose()
      store = nil
    end
  end

  after_each(cleanup)

  -- ===========================================================================
  -- LENS CREATION PERFORMANCE
  -- ===========================================================================
  describe("Lens Creation", function()
    it("PERF: create lens on small DAP tree", function()
      store = EntityStore.new("perf-small")
      local tree = generate_dap_tree(store, 3, 5, 3, 5) -- 3 stacks, 5 frames, 3 scopes, 5 vars
      print(string.format("\n\tGenerated %d frames", #tree.frames))

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 50,
        below = 50,
      })
      print(string.format("\tWindow items: %d", #window._window_items))

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)

      local elapsed
      elapsed, lens = measure_once("Lens creation", function()
        return ExplorationLens:new(window, context_signal)
      end)

      assert.is_true(elapsed < 50, "Lens creation should be under 50ms")
      assert.is_not_nil(lens)
    end)

    it("PERF: create lens on large DAP tree", function()
      store = EntityStore.new("perf-large")
      local tree = generate_dap_tree(store, 10, 10, 3, 10) -- 10 stacks, 10 frames, 3 scopes, 10 vars
      print(string.format("\n\tGenerated %d frames", #tree.frames))

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })
      print(string.format("\tWindow items: %d", #window._window_items))

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)

      local elapsed
      elapsed, lens = measure_once("Lens creation", function()
        return ExplorationLens:new(window, context_signal)
      end)

      assert.is_true(elapsed < 100, "Lens creation should be under 100ms on large tree")
      assert.is_not_nil(lens)
    end)
  end)

  -- ===========================================================================
  -- PATTERN SYNCING PERFORMANCE
  -- ===========================================================================
  describe("Pattern Syncing", function()
    it("PERF: sync pattern with few expansions", function()
      store = EntityStore.new("perf-sync-small")
      local tree = generate_dap_tree(store, 5, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Expand a few nodes
      local frame_vuri = lens.context_vuri
      window:expand(frame_vuri)
      for _, scope_uri in ipairs(tree.scopes[tree.frames[1]] or {}) do
        local scope = store:get(scope_uri)
        if scope then
          window:expand(frame_vuri .. "/" .. scope.key)
        end
      end

      local avg = measure_avg("Sync pattern (3 expansions)", 100, function()
        lens:_sync_pattern_from_window()
      end)

      assert.is_true(avg < 5, "Pattern sync should be under 5ms")
    end)

    it("PERF: sync pattern with many expansions", function()
      store = EntityStore.new("perf-sync-large")
      local tree = generate_dap_tree(store, 5, 10, 3, 10)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 200,
        below = 200,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Expand many nodes under context
      local frame_vuri = lens.context_vuri
      window:expand(frame_vuri)
      for _, scope_uri in ipairs(tree.scopes[tree.frames[1]] or {}) do
        local scope = store:get(scope_uri)
        if scope then
          window:expand(frame_vuri .. "/" .. scope.key)
        end
      end

      local avg = measure_avg("Sync pattern (many expansions)", 100, function()
        lens:_sync_pattern_from_window()
      end)

      assert.is_true(avg < 10, "Pattern sync should be under 10ms with many expansions")
    end)
  end)

  -- ===========================================================================
  -- CONTEXT CHANGE PERFORMANCE
  -- ===========================================================================
  describe("Context Change", function()
    it("PERF: context change with empty pattern", function()
      store = EntityStore.new("perf-ctx-empty")
      local tree = generate_dap_tree(store, 10, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Measure context changes
      local frame_idx = 1
      local avg = measure_avg("Context change (empty pattern)", 50, function()
        frame_idx = (frame_idx % #tree.frames) + 1
        local new_frame = store:get(tree.frames[frame_idx])
        context_signal:set(new_frame)
      end)

      -- Note: Context change includes TreeWindow refresh which is the slow part
      -- The lens operations themselves (burn, apply) are <1ms
      assert.is_true(avg < 50, "Context change with empty pattern should be under 50ms")
    end)

    it("PERF: context change with expansion pattern", function()
      store = EntityStore.new("perf-ctx-expand")
      local tree = generate_dap_tree(store, 10, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Set up expansion pattern
      local frame_vuri = lens.context_vuri
      window:expand(frame_vuri)
      for _, scope_uri in ipairs(tree.scopes[tree.frames[1]] or {}) do
        local scope = store:get(scope_uri)
        if scope then
          window:expand(frame_vuri .. "/" .. scope.key)
        end
      end

      -- Force pattern sync
      lens:_sync_pattern_from_window()
      print(string.format("\n\tPattern has %d expansion entries", vim.tbl_count(lens.pattern.expansion)))

      -- Measure context changes
      local frame_idx = 1
      local avg = measure_avg("Context change (with expansion)", 50, function()
        frame_idx = (frame_idx % #tree.frames) + 1
        local new_frame = store:get(tree.frames[frame_idx])
        context_signal:set(new_frame)
        window:refresh()
      end)

      assert.is_true(avg < 50, "Context change with expansion should be under 50ms")
    end)

    it("PERF: rapid context changes (stepping simulation)", function()
      store = EntityStore.new("perf-ctx-rapid")
      local tree = generate_dap_tree(store, 20, 5, 3, 5) -- 20 stacks to simulate many steps

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Set up pattern
      lens.pattern.focus = "Locals"
      lens.pattern.expansion = { ["Locals"] = true }

      -- Simulate rapid stepping through frames
      local total_time = 0
      local step_count = 100

      collectgarbage("collect")
      local start = vim.loop.hrtime()
      for i = 1, step_count do
        local frame_idx = ((i - 1) % #tree.frames) + 1
        local new_frame = store:get(tree.frames[frame_idx])
        context_signal:set(new_frame)
      end
      total_time = (vim.loop.hrtime() - start) / 1e6

      print(string.format("\n\t%d rapid context changes: %.3f ms total (%.3f ms/step)",
        step_count, total_time, total_time / step_count))

      -- Note: This measures the full system (store + window + lens)
      -- Real-world stepping is async and doesn't block on these times
      assert.is_true(total_time / step_count < 50, "Rapid context changes should be under 50ms each")
    end)
  end)

  -- ===========================================================================
  -- BURN MECHANISM PERFORMANCE
  -- ===========================================================================
  describe("Burn Mechanism", function()
    it("PERF: burn pattern to old context", function()
      store = EntityStore.new("perf-burn")
      local tree = generate_dap_tree(store, 5, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Set up expansion pattern
      lens.pattern.expansion = {
        ["Locals"] = true,
        ["Globals"] = true,
        ["Locals/var1"] = true,
        ["Locals/var2"] = true,
        ["Locals/var3"] = true,
      }

      local context_vuri = lens.context_vuri
      local avg = measure_avg("Burn pattern (5 entries)", 100, function()
        lens:_burn_pattern(context_vuri)
      end)

      assert.is_true(avg < 5, "Burn should be under 5ms")
    end)

    it("PERF: burn large pattern", function()
      store = EntityStore.new("perf-burn-large")
      local tree = generate_dap_tree(store, 5, 5, 3, 10)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 200,
        below = 200,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Set up large expansion pattern
      lens.pattern.expansion = {}
      for i = 1, 20 do
        lens.pattern.expansion["Locals/var" .. i] = true
      end
      lens.pattern.expansion["Locals"] = true
      lens.pattern.expansion["Globals"] = true

      print(string.format("\n\tPattern has %d expansion entries", vim.tbl_count(lens.pattern.expansion)))

      local context_vuri = lens.context_vuri
      local avg = measure_avg("Burn pattern (22 entries)", 100, function()
        lens:_burn_pattern(context_vuri)
      end)

      assert.is_true(avg < 10, "Burn with large pattern should be under 10ms")
    end)
  end)

  -- ===========================================================================
  -- TRANSPOSE MECHANISM PERFORMANCE
  -- ===========================================================================
  describe("Transpose Mechanism", function()
    it("PERF: apply pattern to new context", function()
      store = EntityStore.new("perf-transpose")
      local tree = generate_dap_tree(store, 5, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Set up pattern
      lens.pattern.focus = "Locals"
      lens.pattern.expansion = {
        ["Locals"] = true,
        ["Globals"] = false,
      }

      -- Get a different context vuri
      local other_frame = store:get(tree.frames[6]) -- Different stack
      local other_vuri = lens:_compute_context_vuri(other_frame.uri)

      local avg = measure_avg("Apply pattern", 100, function()
        lens:_apply_pattern(other_vuri)
      end)

      assert.is_true(avg < 10, "Apply pattern should be under 10ms")
    end)

    it("PERF: transpose focus with graceful degradation", function()
      store = EntityStore.new("perf-transpose-degrade")
      local tree = generate_dap_tree(store, 5, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Set up deep focus that won't fully match
      lens.pattern.focus = "Locals/var1/nested/deep/path"

      local other_frame = store:get(tree.frames[6])
      local other_vuri = lens:_compute_context_vuri(other_frame.uri)

      local avg = measure_avg("Transpose focus (degradation)", 100, function()
        lens:_transpose_focus(other_vuri)
      end)

      assert.is_true(avg < 10, "Transpose with degradation should be under 10ms")
    end)
  end)

  -- ===========================================================================
  -- FOCUS TRACKING PERFORMANCE
  -- ===========================================================================
  describe("Focus Tracking", function()
    it("PERF: focus changes within context", function()
      store = EntityStore.new("perf-focus")
      local tree = generate_dap_tree(store, 5, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Expand context so we can focus within it
      local frame_vuri = lens.context_vuri
      window:expand(frame_vuri)
      window:refresh()

      -- Collect vuris under context
      local vuris = {}
      for _, item in ipairs(window._window_items) do
        if item._virtual and item._virtual.uri:find(frame_vuri, 1, true) == 1 then
          table.insert(vuris, item._virtual.uri)
        end
      end
      print(string.format("\n\tFound %d vuris under context", #vuris))

      -- Measure focus changes
      local idx = 1
      local avg = measure_avg("Focus change (within context)", 100, function()
        idx = (idx % #vuris) + 1
        window:focus_on(vuris[idx])
      end)

      assert.is_true(avg < 5, "Focus changes should be under 5ms")
    end)

    it("PERF: focus changes outside context (should not update pattern)", function()
      store = EntityStore.new("perf-focus-outside")
      local tree = generate_dap_tree(store, 5, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Collect vuris outside context (different stacks)
      local frame_vuri = lens.context_vuri
      local outside_vuris = {}
      for _, item in ipairs(window._window_items) do
        if item._virtual and item._virtual.uri:find(frame_vuri, 1, true) ~= 1 then
          table.insert(outside_vuris, item._virtual.uri)
        end
      end
      print(string.format("\n\tFound %d vuris outside context", #outside_vuris))

      if #outside_vuris > 0 then
        local idx = 1
        local avg = measure_avg("Focus change (outside context)", 100, function()
          idx = (idx % #outside_vuris) + 1
          window:focus_on(outside_vuris[idx])
        end)

        assert.is_true(avg < 10, "Focus changes outside context should be under 10ms")
      end
    end)
  end)

  -- ===========================================================================
  -- SCALING TESTS
  -- ===========================================================================
  describe("Scaling", function()
    it("PERF: context change scaling with tree size", function()
      local sizes = {
        { stacks = 5, frames = 3, scopes = 2, vars = 3 },
        { stacks = 10, frames = 5, scopes = 3, vars = 5 },
        { stacks = 20, frames = 8, scopes = 3, vars = 8 },
      }

      print("\n\tContext change scaling:")

      for _, size in ipairs(sizes) do
        cleanup()

        store = EntityStore.new("perf-scale")
        local tree = generate_dap_tree(store, size.stacks, size.frames, size.scopes, size.vars)

        window = TreeWindow:new(store, tree.root, {
          edge_type = "parent",
          above = 100,
          below = 100,
        })

        local initial_frame = store:get(tree.frames[1])
        context_signal = neostate.Signal(initial_frame)
        lens = ExplorationLens:new(window, context_signal)

        -- Set up pattern
        lens.pattern.focus = "Locals"
        lens.pattern.expansion = { ["Locals"] = true }

        -- Measure
        local frame_idx = 1
        collectgarbage("collect")
        local start = vim.loop.hrtime()
        for _ = 1, 20 do
          frame_idx = (frame_idx % #tree.frames) + 1
          local new_frame = store:get(tree.frames[frame_idx])
          context_signal:set(new_frame)
        end
        local elapsed = (vim.loop.hrtime() - start) / 1e6

        print(string.format("\t  %d frames, %d items: %.3f ms/change",
          #tree.frames, #window._window_items, elapsed / 20))
      end
    end)

    it("PERF: pattern complexity scaling", function()
      store = EntityStore.new("perf-pattern-scale")
      local tree = generate_dap_tree(store, 10, 5, 3, 10)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 200,
        below = 200,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      print("\n\tPattern complexity scaling:")

      local pattern_sizes = { 5, 10, 20, 50 }
      for _, pattern_size in ipairs(pattern_sizes) do
        -- Set up pattern of given size
        lens.pattern.expansion = {}
        for i = 1, pattern_size do
          lens.pattern.expansion["path/segment" .. i] = (i % 2 == 0)
        end

        local context_vuri = lens.context_vuri

        collectgarbage("collect")
        local start = vim.loop.hrtime()
        for _ = 1, 50 do
          lens:_burn_pattern(context_vuri)
        end
        local elapsed = (vim.loop.hrtime() - start) / 1e6

        print(string.format("\t  %d pattern entries: %.3f ms/burn", pattern_size, elapsed / 50))
      end
    end)
  end)

  -- ===========================================================================
  -- MEMORY TESTS
  -- ===========================================================================
  describe("Memory", function()
    it("PERF: lens subscriptions are properly cleaned up on dispose", function()
      store = EntityStore.new("perf-memory")
      local tree = generate_dap_tree(store, 5, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Count subscriptions before
      local subs_before = #lens._subscriptions
      print(string.format("\n\tSubscriptions before: %d", subs_before))

      -- Perform several context changes
      for i = 1, 10 do
        local frame_idx = ((i - 1) % #tree.frames) + 1
        local new_frame = store:get(tree.frames[frame_idx])
        context_signal:set(new_frame)
      end

      -- Count subscriptions after - should not grow
      local subs_after = #lens._subscriptions
      print(string.format("\tSubscriptions after 10 changes: %d", subs_after))

      -- Subscriptions should not grow with context changes
      assert.equals(subs_before, subs_after, "Subscription count should stay constant")

      -- Dispose and verify cleanup
      lens:dispose()
      assert.equals(0, #lens._subscriptions, "All subscriptions should be cleaned up")
    end)

    it("PERF: lens pattern state stays bounded", function()
      store = EntityStore.new("perf-pattern-memory")
      local tree = generate_dap_tree(store, 10, 5, 3, 5)

      window = TreeWindow:new(store, tree.root, {
        edge_type = "parent",
        above = 100,
        below = 100,
      })

      local initial_frame = store:get(tree.frames[1])
      context_signal = neostate.Signal(initial_frame)
      lens = ExplorationLens:new(window, context_signal)

      -- Set up a pattern
      lens.pattern.focus = "Locals/var1"
      lens.pattern.expansion = {
        ["Locals"] = true,
        ["Globals"] = false,
      }

      local expansion_count_before = vim.tbl_count(lens.pattern.expansion)

      -- Perform many context changes
      for i = 1, 100 do
        local frame_idx = ((i - 1) % #tree.frames) + 1
        local new_frame = store:get(tree.frames[frame_idx])
        context_signal:set(new_frame)
      end

      local expansion_count_after = vim.tbl_count(lens.pattern.expansion)
      print(string.format("\n\tPattern expansion entries: before=%d, after=%d",
        expansion_count_before, expansion_count_after))

      -- Pattern size should stay bounded (not grow unboundedly)
      assert.is_true(expansion_count_after <= expansion_count_before + 10,
        "Pattern expansion should not grow unboundedly")
    end)
  end)
end)
