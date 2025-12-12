-- Tests for variable_edit plugin (dap://var/ URI protocol for inline variable editing)
local harness = require("helpers.test_harness")

-- Use Python adapter as it reliably supports setVariable
local adapter = harness.for_adapter("python")

local T = MiniTest.new_set({
  hooks = adapter.hooks,
})

T["variable_edit"] = MiniTest.new_set()

T["variable_edit"]["opens dap-var buffer with correct settings"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Step to get variables defined (line 1 -> 2 -> 3)
  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")
  local var_url = "@frame/scopes[0]/variables(name=x)[0]"
  local var_uri = h:query_uri(var_url)
  MiniTest.expect.equality(var_uri ~= nil, true)

  -- Setup variable_edit plugin
  h:use_plugin("neodap.plugins.variable_edit")

  -- Open dap-var buffer using the URI
  h.child.cmd("edit dap://var/" .. var_uri)
  vim.loop.sleep(200)

  -- Check buffer settings
  local bufname = h.child.api.nvim_buf_get_name(0)
  local buftype = h.child.bo.buftype
  local modifiable = h.child.bo.modifiable
  local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Check that buffer name ends with dap://var/ URI
  MiniTest.expect.equality(bufname:match("dap://var/") ~= nil, true)
  MiniTest.expect.equality(buftype, "acwrite")
  MiniTest.expect.equality(modifiable, true)
  MiniTest.expect.equality(lines[1], "42")
end

T["variable_edit"]["shows virtual text indicator with variable info"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  local var_url = "@frame/scopes[0]/variables(name=x)[0]"
  local var_uri = h:query_uri(var_url)
  h.child.cmd("edit dap://var/" .. var_uri)
  vim.loop.sleep(200)

  -- Check for virtual text extmark
  local bufnr = h.child.api.nvim_get_current_buf()
  local ns = h.child.api.nvim_get_namespaces()["neodap-variable-edit"]
  local extmarks = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

  MiniTest.expect.equality(#extmarks > 0, true)
  local virt_text = extmarks[1][4].virt_text[1][1]
  -- Should contain variable name
  MiniTest.expect.equality(virt_text:match("x") ~= nil, true)
end

T["variable_edit"]["shows modified indicator when value changed"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  local var_url = "@frame/scopes[0]/variables(name=x)[0]"
  local var_uri = h:query_uri(var_url)
  h.child.cmd("edit dap://var/" .. var_uri)
  vim.loop.sleep(200)

  -- Modify the value
  h.child.cmd("normal! ggC99")
  vim.loop.sleep(100)

  -- Check for [modified] in virtual text
  local bufnr = h.child.api.nvim_get_current_buf()
  local ns = h.child.api.nvim_get_namespaces()["neodap-variable-edit"]
  local extmarks = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local virt_text_parts = {}
  for _, part in ipairs(extmarks[1][4].virt_text) do
    table.insert(virt_text_parts, part[1])
  end
  local virt_text = table.concat(virt_text_parts, "")
  MiniTest.expect.equality(virt_text:match("%[modified%]") ~= nil, true)
end

T["variable_edit"]["reset with u key restores original value"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  local var_url = "@frame/scopes[0]/variables(name=x)[0]"
  local var_uri = h:query_uri(var_url)
  h.child.cmd("edit dap://var/" .. var_uri)
  vim.loop.sleep(200)

  -- Modify the value
  h.child.cmd("normal! ggC99")
  vim.loop.sleep(100)

  -- Press u to reset
  h.child.cmd("normal! u")
  vim.loop.sleep(100)

  -- Check value is restored
  local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

  MiniTest.expect.equality(lines[1], "42")
end

T["variable_edit"]["close with q key closes buffer"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  local var_url = "@frame/scopes[0]/variables(name=x)[0]"
  local var_uri = h:query_uri(var_url)
  h.child.cmd("edit dap://var/" .. var_uri)
  vim.loop.sleep(200)

  -- Store buffer number
  local edit_bufnr = h.child.api.nvim_get_current_buf()

  -- Exit insert mode first, then press q to close
  h.child.type_keys("<Esc>")
  vim.loop.sleep(50)
  h.child.type_keys("q")
  vim.loop.sleep(100)

  -- Check buffer is no longer valid
  local buf_valid = h.child.api.nvim_buf_is_valid(edit_bufnr)

  MiniTest.expect.equality(buf_valid, false)
end

T["variable_edit"]["edit API opens buffer for variable"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  -- Open variable edit buffer via URL
  h.child.cmd("edit dap://var/@frame/scopes[0]/variables:x")
  vim.loop.sleep(200)

  -- Check buffer opened
  local bufname = h.child.api.nvim_buf_get_name(0)
  local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

  MiniTest.expect.equality(bufname:match("dap://var/") ~= nil, true)
  MiniTest.expect.equality(lines[1], "42")
end

T["variable_edit"]["submits new value via Enter in normal mode"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  -- Check original value via query
  local original_value = h:query_field("@frame/scopes[0]/variables:x", "value")
  MiniTest.expect.equality(original_value, "42")

  -- Open variable edit buffer via URL
  h.child.cmd("edit dap://var/@frame/scopes[0]/variables:x")
  vim.loop.sleep(200)

  -- Change value and submit using type_keys to simulate user input
  h.child.type_keys("<Esc>")
  vim.loop.sleep(50)
  h.child.type_keys("cc99")
  vim.loop.sleep(50)
  h.child.type_keys("<Esc>")
  vim.loop.sleep(50)
  h.child.type_keys("<CR>")
  vim.loop.sleep(500)

  -- Check entity was updated via query
  local updated_value = h:query_field("@frame/scopes[0]/variables:x", "value")
  MiniTest.expect.equality(updated_value, "99")
end

T["variable_edit"]["closeonsubmit option closes buffer after submit"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  -- Open with closeonsubmit option using URL pattern
  h.child.cmd("edit dap://var/@frame/scopes[0]/variables:x?closeonsubmit")
  vim.loop.sleep(200)

  -- Store buffer number
  local edit_bufnr = h.child.api.nvim_get_current_buf()

  -- Change value and submit
  h.child.cmd("stopinsert")
  h.child.cmd("normal! ggC99")
  vim.loop.sleep(100)
  h.child.cmd("stopinsert")
  h.child.type_keys("<CR>")
  vim.loop.sleep(500)

  -- Check buffer is closed
  local buf_valid = h.child.api.nvim_buf_is_valid(edit_bufnr)

  MiniTest.expect.equality(buf_valid, false)
end

T["variable_edit"]["does not submit when value unchanged"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  -- Open via URL pattern
  h.child.cmd("edit dap://var/@frame/scopes[0]/variables:x")
  vim.loop.sleep(200)

  -- Submit without changing value - entity_buffer.submit shows "no changes" message
  h.child.cmd("stopinsert")
  h.child.type_keys("<CR>")
  vim.loop.sleep(300)

  -- Value should still be 42 (unchanged) - query via entity graph
  local value_after = h:query_field("@frame/scopes[0]/variables:x", "value")
  MiniTest.expect.equality(value_after, "42")
end

T["variable_edit"]["opens buffer via URL with @frame context"] = function()
  local h = adapter.harness()
  h:fixture("var-edit")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Step to get variables defined (line 1 -> 2 -> 3)
  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  -- Open using URL syntax
  h.child.cmd("edit dap://var/@frame/scopes[0]/variables:x")
  vim.loop.sleep(300)

  -- Check buffer content shows variable value
  local bufname = h.child.api.nvim_buf_get_name(0)
  local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

  MiniTest.expect.equality(bufname:match("@frame/scopes%[0%]/variables:x") ~= nil, true)
  MiniTest.expect.equality(lines[1], "42")
end

T["variable_edit"]["URL buffer updates when stepping to new frame"] = function()
  local h = adapter.harness()
  h:fixture("debugger-stack")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Step to x = 42 (line 1 -> 5 -> 6)
  h:cmd("DapStep over")  -- def inner() -> x = 42
  h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=5)[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapStep over")  -- x = 42 -> inner()
  h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  -- Open URL-bound buffer for variable x
  h.child.cmd("edit dap://var/@frame/scopes[0]/variables:x")
  vim.loop.sleep(300)

  -- Store buffer number and verify initial value
  local edit_bufnr = h.child.api.nvim_get_current_buf()
  local initial_lines = h.child.api.nvim_buf_get_lines(edit_bufnr, 0, -1, false)
  MiniTest.expect.equality(initial_lines[1], "42")

  -- Step into inner() and to x = 99 (line 6 -> 2 -> 3)
  h:cmd("DapStep into")
  h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapStep over")  -- x = 99 -> pass
  h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")
  vim.loop.sleep(300)

  -- Buffer should update to show new variable value
  local updated_lines = h.child.api.nvim_buf_get_lines(edit_bufnr, 0, -1, false)

  MiniTest.expect.equality(updated_lines[1], "99")
end

T["variable_edit"]["URL buffer does not update when dirty"] = function()
  local h = adapter.harness()
  h:fixture("debugger-stack")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:cmd("DapStep over")  -- def inner()
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapStep over")  -- x = 42
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")

  h:use_plugin("neodap.plugins.variable_edit")

  -- Open URL-bound buffer
  h.child.cmd("edit dap://var/@frame/scopes[0]/variables:x")
  vim.loop.sleep(300)

  -- Store buffer number
  local edit_bufnr = h.child.api.nvim_get_current_buf()

  -- Modify buffer (make it dirty)
  h.child.cmd("stopinsert")
  h.child.cmd("normal! gg0C123")
  vim.loop.sleep(100)

  -- Verify buffer is dirty
  local lines_before = h.child.api.nvim_buf_get_lines(edit_bufnr, 0, -1, false)
  MiniTest.expect.equality(lines_before[1], "123")

  -- Step into inner()
  h:cmd("DapStep into")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapStep over")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  h:query_call("@frame", "fetchScopes")
  h:wait_url("@frame/scopes[0]")
  h:wait_url("@frame/scopes[0]")
  h:query_call("@frame/scopes[0]", "fetchVariables")
  h:wait_url("@frame/scopes[0]/variables[0]")
  vim.loop.sleep(300)

  -- Buffer should NOT update because it's dirty
  local lines_after = h.child.api.nvim_buf_get_lines(edit_bufnr, 0, -1, false)

  -- Should still show user's edit, not the new variable value
  MiniTest.expect.equality(lines_after[1], "123")
end

return T
