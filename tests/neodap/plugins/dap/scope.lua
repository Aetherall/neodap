local harness = require("helpers.test_harness")

return harness.integration("scope", function(T, ctx)
  T["scope:fetchVariables() populates variable entities"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to define variables (line 1 -> 2 -> 3)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Check we have variables
    MiniTest.expect.equality(h:query_is_nil("@frame/scopes[0]/variables(name=x)[0]"), false)
    MiniTest.expect.equality(h:query_is_nil("@frame/scopes[0]/variables(name=y)[0]"), false)
  end

  T["variables link back to scope"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step once to define x (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Check variable exists and links back to scope
    MiniTest.expect.equality(h:query_count("@frame/scopes[0]/variables") >= 1, true)
    MiniTest.expect.equality(h:query_field_uri("@frame/scopes[0]/variables[0]", "scope"), h:query_uri("@frame/scopes[0]"))
  end

  T["scope has correct properties"] = function()
    local h = ctx.create()
    h:fixture("hello")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    -- Collect scope properties
    local scopes_info = h:get_scopes_info()

    -- Should have at least one scope
    MiniTest.expect.equality(#scopes_info >= 1, true)
    -- First scope should have variablesReference > 0
    MiniTest.expect.equality(scopes_info[1].variablesReference > 0, true)
    MiniTest.expect.equality(type(scopes_info[1].name), "string")
  end

  T["variables have values"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to define x (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Check x has a value
    local x_url = "@frame/scopes[0]/variables(name=x)[0]"
    MiniTest.expect.equality(h:query_is_nil(x_url), false)
    MiniTest.expect.equality(h:query_field(x_url, "value") ~= nil, true)
  end
end)
