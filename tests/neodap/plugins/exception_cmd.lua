local harness = require("helpers.test_harness")

-- Common exception filter tests that run on both adapters
-- Tests basic schema and entity creation from adapter capabilities
return harness.integration("dap_exception", function(T, ctx)
  T["exception filter bindings created from capabilities"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_count("/sessions[0]/exceptionFilterBindings") > 0, true)
  end

  T["global exception filters created from capabilities"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_count("/exceptionFilters") > 0, true)
  end

  T["exception filter has label"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local label = h:query_field("/exceptionFilters[0]", "label")
    MiniTest.expect.equality(label ~= nil and label ~= "", true)
  end

  T["DapException lists filters without error"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.exception_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Command should execute without error
    h:cmd("DapException")
  end
end)
