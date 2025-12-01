-- Tests for loadedSources DAP request and loadedSource event handling
-- Uses js-debug (pwa-node) which supports loadedSources

local sdk = require("neodap.sdk")
local neostate = require("neostate")

neostate.setup({
  debug_context = false,
  trace = false,
})

-- Inline verified_it helper for async tests
local function verified_it(name, fn, timeout_ms)
  timeout_ms = timeout_ms or 30000

  return it(name, function()
    local completed = false
    local test_error = nil
    local test_result = nil

    local co = coroutine.create(function()
      local ok, result = pcall(fn)
      if not ok then
        test_error = result
      else
        test_result = result
      end
      completed = true
    end)

    local ok, err = coroutine.resume(co)
    if not ok and not completed then
      error("Test failed to start: " .. tostring(err))
    end

    local success = vim.wait(timeout_ms, function()
      return completed
    end, 100)

    if not success then
      error(string.format("Test '%s' timed out after %dms", name, timeout_ms))
    end

    if test_error then
      error(test_error)
    end

    if test_result ~= true then
      error(string.format(
        "Test did not return true (got: %s). Tests must return true at completion.",
        tostring(test_result)
      ))
    end
  end)
end

-- Helper to create js-debug debugger
local function create_js_debugger()
  local debugger = sdk:create_debugger()

  debugger:register_adapter("pwa-node", {
    type = "server",
    command = "js-debug",
    args = { "0" },
    connect_condition = function(chunk)
      local h, p = chunk:match("Debug server listening at (.*):(%d+)")
      return tonumber(p), h
    end
  })

  return debugger
end

-- Helper to wait for child session (js-debug spawns child)
local function wait_for_child_session(bootstrap_session)
  local child = nil
  vim.wait(10000, function()
    for s in bootstrap_session:children():iter() do
      child = s
      return true
    end
    return false
  end, 50)
  return child
end

describe("loadedSources (js-debug)", function()
  local js_script = vim.fn.fnamemodify("tests/fixtures/counter_loop.js", ":p")

  describe("Capability Check", function()
    verified_it("supportsLoadedSources() returns true for js-debug", function()
      print("\n=== CAPABILITY CHECK TEST (js-debug) ===")
      local debugger = create_js_debugger()

      -- Add breakpoint to stop execution
      debugger:add_breakpoint({ path = js_script }, 5)

      local bootstrap_session = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script,
        console = "internalConsole",
      })

      -- Wait for child session (real debuggee)
      local session = wait_for_child_session(bootstrap_session)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for capabilities
      vim.wait(10000, function()
        return session.capabilities ~= nil
      end)

      local supports = session:supportsLoadedSources()
      print(string.format("  supportsLoadedSources: %s", tostring(supports)))
      print(string.format("  capabilities.supportsLoadedSourcesRequest: %s",
        tostring(session.capabilities and session.capabilities.supportsLoadedSourcesRequest)))

      assert.is_true(supports, "js-debug should support loadedSources")

      -- Cleanup
      bootstrap_session:disconnect(true)
      vim.wait(2000, function() return bootstrap_session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("loadedSources() Request", function()
    verified_it("should fetch and return Source entities", function()
      print("\n=== LOADED SOURCES REQUEST TEST ===")
      local debugger = create_js_debugger()

      -- Add breakpoint to stop execution
      debugger:add_breakpoint({ path = js_script }, 5)

      local bootstrap_session = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap_session)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for stopped state
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      print("  Session stopped, fetching loaded sources...")

      local err, sources = session:loadedSources()

      assert.is_nil(err, "loadedSources() should not return error: " .. tostring(err))
      assert.is_table(sources, "loadedSources() should return table")
      print(string.format("  Got %d loaded sources", #sources))

      -- Should have at least our script
      assert.is_true(#sources > 0, "Should have at least one loaded source")

      -- Verify sources are Source entities
      for i, source in ipairs(sources) do
        assert.is_function(source.is_virtual, "Source should have is_virtual method")
        assert.is_function(source.location_uri, "Source should have location_uri method")
        assert.is_string(source.uri, "Source should have uri field")
        assert.is_string(source.correlation_key, "Source should have correlation_key")

        if i <= 5 then
          print(string.format("  [%d] %s (virtual=%s)",
            i,
            source.path or source.name or "unknown",
            tostring(source:is_virtual())))
        end
      end

      if #sources > 5 then
        print(string.format("  ... and %d more sources", #sources - 5))
      end

      -- Cleanup
      bootstrap_session:disconnect(true)
      vim.wait(2000, function() return bootstrap_session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should return same Source entities on repeated calls (deduplication)", function()
      print("\n=== DEDUPLICATION TEST ===")
      local debugger = create_js_debugger()

      debugger:add_breakpoint({ path = js_script }, 5)

      local bootstrap_session = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap_session)
      assert.is_not_nil(session, "Should have child session")

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Fetch sources twice
      local err1, sources1 = session:loadedSources()
      local err2, sources2 = session:loadedSources()

      assert.is_nil(err1)
      assert.is_nil(err2)

      print(string.format("  First call: %d sources", #sources1))
      print(string.format("  Second call: %d sources", #sources2))

      -- Should return same number
      assert.are.equal(#sources1, #sources2, "Should return same number of sources")

      -- Build lookup by correlation_key
      local sources1_by_key = {}
      for _, s in ipairs(sources1) do
        sources1_by_key[s.correlation_key] = s
      end

      -- Verify same Source objects (by reference)
      local same_count = 0
      for _, s2 in ipairs(sources2) do
        local s1 = sources1_by_key[s2.correlation_key]
        if s1 == s2 then
          same_count = same_count + 1
        end
      end

      print(string.format("  Same objects: %d/%d", same_count, #sources2))
      assert.are.equal(#sources2, same_count, "All sources should be same objects (deduplication)")

      -- Cleanup
      bootstrap_session:disconnect(true)
      vim.wait(2000, function() return bootstrap_session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should populate debugger.sources and source_bindings collections", function()
      print("\n=== COLLECTION POPULATION TEST ===")
      local debugger = create_js_debugger()

      debugger:add_breakpoint({ path = js_script }, 5)

      local bootstrap_session = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap_session)
      assert.is_not_nil(session, "Should have child session")

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Fetch loaded sources
      local err, sources = session:loadedSources()
      assert.is_nil(err)

      print(string.format("  loadedSources() returned: %d", #sources))

      -- Count sources in collection
      local sources_count = 0
      for _ in debugger.sources:iter() do
        sources_count = sources_count + 1
      end
      print(string.format("  debugger.sources count: %d", sources_count))

      -- Verify sources are in debugger.sources collection
      local found_count = 0
      for _, source in ipairs(sources) do
        local found = debugger.sources:get_one("by_correlation_key", source.correlation_key)
        if found == source then
          found_count = found_count + 1
        end
      end
      print(string.format("  Sources found in collection: %d/%d", found_count, #sources))
      assert.are.equal(#sources, found_count, "All sources should be in debugger.sources")

      -- Check source_bindings for this session
      local binding_count = 0
      for binding in session:source_bindings():iter() do
        binding_count = binding_count + 1
      end
      print(string.format("  Source bindings for session: %d", binding_count))
      assert.is_true(binding_count > 0, "Should have source bindings")

      -- Cleanup
      bootstrap_session:disconnect(true)
      vim.wait(2000, function() return bootstrap_session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should include main program source", function()
      print("\n=== MAIN PROGRAM SOURCE TEST ===")
      local debugger = create_js_debugger()

      debugger:add_breakpoint({ path = js_script }, 5)

      local bootstrap_session = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap_session)
      assert.is_not_nil(session, "Should have child session")

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      local err, sources = session:loadedSources()
      assert.is_nil(err)

      -- Find our main script in loaded sources
      local found_main = nil
      for _, source in ipairs(sources) do
        if source.path and source.path:match("counter_loop%.js$") then
          found_main = source
          break
        end
      end

      assert.is_not_nil(found_main, "Should find main program in loaded sources")
      print(string.format("  Found main program: %s", found_main.path))
      print(string.format("  correlation_key: %s", found_main.correlation_key))
      assert.is_false(found_main:is_virtual(), "Main program should not be virtual")

      -- Cleanup
      bootstrap_session:disconnect(true)
      vim.wait(2000, function() return bootstrap_session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("loadedSource Events (Real)", function()
    local dynamic_script = vim.fn.fnamemodify("tests/fixtures/dynamic_load.js", ":p")
    local helper_script = vim.fn.fnamemodify("tests/fixtures/dynamic_helper.js", ":p")

    verified_it("should receive loadedSource event for main program file", function()
      print("\n=== MAIN PROGRAM LOADED SOURCE EVENT TEST ===")
      local debugger = create_js_debugger()

      -- Track loadedSource events BEFORE session starts (via onSession)
      local loaded_source_events = {}
      debugger:onSession(function(session)
        session.client:on("loadedSource", function(body)
          table.insert(loaded_source_events, {
            reason = body.reason,
            path = body.source and body.source.path,
            name = body.source and body.source.name,
          })
        end)
      end)

      -- Set breakpoint to stop execution
      debugger:add_breakpoint({ path = dynamic_script }, 19)

      local bootstrap_session = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = dynamic_script,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap_session)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for stopped state
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      print(string.format("  Total loadedSource events: %d", #loaded_source_events))

      -- Find event for main program
      local found_main = nil
      for _, event in ipairs(loaded_source_events) do
        if event.path and event.path:match("dynamic_load%.js$") then
          found_main = event
          break
        end
      end

      assert.is_not_nil(found_main, "Should receive loadedSource event for main program")
      assert.are.equal("new", found_main.reason, "Main program event should have reason 'new'")
      print(string.format("  Found main program event: %s (reason=%s)", found_main.path, found_main.reason))

      -- Count local vs virtual
      local local_count = 0
      local virtual_count = 0
      for _, event in ipairs(loaded_source_events) do
        if event.path and not event.path:match("^<") then
          local_count = local_count + 1
        else
          virtual_count = virtual_count + 1
        end
      end
      print(string.format("  Local file events: %d, Virtual/internal: %d", local_count, virtual_count))

      -- Cleanup
      bootstrap_session:disconnect(true)
      vim.wait(2000, function() return bootstrap_session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should receive loadedSource event for dynamically required module", function()
      print("\n=== DYNAMIC REQUIRE LOADED SOURCE EVENT TEST ===")
      local debugger = create_js_debugger()

      -- Track loadedSource events BEFORE session starts
      local loaded_source_events = {}
      debugger:onSession(function(session)
        session.client:on("loadedSource", function(body)
          table.insert(loaded_source_events, {
            reason = body.reason,
            path = body.source and body.source.path,
            name = body.source and body.source.name,
          })
        end)
      end)

      -- Breakpoint before require (line 19) and after (line 21)
      debugger:add_breakpoint({ path = dynamic_script }, 19)
      debugger:add_breakpoint({ path = dynamic_script }, 21)

      local bootstrap_session = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = dynamic_script,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap_session)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for first stop (before require)
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      local events_before_require = #loaded_source_events
      print(string.format("  Events before require: %d", events_before_require))

      -- Verify helper NOT yet loaded
      local helper_before = nil
      for _, event in ipairs(loaded_source_events) do
        if event.path and event.path:match("dynamic_helper%.js$") then
          helper_before = event
          break
        end
      end
      assert.is_nil(helper_before, "Helper should not be loaded yet before require()")

      -- Continue execution past the require()
      session.client:request("continue", { threadId = 1 }, function() end)

      -- Wait for second stop (after require)
      vim.wait(5000, function()
        return session.state:get() == "stopped"
      end)

      -- Small delay for events to process
      vim.wait(200, function() return false end)

      print(string.format("  Events after require: %d", #loaded_source_events))
      print(string.format("  New events: %d", #loaded_source_events - events_before_require))

      -- Find event for dynamically loaded helper
      local found_helper = nil
      for _, event in ipairs(loaded_source_events) do
        if event.path and event.path:match("dynamic_helper%.js$") then
          found_helper = event
          break
        end
      end

      assert.is_not_nil(found_helper, "Should receive loadedSource event for dynamically required module")
      assert.are.equal("new", found_helper.reason, "Dynamic module event should have reason 'new'")
      print(string.format("  Found dynamic module event: %s (reason=%s)", found_helper.path, found_helper.reason))

      -- Cleanup
      bootstrap_session:disconnect(true)
      vim.wait(2000, function() return bootstrap_session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should create Source entities from loadedSource events", function()
      print("\n=== SOURCE CREATION FROM EVENTS TEST ===")
      local debugger = create_js_debugger()

      -- Track sources created from events BEFORE session starts
      local sources_from_events = {}
      debugger:onSession(function(session)
        session:onSource(function(source)
          table.insert(sources_from_events, source)
        end)
      end)

      debugger:add_breakpoint({ path = dynamic_script }, 19)

      local bootstrap_session = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = dynamic_script,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap_session)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for stopped state
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      print(string.format("  Sources received via onSource: %d", #sources_from_events))

      -- Should have sources (from loadedSource events during startup)
      assert.is_true(#sources_from_events > 0, "Should receive sources via onSource hook")

      -- Verify main program is in sources
      local found_main = nil
      for _, src in ipairs(sources_from_events) do
        if src.path and src.path:match("dynamic_load%.js$") then
          found_main = src
          break
        end
      end
      assert.is_not_nil(found_main, "Main program should be in sources from events")
      print(string.format("  Main program source: %s", found_main.path))

      -- Verify sources in debugger.sources collection match
      local sources_in_collection = 0
      for _ in debugger.sources:iter() do
        sources_in_collection = sources_in_collection + 1
      end
      print(string.format("  Sources in debugger.sources: %d", sources_in_collection))

      -- All sources from events should be in the collection
      local all_in_collection = true
      for _, src in ipairs(sources_from_events) do
        local found = debugger.sources:get_one("by_correlation_key", src.correlation_key)
        if found ~= src then
          all_in_collection = false
          break
        end
      end
      assert.is_true(all_in_collection, "All sources from events should be in debugger.sources")
      print("  All event sources found in collection")

      -- Verify source bindings exist for session
      local bindings_count = 0
      for _ in session:source_bindings():iter() do
        bindings_count = bindings_count + 1
      end
      print(string.format("  Source bindings for session: %d", bindings_count))
      assert.is_true(bindings_count > 0, "Should have source bindings")

      -- Cleanup
      bootstrap_session:disconnect(true)
      vim.wait(2000, function() return bootstrap_session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("Event Handler Logic", function()
    -- These tests verify handler logic directly since some events (like "changed")
    -- are difficult to trigger with real adapters (requires HMR/live reload tooling)
    --
    -- Note: "changed" events are skipped - they require Hot Module Replacement
    -- or similar dev tooling which is beyond the scope of these tests.

    verified_it("_handle_source_removed removes binding but keeps source", function()
      print("\n=== REMOVED HANDLER LOGIC TEST ===")
      local debugger = create_js_debugger()

      local bootstrap_session = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script,
        console = "internalConsole",
        stopOnEntry = true,
      })

      local session = wait_for_child_session(bootstrap_session)
      assert.is_not_nil(session, "Should have child session")

      vim.wait(5000, function()
        return session.capabilities ~= nil
      end)

      -- Create a source
      local test_source_data = {
        path = "/fake/removable/source.js",
        name = "source.js",
      }
      local source = session:get_or_create_source(test_source_data)

      -- Verify binding exists
      local binding_before = session:_find_source_binding(source)
      assert.is_not_nil(binding_before, "Should have binding before removal")
      print("  Created source with binding")

      -- Count bindings for this session before
      local bindings_before = 0
      for _ in session:source_bindings():iter() do
        bindings_before = bindings_before + 1
      end

      -- Call handler directly (simulating event)
      session:_handle_source_removed({
        path = "/fake/removable/source.js",
      })

      -- Binding should be removed
      local binding_after = session:_find_source_binding(source)
      assert.is_nil(binding_after, "Binding should be removed")

      -- Count bindings after
      local bindings_after = 0
      for _ in session:source_bindings():iter() do
        bindings_after = bindings_after + 1
      end
      print(string.format("  Bindings before: %d, after: %d", bindings_before, bindings_after))
      assert.are.equal(bindings_before - 1, bindings_after, "Should have one less binding")

      -- Source should still exist in global collection
      local source_still_exists = debugger.sources:get_one("by_correlation_key", source.correlation_key)
      assert.are.equal(source, source_still_exists, "Source should still exist")
      print("  Source preserved in global collection")

      -- Cleanup
      bootstrap_session:disconnect(true)
      vim.wait(2000, function() return bootstrap_session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)
end)
