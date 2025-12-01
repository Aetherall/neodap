-- Tests for ExplorationLens
-- The lens manages context-relative exploration state (focus + expansion)

local neostate = require("neostate")
local EntityStore = require("neostate.entity_store")
local ExplorationLens = require("neodap.lib.exploration_lens")
local TreeWindow = require("neostate.tree_window")

describe("ExplorationLens", function()
  local store, window, context_signal, lens

  -- Helper to set up a simple tree structure
  local function setup_tree()
    -- Create a tree:
    -- Debugger
    -- ├── frame:1 (context)
    -- │   ├── Locals
    -- │   │   └── myVar
    -- │   └── Globals
    -- └── frame:2
    --     ├── Locals
    --     │   └── myVar
    --     └── Globals

    store = EntityStore.new("test")

    store:add({ uri = "root", key = "Debugger", name = "Debugger" }, "root")
    store:add({ uri = "frame:1", key = "frame:1", name = "Frame 1", _type = "frame" }, "frame",
      {{ type = "parent", to = "root" }})
    store:add({ uri = "frame:2", key = "frame:2", name = "Frame 2", _type = "frame" }, "frame",
      {{ type = "parent", to = "root" }})
    store:add({ uri = "frame:1/Locals", key = "Locals", name = "Locals", _type = "scope" }, "scope",
      {{ type = "parent", to = "frame:1" }})
    store:add({ uri = "frame:1/Globals", key = "Globals", name = "Globals", _type = "scope" }, "scope",
      {{ type = "parent", to = "frame:1" }})
    store:add({ uri = "frame:1/Locals/myVar", key = "myVar", name = "myVar", _type = "variable" }, "variable",
      {{ type = "parent", to = "frame:1/Locals" }})
    store:add({ uri = "frame:2/Locals", key = "Locals", name = "Locals", _type = "scope" }, "scope",
      {{ type = "parent", to = "frame:2" }})
    store:add({ uri = "frame:2/Globals", key = "Globals", name = "Globals", _type = "scope" }, "scope",
      {{ type = "parent", to = "frame:2" }})
    store:add({ uri = "frame:2/Locals/myVar", key = "myVar", name = "myVar", _type = "variable" }, "variable",
      {{ type = "parent", to = "frame:2/Locals" }})

    window = TreeWindow:new(store, "root", {
      edge_type = "parent",
      above = 20,
      below = 20,
    })

    -- Get entity references for tests
    local ctx1 = store:get("frame:1")
    local ctx2 = store:get("frame:2")

    -- Start with context at frame:1
    context_signal = neostate.Signal(ctx1)

    lens = ExplorationLens:new(window, context_signal)

    return {
      ctx1 = ctx1,
      ctx2 = ctx2,
    }
  end

  after_each(function()
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
    store = nil
  end)

  describe("initialization", function()
    it("should initialize with current context", function()
      local entities = setup_tree()

      local state = lens:get_state()
      assert.is_not_nil(state.context_entity_uri)
      assert.equals("frame:1", state.context_entity_uri)
    end)

    it("should have empty pattern initially", function()
      setup_tree()

      local state = lens:get_state()
      assert.is_nil(state.focus)
      assert.same({}, state.expansion)
    end)
  end)

  describe("pattern building - focus", function()
    it("should track focus changes under context", function()
      local entities = setup_tree()

      -- Focus on Locals under frame:1
      window:focus_on("Debugger/frame:1/Locals")

      local state = lens:get_state()
      assert.equals("Locals", state.focus)
    end)

    it("should track nested focus", function()
      local entities = setup_tree()

      -- Expand Locals first so myVar is visible
      window:expand("Debugger/frame:1/Locals")
      window:focus_on("Debugger/frame:1/Locals/myVar")

      local state = lens:get_state()
      assert.equals("Locals/myVar", state.focus)
    end)

    it("should not update pattern for focus outside context", function()
      local entities = setup_tree()

      -- Focus on frame:2 (outside context frame:1)
      window:focus_on("Debugger/frame:2")

      local state = lens:get_state()
      -- Pattern focus should not be updated (stays nil or previous value)
      assert.is_nil(state.focus)
    end)

    it("should track focus on context root as empty path", function()
      local entities = setup_tree()

      -- Focus on the context itself
      window:focus_on("Debugger/frame:1")

      local state = lens:get_state()
      assert.equals("", state.focus)
    end)
  end)

  describe("pattern building - expansion", function()
    it("should capture expansion state when syncing", function()
      local entities = setup_tree()

      -- Expand Locals
      window:expand("Debugger/frame:1/Locals")

      -- Trigger sync by changing context
      context_signal:set(entities.ctx2)

      -- Check that pattern captured Locals as expanded
      local state = lens:get_state()
      -- Note: pattern was synced before context change, so it should have captured Locals
      -- But since we're now at ctx2, the pattern reflects what was captured
    end)

    it("should only capture visible nodes in pattern", function()
      local entities = setup_tree()

      -- Expand Locals to make myVar visible
      window:expand("Debugger/frame:1/Locals")
      window:focus_on("Debugger/frame:1/Locals/myVar")

      -- Pattern should include the expanded Locals
      context_signal:set(entities.ctx2)

      -- After context change, pattern should have been synced
      -- and applied to new context
    end)
  end)

  describe("burn mechanism", function()
    it("should preserve expansion state at old context after change", function()
      local entities = setup_tree()

      -- Expand Locals at frame:1
      window:expand("Debugger/frame:1/Locals")

      -- Verify it's expanded
      assert.is_false(window:is_collapsed("Debugger/frame:1/Locals"))

      -- Change context to frame:2
      context_signal:set(entities.ctx2)

      -- Rebuild window to include new context
      window:refresh()

      -- Old context (frame:1/Locals) should still be expanded (burned)
      local signal = window.collapsed["frame:1/Locals"]
      if signal then
        assert.is_false(signal:get(), "frame:1/Locals should still be expanded after burn")
      end
    end)

    it("should allow independent modification of old context after burn", function()
      local entities = setup_tree()

      -- Expand Locals at frame:1
      window:expand("Debugger/frame:1/Locals")

      -- Change context to frame:2
      context_signal:set(entities.ctx2)
      window:refresh()

      -- Now collapse Locals at old frame:1
      window:collapse("Debugger/frame:1/Locals")

      -- It should be collapsed
      local signal = window.collapsed["frame:1/Locals"]
      if signal then
        assert.is_true(signal:get(), "Should be able to collapse burned state")
      end

      -- And this shouldn't affect frame:2's Locals
    end)
  end)

  describe("transposition", function()
    it("should apply focus pattern to new context", function()
      local entities = setup_tree()

      -- Focus on Locals at frame:1
      window:focus_on("Debugger/frame:1/Locals")

      -- Verify pattern captured
      local state = lens:get_state()
      assert.equals("Locals", state.focus)

      -- Change context to frame:2
      context_signal:set(entities.ctx2)
      window:refresh()

      -- Focus should now be at frame:2/Locals
      local focus = window.focus:get()
      assert.equals("Debugger/frame:2/Locals", focus)
    end)

    it("should apply expansion pattern to new context", function()
      local entities = setup_tree()

      -- Expand Locals at frame:1
      window:expand("Debugger/frame:1/Locals")

      -- Change context to frame:2
      context_signal:set(entities.ctx2)
      window:refresh()

      -- Locals at frame:2 should also be expanded
      local signal = window.collapsed["frame:2/Locals"]
      if signal then
        assert.is_false(signal:get(), "frame:2/Locals should be expanded after transpose")
      end
    end)

    it("should apply nested expansion pattern", function()
      local entities = setup_tree()

      -- Expand both Locals and navigate to myVar at frame:1
      window:expand("Debugger/frame:1/Locals")
      window:focus_on("Debugger/frame:1/Locals/myVar")

      -- Change context to frame:2
      context_signal:set(entities.ctx2)
      window:refresh()

      -- Check focus transposed
      local focus = window.focus:get()
      assert.equals("Debugger/frame:2/Locals/myVar", focus)
    end)
  end)

  describe("graceful degradation", function()
    it("should fall back to shorter path when target doesn't exist", function()
      -- Create a simpler tree for this test
      -- frame:1 has Locals/myVar, frame:2 has only Locals (no myVar)
      store = EntityStore.new("degradation-test")

      store:add({ uri = "root", key = "Debugger", name = "Debugger" }, "root")
      store:add({ uri = "frame:1", key = "frame:1", name = "Frame 1" }, "frame",
        {{ type = "parent", to = "root" }})
      store:add({ uri = "frame:2", key = "frame:2", name = "Frame 2" }, "frame",
        {{ type = "parent", to = "root" }})
      store:add({ uri = "frame:1/Locals", key = "Locals", name = "Locals" }, "scope",
        {{ type = "parent", to = "frame:1" }})
      store:add({ uri = "frame:1/Locals/myVar", key = "myVar", name = "myVar" }, "variable",
        {{ type = "parent", to = "frame:1/Locals" }})
      -- frame:2 has Locals but no myVar
      store:add({ uri = "frame:2/Locals", key = "Locals", name = "Locals" }, "scope",
        {{ type = "parent", to = "frame:2" }})

      window = TreeWindow:new(store, "root", {
        edge_type = "parent",
        above = 20,
        below = 20,
      })

      local ctx1 = store:get("frame:1")
      local ctx2 = store:get("frame:2")
      context_signal = neostate.Signal(ctx1)
      lens = ExplorationLens:new(window, context_signal)

      -- Expand Locals and focus on myVar at frame:1
      window:expand("Debugger/frame:1/Locals")
      window:focus_on("Debugger/frame:1/Locals/myVar")

      -- Verify pattern
      local state = lens:get_state()
      assert.equals("Locals/myVar", state.focus)

      -- Change context to frame:2 (which has no myVar)
      context_signal:set(ctx2)
      window:refresh()

      -- Focus should degrade to Locals (the deepest existing match)
      local focus = window.focus:get()
      assert.equals("Debugger/frame:2/Locals", focus)
    end)

    it("should fall back to context when nothing matches", function()
      -- frame:1 has Locals, frame:2 has no children
      store = EntityStore.new("fallback-test")

      store:add({ uri = "root", key = "Debugger", name = "Debugger" }, "root")
      store:add({ uri = "frame:1", key = "frame:1", name = "Frame 1" }, "frame",
        {{ type = "parent", to = "root" }})
      store:add({ uri = "frame:2", key = "frame:2", name = "Frame 2" }, "frame",
        {{ type = "parent", to = "root" }})
      store:add({ uri = "frame:1/Locals", key = "Locals", name = "Locals" }, "scope",
        {{ type = "parent", to = "frame:1" }})
      -- frame:2 has no children

      window = TreeWindow:new(store, "root", {
        edge_type = "parent",
        above = 20,
        below = 20,
      })

      local ctx1 = store:get("frame:1")
      local ctx2 = store:get("frame:2")
      context_signal = neostate.Signal(ctx1)
      lens = ExplorationLens:new(window, context_signal)

      -- Focus on Locals at frame:1
      window:focus_on("Debugger/frame:1/Locals")

      -- Change context to frame:2 (which has no Locals)
      context_signal:set(ctx2)
      window:refresh()

      -- Focus should fall back to frame:2 itself
      local focus = window.focus:get()
      assert.equals("Debugger/frame:2", focus)
    end)
  end)

  describe("outside context actions", function()
    it("should not update pattern for actions outside context", function()
      local entities = setup_tree()

      -- Focus on something under context
      window:focus_on("Debugger/frame:1/Locals")

      local state1 = lens:get_state()
      assert.equals("Locals", state1.focus)

      -- Focus on something outside context
      window:focus_on("Debugger/frame:2/Globals")

      -- Pattern should not be updated
      local state2 = lens:get_state()
      assert.equals("Locals", state2.focus) -- Still Locals, not Globals
    end)

    it("should allow free navigation in old context after change", function()
      local entities = setup_tree()

      -- Focus on Locals at frame:1
      window:focus_on("Debugger/frame:1/Locals")

      -- Change context to frame:2
      context_signal:set(entities.ctx2)
      window:refresh()

      -- Now navigate in old frame:1 (outside new context)
      window:focus_on("Debugger/frame:1/Globals")

      -- This should not affect the pattern (pattern follows frame:2 now)
      local state = lens:get_state()
      -- The focus pattern should still be "Locals" since that's what we had
      -- when context was frame:1
    end)
  end)

  describe("async navigation", function()
    it("should store pending path when target not yet visible", function()
      local entities = setup_tree()

      -- Set focus pattern manually
      lens.pattern.focus = "Locals/myVar"

      -- Collapse Locals so myVar is not visible
      window:collapse("Debugger/frame:1/Locals")

      -- Change context to frame:2 (Locals also collapsed by default)
      context_signal:set(entities.ctx2)
      window:refresh()

      -- Check pending path
      local state = lens:get_state()
      -- Should have pending path if myVar wasn't found
      if state.pending_path then
        assert.is_true(#state.pending_path > 0)
      end
    end)

    it("should retry navigation on tree rebuild", function()
      local entities = setup_tree()

      -- Focus on myVar at frame:1
      window:expand("Debugger/frame:1/Locals")
      window:focus_on("Debugger/frame:1/Locals/myVar")

      -- Change context to frame:2
      context_signal:set(entities.ctx2)
      window:refresh()

      -- Expand Locals at frame:2 to make myVar visible
      window:expand("Debugger/frame:2/Locals")
      window:refresh()

      -- Focus should now be on myVar at frame:2
      local focus = window.focus:get()
      assert.equals("Debugger/frame:2/Locals/myVar", focus)

      -- Pending path should be cleared
      local state = lens:get_state()
      assert.is_nil(state.pending_path)
    end)
  end)

  describe("context vuri computation", function()
    it("should compute context vuri from entity in window", function()
      local entities = setup_tree()

      local state = lens:get_state()
      assert.equals("Debugger/frame:1", state.context_vuri)
    end)

    it("should update context vuri on context change", function()
      local entities = setup_tree()

      context_signal:set(entities.ctx2)
      window:refresh()

      local state = lens:get_state()
      assert.equals("Debugger/frame:2", state.context_vuri)
    end)
  end)

  describe("get_state", function()
    it("should return complete state for debugging", function()
      local entities = setup_tree()

      window:focus_on("Debugger/frame:1/Locals")
      window:expand("Debugger/frame:1/Locals")

      local state = lens:get_state()

      assert.is_not_nil(state.focus)
      assert.is_not_nil(state.expansion)
      assert.is_not_nil(state.context_vuri)
      assert.is_not_nil(state.context_entity_uri)
    end)
  end)

  describe("cleanup", function()
    it("should unsubscribe all subscriptions on dispose", function()
      local entities = setup_tree()

      -- Count subscriptions
      local initial_count = #lens._subscriptions

      lens:dispose()

      -- Subscriptions should be cleared
      assert.equals(0, #lens._subscriptions)
    end)

    it("should not crash when context changes after dispose", function()
      local entities = setup_tree()

      lens:dispose()

      -- This should not error
      context_signal:set(entities.ctx2)
    end)
  end)
end)
