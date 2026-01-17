-- Integration tests for Frame entity, scopes, and variables
local harness = require("helpers.test_harness")

return harness.integration("frame", function(T, ctx)
  -- ==========================================================================
  -- Frame Location Tests (from test_neodap.lua)
  -- ==========================================================================

  T["Frame provides location"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Frame should exist
    MiniTest.expect.equality(h:query_is_nil("@frame"), false)

    -- Frame should have location fields
    local frame_name = h:query_field("@frame", "name")
    local frame_line = h:query_field("@frame", "line")
    local frame_column = h:query_field("@frame", "column")

    MiniTest.expect.equality(frame_name ~= nil, true)
    MiniTest.expect.equality(frame_line, 1)
    MiniTest.expect.equality(frame_column ~= nil, true)

    -- Frame should have a source with path
    local source_path = h:query_field("@frame/source", "path")
    MiniTest.expect.equality(source_path ~= nil, true)
  end

  T["Variable exists in scope"] = function()
    -- Skip for JavaScript - variable timing and scope structure differs
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("nested-dict")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to define the dict
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Variables should exist in the scope
    local var_count = h:query_count("@frame/scopes[0]/variables")
    MiniTest.expect.equality(var_count >= 1, true)

    -- First variable should have a name and value
    local var_name = h:query_field("@frame/scopes[0]/variables[0]", "name")
    local var_value = h:query_field("@frame/scopes[0]/variables[0]", "value")

    MiniTest.expect.equality(var_name ~= nil, true)
    MiniTest.expect.equality(var_value ~= nil, true)
  end

  -- ==========================================================================
  -- Frame Sorting Tests (from test_edge_sorting.lua)
  -- ==========================================================================

  T["frames[0] is top of stack (most recent call)"] = function()
    local h = ctx.create()
    h:init_plugin("neodap.plugins.breakpoint_cmd")
    h:fixture("with-function")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Set breakpoint inside inner function (line 2 is where x = 1)
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Continue to breakpoint at line 2
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get frame names via URL
    local frame0_name = h:query_field("@thread/stack/frames[0]", "name")
    local frame1_name = h:query_field("@thread/stack/frames[1]", "name")

    -- frames[0] should be "inner" (current function)
    -- Note: JavaScript adapter may prefix with scope (e.g., "global.inner")
    MiniTest.expect.equality(frame0_name:match("inner$") ~= nil, true)

    -- frames[1] should be "outer" (caller)
    -- Note: JavaScript adapter may prefix with scope (e.g., "global.outer")
    MiniTest.expect.equality(frame1_name:match("outer$") ~= nil, true)

    -- Verify indices are ascending
    local frame0_index = h:query_field("@thread/stack/frames[0]", "index")
    local frame1_index = h:query_field("@thread/stack/frames[1]", "index")
    MiniTest.expect.equality(frame0_index < frame1_index, true)
  end
end)
