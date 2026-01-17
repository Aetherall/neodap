local harness = require("helpers.test_harness")

return harness.integration("variable", function(T, ctx)
  T["variable:fetchChildren() expands nested structures"] = function()
    local h = ctx.create()
    h:fixture("nested-dict")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step once to define data (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Get the data variable and fetch children
    local var_url = "@frame/scopes[0]/variables(name=data)[0]"
    h:query_call(var_url, "fetchChildren")
    h:wait_url(var_url .. "/children[0]")

    -- Dict/object should have at least 3 children
    local var_uri = h:query_uri(var_url)
    MiniTest.expect.equality(h:query_count(var_uri .. "/children") >= 3, true)
  end

  T["children link back to parent"] = function()
    local h = ctx.create()
    h:fixture("nested-dict")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step once to define data (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Get data variable and fetch children
    local var_url = "@frame/scopes[0]/variables(name=data)[0]"
    h:query_call(var_url, "fetchChildren")
    h:wait_url(var_url .. "/children[0]")

    -- Check child exists and links back to parent
    local var_uri = h:query_uri(var_url)
    MiniTest.expect.equality(h:query_count(var_uri .. "/children") >= 1, true)
    MiniTest.expect.equality(h:query_field_uri(var_uri .. "/children[0]", "parent"), var_uri)
  end

  T["variable:fetchChildren() handles nested structures"] = function()
    local h = ctx.create()
    h:fixture("nested-dict")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step once to define nested (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Get nested variable and fetch children
    local var_url = "@frame/scopes[0]/variables(name=data)[0]"
    h:query_call(var_url, "fetchChildren")
    h:wait_url(var_url .. "/children[0]")

    -- Dict/object should have children
    local var_uri = h:query_uri(var_url)
    MiniTest.expect.equality(h:query_count(var_uri .. "/children") >= 2, true)
  end
end)
