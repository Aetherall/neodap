local harness = require("helpers.test_harness")

-- Output tests are Python-only because js-debug routes console output
-- through the debugger console rather than emitting DAP output events
local adapter = harness.for_adapter("python")

local T = MiniTest.new_set({
  hooks = adapter.hooks,
})

T["dap_output"] = MiniTest.new_set()

T["dap_output"]["output event creates entity"] = function()
  local h = adapter.harness()
  h:fixture("hello")
  h:cmd("DapLaunch Debug")
  h:wait_terminated()

  MiniTest.expect.equality(h:query_count("/sessions[0]/outputs") > 0, true)
end

T["dap_output"]["output has text property"] = function()
  local h = adapter.harness()
  h:fixture("hello")
  h:cmd("DapLaunch Debug")
  h:wait_terminated()

  local text = h:query_field("/sessions[0]/outputs[0]", "text")
  MiniTest.expect.equality(text ~= nil and text ~= "", true)
end

T["dap_output"]["output has category"] = function()
  local h = adapter.harness()
  h:fixture("hello")
  h:cmd("DapLaunch Debug")
  h:wait_terminated()

  MiniTest.expect.equality(h:query_field("/sessions[0]/outputs[0]", "category") ~= nil, true)
end

T["dap_output"]["output entities have sequential seq values"] = function()
  local h = adapter.harness()
  h:fixture("hello")
  h:cmd("DapLaunch Debug")
  h:wait_terminated()

  local count = h:query_count("/sessions[0]/outputs")
  if count >= 2 then
    local seq_values = {}
    for i = 0, count - 1 do
      local seq = h:query_field(string.format("/sessions[0]/outputs[%d]", i), "seq")
      table.insert(seq_values, seq)
    end
    table.sort(seq_values)
    for i = 2, #seq_values do
      MiniTest.expect.equality(seq_values[i], seq_values[i - 1] + 1)
    end
  end
end

return T
