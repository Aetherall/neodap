local harness = require("helpers.test_harness")

local T = harness.integration("source_buffer", function(T, ctx)
  T["opens dap://source/ buffer with file content from session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.source_buffer")

    -- Get source key from frame's source
    local source_key = h:query_field("@frame/source[0]", "key")
    MiniTest.expect.equality(source_key ~= nil, true)

    -- Open source buffer and check content
    h.child.cmd("edit dap://source/source:" .. source_key)
    h:wait(1000)

    local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)
    local content = table.concat(lines, "\n")
    local has_content = content:find("=") ~= nil

    MiniTest.expect.equality(has_content, true)
    MiniTest.expect.equality(h.child.bo.buftype, "nofile")
    MiniTest.expect.equality(h.child.bo.swapfile, false)
    MiniTest.expect.equality(h.child.bo.modifiable, false)
  end

  T["buffer name matches dap://source/ URI"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.source_buffer")

    -- Get source key from frame's source
    local source_key = h:query_field("@frame/source[0]", "key")
    MiniTest.expect.equality(source_key ~= nil, true)

    -- Open source buffer
    h.child.cmd("edit dap://source/source:" .. source_key)
    h:wait(500)

    local buf_name = h.child.api.nvim_buf_get_name(0)
    local starts_with_dap = buf_name:find("^dap://source/") ~= nil

    MiniTest.expect.equality(starts_with_dap, true)
  end

  T["shows error for non-existent source key"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.source_buffer")

    -- Try to open a non-existent source
    h.child.cmd("edit dap://source/source:nonexistent-key-12345")

    local lines = h.child.api.nvim_buf_get_lines(0, 0, 1, false)
    local first_line = lines[1] or ""

    -- entity_buffer shows validation error
    MiniTest.expect.equality(first_line:find("Error") ~= nil, true)
  end

  T["content matches actual file content"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.source_buffer")

    -- Get source key from frame's source (the actual source file we're debugging)
    local source_key = h:query_field("@frame/source[0]", "key")
    MiniTest.expect.equality(source_key ~= nil, true)

    -- Read actual file content (from frame source path)
    local source_path = h:query_field("@frame/source[0]", "path")
    local actual_lines = h.child.fn.readfile(source_path)

    -- Open source buffer
    h.child.cmd("edit dap://source/source:" .. source_key)
    h:wait(500)

    -- Compare buffer content with actual file
    local buf_lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

    MiniTest.expect.equality(#buf_lines, #actual_lines)
    for i, line in ipairs(buf_lines) do
      MiniTest.expect.equality(line, actual_lines[i])
    end
  end

  T["multiple sources can be opened"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.source_buffer")

    -- Get source count and first source key from frame
    local source_count = h:query_count("/sources")
    local source_key1 = h:query_field("@frame/source[0]", "key")

    MiniTest.expect.equality(source_count >= 1, true)
    MiniTest.expect.equality(source_key1 ~= nil, true)

    -- Open first source
    h.child.cmd("edit dap://source/source:" .. source_key1)
    local buf1 = h.child.api.nvim_get_current_buf()
    h:wait(500)

    MiniTest.expect.equality(buf1 ~= nil, true)

    -- If there are multiple sources, test opening a second one
    if source_count >= 2 then
      -- Get a different source from the collection
      local source_key2 = h:query_field("/sources[0]", "key")
      -- If same as first, try the next one
      if source_key2 == source_key1 then
        source_key2 = h:query_field("/sources[1]", "key")
      end
      if source_key2 and source_key2 ~= source_key1 then
        h.child.cmd("edit dap://source/source:" .. source_key2)
        local buf2 = h.child.api.nvim_get_current_buf()
        MiniTest.expect.equality(buf2 ~= nil, true)
        MiniTest.expect.equality(buf1 ~= buf2, true)
      end
    end
  end
end)

return T
