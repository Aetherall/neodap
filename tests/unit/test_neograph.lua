-- Unit tests for neograph-native integration
-- Tests the reactive graph database layer that backs neodap entities
local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local neo = require("neograph")
local schema = require("neodap.schema")

-- =============================================================================
-- Schema tests
-- =============================================================================

T["schema"] = MiniTest.new_set()

T["schema"]["creates graph from schema"] = function()
  local graph = neo.create(schema.schema)
  MiniTest.expect.no_error(function()
    graph:insert("Debugger", { uri = "debugger:test" })
  end)
end

T["schema"]["creates all entity types"] = function()
  local graph = neo.create(schema.schema)

  -- Test creating each type
  local types = {
    "Debugger", "Source", "SourceBinding", "Breakpoint", "BreakpointBinding",
    "Session", "Thread", "Stack", "Frame", "Scope", "Variable",
    "Output", "ExceptionFilter", "Stdio", "Threads", "Breakpoints", "Sessions", "Targets"
  }

  for _, type_name in ipairs(types) do
    MiniTest.expect.no_error(function()
      graph:insert(type_name, { uri = type_name .. ":test" })
    end)
  end
end

-- =============================================================================
-- Rollup tests
-- =============================================================================

T["rollups"] = MiniTest.new_set()

T["rollups"]["reference rollup returns Signal"] = function()
  local graph = neo.create(schema.schema)

  local debugger = graph:insert("Debugger", { uri = "debugger:test" })
  local session = graph:insert("Session", { uri = "session:test", sessionId = "s1" })

  -- Link via edge
  debugger.sessions:link(session)

  -- Reference rollup should return the session via :get()
  local first = debugger.firstSession:get()
  MiniTest.expect.equality(first._id, session._id)
end

T["rollups"]["reference rollup for one-to-one edge"] = function()
  local graph = neo.create(schema.schema)

  local debugger = graph:insert("Debugger", { uri = "debugger:test" })
  local session = graph:insert("Session", { uri = "session:test", sessionId = "s1" })

  -- Link
  debugger.sessions:link(session)

  -- Reverse edge access via rollup
  local parent = session.debugger:get()
  MiniTest.expect.equality(parent._id, debugger._id)
end

T["rollups"]["property rollup count"] = function()
  local graph = neo.create(schema.schema)

  local debugger = graph:insert("Debugger", { uri = "debugger:test" })
  local s1 = graph:insert("Session", { uri = "session:1", sessionId = "s1" })
  local s2 = graph:insert("Session", { uri = "session:2", sessionId = "s2" })

  debugger.sessions:link(s1)
  debugger.sessions:link(s2)

  -- sessionCount rollup
  MiniTest.expect.equality(debugger.sessionCount:get(), 2)
end

T["rollups"]["filtered reference rollup"] = function()
  local graph = neo.create(schema.schema)

  local bp = graph:insert("Breakpoint", { uri = "bp:test", line = 10, enabled = true })
  local b1 = graph:insert("BreakpointBinding", { uri = "bb:1", verified = false, hit = false })
  local b2 = graph:insert("BreakpointBinding", { uri = "bb:2", verified = true, hit = false })
  local b3 = graph:insert("BreakpointBinding", { uri = "bb:3", verified = true, hit = true })

  bp.bindings:link(b1)
  bp.bindings:link(b2)
  bp.bindings:link(b3)

  -- hitBinding should return b3
  local hit = bp.hitBinding:get()
  MiniTest.expect.equality(hit._id, b3._id)

  -- verifiedBinding should return one of b2 or b3
  local verified = bp.verifiedBinding:get()
  MiniTest.expect.equality(verified.verified:get(), true)
end

T["rollups"]["property rollup any"] = function()
  local graph = neo.create(schema.schema)

  local bp = graph:insert("Breakpoint", { uri = "bp:test", line = 10, enabled = true })

  -- No bindings yet
  MiniTest.expect.equality(bp.hasHitBinding:get(), false)
  MiniTest.expect.equality(bp.hasVerifiedBinding:get(), false)

  -- Add verified binding
  local b1 = graph:insert("BreakpointBinding", { uri = "bb:1", verified = true, hit = false })
  bp.bindings:link(b1)

  MiniTest.expect.equality(bp.hasVerifiedBinding:get(), true)
  MiniTest.expect.equality(bp.hasHitBinding:get(), false)

  -- Add hit binding
  local b2 = graph:insert("BreakpointBinding", { uri = "bb:2", verified = true, hit = true })
  bp.bindings:link(b2)

  MiniTest.expect.equality(bp.hasHitBinding:get(), true)
end

-- =============================================================================
-- Entity constructor tests
-- =============================================================================

T["entity constructor"] = MiniTest.new_set()

T["entity constructor"]["creates nodes with custom methods"] = function()
  local entity_mod = require("neodap.entity")
  local graph = neo.create(schema.schema)

  -- Create a simple entity class
  local Session = entity_mod.class("Session")
  entity_mod.add_common_methods(Session)

  function Session:isRunning()
    return self.state:get() == "running"
  end

  -- Use the constructor pattern (Entity.new sets metatable, inserts, attaches graph)
  local session = Session.new(graph, { uri = "session:test", state = "running" })

  MiniTest.expect.equality(session:isRunning(), true)
  MiniTest.expect.equality(session:id(), session._id)
end

-- =============================================================================
-- Derive tests
-- =============================================================================

T["derive"] = MiniTest.new_set()

T["derive"]["derive creates reactive signal"] = function()
  local derive_mod = require("neodap.derive")
  local graph = neo.create(schema.schema)

  local node = graph:insert("Session", { uri = "session:test", state = "running" })

  local derived = derive_mod.derive(
    function()
      return node.state:get() == "running"
    end,
    function(notify)
      return node.state:use(function()
        notify()
      end)
    end
  )

  MiniTest.expect.equality(derived:get(), true)

  -- Update state
  graph:update(node._id, { state = "stopped" })

  MiniTest.expect.equality(derived:get(), false)
end

T["derive"]["DerivedSignal transforms source"] = function()
  local derive_mod = require("neodap.derive")
  local graph = neo.create(schema.schema)

  local node = graph:insert("Session", { uri = "session:test", name = "test-session" })

  local derived = derive_mod.DerivedSignal.new(node.name, function(name)
    return string.upper(name)
  end)

  MiniTest.expect.equality(derived:get(), "TEST-SESSION")
end

-- =============================================================================
-- Neodap bootstrap tests (from test_minimal_native.lua)
-- =============================================================================

T["bootstrap"] = MiniTest.new_set()

T["bootstrap"]["neodap loads without error"] = function()
  local neodap = require("neodap")
  MiniTest.expect.no_error(function()
    neodap.setup()
  end)
end

T["bootstrap"]["debugger entity exists"] = function()
  local neodap = require("neodap")
  neodap.setup()
  local debugger = neodap.debugger

  MiniTest.expect.equality(type(debugger), "table")
  MiniTest.expect.equality(debugger._graph ~= nil, true)
end

T["bootstrap"]["debugger has sessions edge"] = function()
  local neodap = require("neodap")
  neodap.setup()
  local debugger = neodap.debugger

  local sessions = debugger.sessions
  MiniTest.expect.equality(type(sessions), "table")
  MiniTest.expect.equality(type(sessions.iter), "function")
end

T["bootstrap"]["debugger has firstSession rollup"] = function()
  local neodap = require("neodap")
  neodap.setup()
  local debugger = neodap.debugger

  local firstSession = debugger.firstSession
  MiniTest.expect.equality(type(firstSession), "table")
  MiniTest.expect.equality(type(firstSession.get), "function")
end

T["bootstrap"]["identity is pre-installed"] = function()
  local neodap = require("neodap")
  neodap.setup()

  local debugger = neodap.debugger
  -- Check the internal flag via rawget
  local installed = rawget(debugger, "_identity_installed")
  MiniTest.expect.equality(installed, true)
end

return T
