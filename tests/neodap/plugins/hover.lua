-- Visual tests for hover plugin (in-process LSP for DAP hover)
local harness = require("helpers.test_harness")

local T = harness.integration("hover", function(T, ctx)
  -------------------------------------------------------------------------------
  -- Basic Hover Tests
  -------------------------------------------------------------------------------

  T["shows hover value when stopped"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.hover")
    h:use_plugin("neodap.plugins.jump_stop")

    -- Set up K keybind for hover
    h:cmd("nnoremap K <cmd>lua vim.lsp.buf.hover()<CR>")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to define variable x
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
    h:wait(500) -- Wait for jump_stop to update focus and open file

    -- Position cursor on 'x' and trigger hover
    -- Python: x = 1 -> x at col 0
    -- JavaScript: const x = 1; -> x at col 6
    local x_col = ctx.adapter_name == "javascript" and 6 or 0
    h:set_cursor(1, x_col)
    h.child.type_keys("K")
    h:wait(1000) -- Wait for hover to appear

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["hover shows type information"] = function()
    local h = ctx.create()
    h:fixture("nested-dict")
    h:setup_visual()
    h:use_plugin("neodap.plugins.hover")
    h:use_plugin("neodap.plugins.jump_stop")

    h:cmd("nnoremap K <cmd>lua vim.lsp.buf.hover()<CR>")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to define the dict variable
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
    h:wait(500)

    -- Position cursor on 'data' variable and trigger hover
    -- Python: data = {...} -> data at col 0
    -- JavaScript: const data = {...} -> data at col 6
    local data_col = ctx.adapter_name == "javascript" and 6 or 0
    h:set_cursor(1, data_col)
    h.child.type_keys("K")
    h:wait(1000)

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["hover returns nil when no debug session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.hover")

    h:cmd("nnoremap K <cmd>lua vim.lsp.buf.hover()<CR>")

    -- Edit main file but don't start debug session
    h:edit_main()
    h:wait(100)

    -- Position cursor on 'x' and try hover - should show nothing (no session)
    local x_col = ctx.adapter_name == "javascript" and 6 or 0
    h:set_cursor(1, x_col)
    h.child.type_keys("K")
    h:wait(500)

    -- Should show no hover window (no session to evaluate)
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  -------------------------------------------------------------------------------
  -- Focus Context Tests
  -------------------------------------------------------------------------------

  T["hover works after stepping"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.hover")
    h:use_plugin("neodap.plugins.jump_stop")

    h:cmd("nnoremap K <cmd>lua vim.lsp.buf.hover()<CR>")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(500)

    -- Step over to define x
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
    h:wait(1000) -- Wait for jump_stop to update focus

    -- Hover should work after stepping (focus updated by jump_stop)
    local x_col = ctx.adapter_name == "javascript" and 6 or 0
    h:set_cursor(1, x_col)
    h.child.type_keys("K")
    h:wait(1000)

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["hover uses focused frame in call stack"] = function()
    -- Skip for Python - function call syntax differs
    if ctx.adapter_name == "python" then
      return
    end

    local h = ctx.create()
    h:init_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.hover")
    h:use_plugin("neodap.plugins.jump_stop")
    h:fixture("with-function")
    h:setup_visual()

    h:cmd("nnoremap K <cmd>lua vim.lsp.buf.hover()<CR>")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Set breakpoint inside inner function (line 2)
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Continue to breakpoint - should have multiple frames
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:wait(500)

    -- Should have at least 2 frames now
    local frame_count = h:query_count("@thread/stack/frames")
    MiniTest.expect.equality(frame_count >= 2, true)

    -- Focus inner frame and hover on x (local variable in inner)
    h:cmd("DapFocus @thread/stack/frames[0]")
    h:wait(200)
    h:set_cursor(2, 8) -- const x = 1; -> x at col 8
    h.child.type_keys("K")
    h:wait(1000)

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  -------------------------------------------------------------------------------
  -- Hover Window Interaction Tests
  -------------------------------------------------------------------------------

  T["hover window can be closed with Escape"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.hover")
    h:use_plugin("neodap.plugins.jump_stop")

    h:cmd("nnoremap K <cmd>lua vim.lsp.buf.hover()<CR>")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to define variable
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
    h:wait(500)

    -- Open hover
    local x_col = ctx.adapter_name == "javascript" and 6 or 0
    h:set_cursor(1, x_col)
    h.child.type_keys("K")
    h:wait(1000)

    -- Close with Escape
    h.child.type_keys("<Esc>")
    h:wait(200)

    -- Hover should be closed
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end
end)

return T
