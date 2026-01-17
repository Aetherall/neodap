local harness = require("helpers.test_harness")

-- Python-specific exception filter API tests
local adapter = harness.for_adapter("python")

local T = MiniTest.new_set({
  hooks = adapter.hooks,
})

T["dap_exception_api"] = MiniTest.new_set()

T["dap_exception_api"]["toggle changes enabled state"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:use_plugin("neodap.plugins.exception_cmd")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  local filter_id = h:query_field("/sessions[0]/exceptionFilters[0]", "filterId")
  local filter_url = string.format("/sessions[0]/exceptionFilters(filterId=%s)[0]", filter_id)
  local initial = h:query_field(filter_url, "enabled")
  local target = not initial

  h:cmd("DapException toggle " .. filter_id)
  h:wait_url(string.format("/sessions/exceptionFilters(filterId=%s,enabled=%s)", filter_id, tostring(target)))

  MiniTest.expect.equality(h:query_field(filter_url, "enabled"), target)
end

T["dap_exception_api"]["enable sets enabled to true"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:use_plugin("neodap.plugins.exception_cmd")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  local filter_id = h:query_field("/sessions[0]/exceptionFilters[0]", "filterId")
  local filter_url = string.format("/sessions[0]/exceptionFilters(filterId=%s)[0]", filter_id)
  h:cmd("DapException disable " .. filter_id)

  h:cmd("DapException enable " .. filter_id)
  h:wait_url(string.format("/sessions/exceptionFilters(filterId=%s,enabled=true)", filter_id))

  MiniTest.expect.equality(h:query_field(filter_url, "enabled"), true)
end

T["dap_exception_api"]["disable sets enabled to false"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:use_plugin("neodap.plugins.exception_cmd")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  local filter_id = h:query_field("/sessions[0]/exceptionFilters[0]", "filterId")
  local filter_url = string.format("/sessions[0]/exceptionFilters(filterId=%s)[0]", filter_id)
  h:cmd("DapException enable " .. filter_id)

  h:cmd("DapException disable " .. filter_id)
  h:wait_url(string.format("/sessions/exceptionFilters(filterId=%s,enabled=false)", filter_id))

  MiniTest.expect.equality(h:query_field(filter_url, "enabled"), false)
end

T["dap_exception_api"]["set_condition updates condition"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:use_plugin("neodap.plugins.exception_cmd")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  local filter_id = h:query_field("/sessions[0]/exceptionFilters[0]", "filterId")

  h:cmd("DapException condition " .. filter_id .. " x > 0")
  h:wait(50)

  MiniTest.expect.equality(h:query_field("/sessions[0]/exceptionFilters(filterId=" .. filter_id .. ")[0]", "condition"), "x > 0")
end

return T
