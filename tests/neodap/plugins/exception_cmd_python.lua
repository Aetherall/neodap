local harness = require("helpers.test_harness")

-- Python-specific exception filter API tests
-- Tests use the new binding pattern: global ExceptionFilter + per-session ExceptionFilterBinding
local adapter = harness.for_adapter("python")

local T = MiniTest.new_set({
  hooks = adapter.hooks,
})

T["dap_exception_api"] = MiniTest.new_set()

T["dap_exception_api"]["toggle creates session override"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:use_plugin("neodap.plugins.exception_cmd")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Get the filter ID from the global filter
  local filter_id = h:query_field("/exceptionFilters[0]", "filterId")
  local global_default = h:query_field("/exceptionFilters[0]", "defaultEnabled") or false
  local target = not global_default

  -- Toggle should create an override on the binding
  h:cmd("DapException toggle " .. filter_id)
  h:wait(50)

  -- The binding's enabled field should now be set (not nil)
  local binding_enabled = h:query_field("/sessions[0]/exceptionFilterBindings[0]", "enabled")
  MiniTest.expect.equality(binding_enabled, target)
end

T["dap_exception_api"]["enable sets binding override to true"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:use_plugin("neodap.plugins.exception_cmd")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  local filter_id = h:query_field("/exceptionFilters[0]", "filterId")
  h:cmd("DapException disable " .. filter_id)

  h:cmd("DapException enable " .. filter_id)
  h:wait(50)

  MiniTest.expect.equality(h:query_field("/sessions[0]/exceptionFilterBindings[0]", "enabled"), true)
end

T["dap_exception_api"]["disable sets binding override to false"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:use_plugin("neodap.plugins.exception_cmd")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  local filter_id = h:query_field("/exceptionFilters[0]", "filterId")
  h:cmd("DapException enable " .. filter_id)

  h:cmd("DapException disable " .. filter_id)
  h:wait(50)

  MiniTest.expect.equality(h:query_field("/sessions[0]/exceptionFilterBindings[0]", "enabled"), false)
end

T["dap_exception_api"]["clear removes binding override"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:use_plugin("neodap.plugins.exception_cmd")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  local filter_id = h:query_field("/exceptionFilters[0]", "filterId")
  -- First set an override
  h:cmd("DapException enable " .. filter_id)
  h:wait(50)
  MiniTest.expect.equality(h:query_field("/sessions[0]/exceptionFilterBindings[0]", "enabled"), true)

  -- Clear the override
  h:cmd("DapException clear " .. filter_id)
  h:wait(50)

  -- enabled should be nil (using global default)
  -- vim.NIL is returned from child process for nil values
  local enabled = h:query_field("/sessions[0]/exceptionFilterBindings[0]", "enabled")
  MiniTest.expect.equality(enabled == nil or enabled == vim.NIL, true)
end

T["dap_exception_api"]["set_condition updates binding condition"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:use_plugin("neodap.plugins.exception_cmd")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  local filter_id = h:query_field("/exceptionFilters[0]", "filterId")

  h:cmd("DapException condition " .. filter_id .. " x > 0")
  h:wait(50)

  MiniTest.expect.equality(h:query_field("/sessions[0]/exceptionFilterBindings[0]", "condition"), "x > 0")
end

return T
