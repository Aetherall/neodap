-- Tests for breakpointLocations request support
-- Tests: Session:supportsBreakpointLocations, Session:breakpointLocations,
--        Debugger:breakpointLocations, Source:breakpointLocations

local neostate = require("neostate")
local sdk = require("neodap.sdk")

neostate.setup({
  debug_context = false,
  trace = false,
})

-- Helper for tests that need coroutines
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
    args = { "0" },  -- Use random port
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
  end)
  return child
end

describe("breakpointLocations (js-debug)", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/counter_loop.js"

  -- ==========================================================================
  -- CAPABILITY CHECK
  -- ==========================================================================

  describe("Capability Check", function()
    verified_it("supportsBreakpointLocations() returns true for js-debug", function()
      print("\n=== CAPABILITY CHECK TEST (js-debug) ===")
      local debugger = create_js_debugger()

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
        stopOnEntry = true,
      })

      -- Wait for child session (js-debug spawns child for actual debugging)
      local session = wait_for_child_session(bootstrap)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for session to be ready
      vim.wait(10000, function()
        return session.state:get() == "stopped" or session.state:get() == "running"
      end)

      local supports = session:supportsBreakpointLocations()
      print(string.format("  supportsBreakpointLocations: %s", tostring(supports)))
      print(string.format("  capabilities.supportsBreakpointLocationsRequest: %s",
        tostring(session.capabilities and session.capabilities.supportsBreakpointLocationsRequest)))

      assert.is_true(supports, "js-debug should support breakpointLocations")

      -- Cleanup
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  -- ==========================================================================
  -- SESSION:BREAKPOINTLOCATIONS
  -- ==========================================================================

  describe("Session:breakpointLocations()", function()
    verified_it("returns locations for a line", function()
      print("\n=== SESSION:BREAKPOINTLOCATIONS TEST ===")
      local debugger = create_js_debugger()

      -- Add a breakpoint to stop execution (needed to load source)
      debugger:add_breakpoint({ path = script_path }, 5)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for stopped state (source is loaded at this point)
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Query breakpoint locations for line 7 (0-indexed: 6) - "counter += 1;"
      local err, locations = session:breakpointLocations({ path = script_path }, 6)

      print(string.format("  Error: %s", tostring(err)))
      print(string.format("  Locations count: %d", locations and #locations or 0))

      assert.is_nil(err, "Should not return error")
      assert.is_not_nil(locations, "Should return locations array")
      assert.is_true(#locations > 0, "Should have at least one location")

      -- Print locations
      for i, loc in ipairs(locations) do
        print(string.format("  [%d] line=%d, col=%d", i, loc.pos[1], loc.pos[2]))
        if loc.end_pos then
          print(string.format("       end: line=%d, col=%d", loc.end_pos[1], loc.end_pos[2]))
        end
      end

      -- Verify 0-indexed
      assert.are.equal(6, locations[1].pos[1], "Line should be 0-indexed (line 7 = index 6)")

      -- Cleanup
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("returns locations with position (line, col)", function()
      print("\n=== SESSION:BREAKPOINTLOCATIONS WITH COLUMN TEST ===")
      local debugger = create_js_debugger()

      -- Add a breakpoint to stop execution (needed to load source)
      debugger:add_breakpoint({ path = script_path }, 5)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for stopped state
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Query with {line, col} format - line 7 (0-indexed: 6)
      local err, locations = session:breakpointLocations({ path = script_path }, { 6, 0 })

      print(string.format("  Error: %s", tostring(err)))
      print(string.format("  Locations count: %d", locations and #locations or 0))

      assert.is_nil(err, "Should not return error")
      assert.is_not_nil(locations, "Should return locations array")

      -- Cleanup
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("returns locations for a range", function()
      print("\n=== SESSION:BREAKPOINTLOCATIONS RANGE TEST ===")
      local debugger = create_js_debugger()

      -- Add a breakpoint to stop execution (needed to load source)
      debugger:add_breakpoint({ path = script_path }, 5)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for stopped state
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Query range: lines 1-10 (0-indexed: 0-9)
      local err, locations = session:breakpointLocations(
        { path = script_path },
        { 0, 0 },
        { 9, 0 }
      )

      print(string.format("  Error: %s", tostring(err)))
      print(string.format("  Locations in range: %d", locations and #locations or 0))

      assert.is_nil(err, "Should not return error")
      assert.is_not_nil(locations, "Should return locations array")
      assert.is_true(#locations > 1, "Range should have multiple locations")

      -- Print all locations
      for i, loc in ipairs(locations) do
        print(string.format("  [%d] line=%d, col=%d", i, loc.pos[1], loc.pos[2]))
      end

      -- Cleanup
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  -- ==========================================================================
  -- SOURCE:BREAKPOINTLOCATIONS
  -- ==========================================================================

  describe("Source:breakpointLocations()", function()
    verified_it("convenience method works via debugger", function()
      print("\n=== SOURCE:BREAKPOINTLOCATIONS TEST ===")
      local debugger = create_js_debugger()

      -- Add a breakpoint to stop execution (needed to load source)
      debugger:add_breakpoint({ path = script_path }, 5)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for stopped state
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Get source entity
      local source = session:get_or_create_source({ path = script_path })
      assert.is_not_nil(source, "Should have source entity")

      -- Query via Source convenience method - line 7 (0-indexed: 6)
      local err, locations = source:breakpointLocations(6)

      print(string.format("  Error: %s", tostring(err)))
      print(string.format("  Locations via Source: %d", locations and #locations or 0))

      assert.is_nil(err, "Should not return error")
      assert.is_not_nil(locations, "Should return locations array")
      assert.is_true(#locations > 0, "Should have locations")

      -- Cleanup
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)
end)

-- ==========================================================================
-- UNSUPPORTED ADAPTER TEST (Python/debugpy)
-- ==========================================================================

describe("breakpointLocations (unsupported adapter)", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/simple_python.py"

  verified_it("returns error when adapter doesn't support it", function()
    print("\n=== UNSUPPORTED ADAPTER TEST (debugpy) ===")
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    vim.wait(10000, function()
      return session.state:get() == "stopped" or session.state:get() == "running"
    end)

    local supports = session:supportsBreakpointLocations()
    print(string.format("  supportsBreakpointLocations: %s", tostring(supports)))

    -- debugpy typically doesn't support breakpointLocations
    if not supports then
      local err, locations = session:breakpointLocations({ path = script_path }, 5)
      print(string.format("  Error: %s", tostring(err)))
      assert.is_not_nil(err, "Should return error for unsupported adapter")
      assert.is_nil(locations, "Should not return locations")
    else
      print("  Note: debugpy now supports breakpointLocations, skipping error test")
    end

    -- Cleanup
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)
