-- Tests for url_buffer plugin (dap://url/ URI protocol for debugging URL queries)
local harness = require("helpers.test_harness")

return harness.integration("url_buffer", function(T, ctx)

  T["shows empty sessions before launch"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")

    h:open_url_buffer("/sessions")
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["shows session after launch"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:open_url_buffer("/sessions")
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["shows threads for focused frame"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:focus("@frame")

    h:open_url_buffer("@frame/stack/thread/session/threads")
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["shows scopes for focused frame"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:focus("@frame")

    h:open_url_buffer("@frame/scopes")
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["updates reactively when session added"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")

    -- Open buffer before any session exists
    h:open_url_buffer("/sessions")

    -- Now launch a session
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    vim.loop.sleep(300) -- Wait for reactive update

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  --
  -- Complex URL traversal tests
  --
  -- These tests open the buffer FIRST, then make changes, proving reactivity
  --

  T["complex: frames before fetch"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")

    -- Open buffer BEFORE launch - should show 0 frames
    h:open_url_buffer("/sessions/threads/stacks/frames")

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["complex: frames[0] at entry"] = function()
    -- Skip for JavaScript - breakpoint timing issues
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")

    -- Launch and stop at entry (module level)
    h:fixture("with-function")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Show top frame at module entry point
    h:open_url_buffer("/sessions/threads/stacks/frames[0]")
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["complex: frames[0] after continue"] = function()
    -- Skip for JavaScript - breakpoint timing issues
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")
    h:init_plugin("neodap.plugins.breakpoint_cmd")

    -- Launch and stop at entry
    h:fixture("with-function")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Set breakpoint before opening url_buffer
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Open buffer showing top frame BEFORE continuing
    h:open_url_buffer("/sessions/threads/stacks/frames[0]")

    -- Continue to breakpoint inside inner() - stack will be deeper
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    vim.loop.sleep(300)

    -- Buffer should now show NEW top frame (inner function)
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  --
  -- Dynamic resolution reactivity tests
  --
  -- These tests prove that the buffer content updates reactively
  -- when the underlying context changes.
  --

  T["reactivity: sessions before launch"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")

    -- Open buffer BEFORE any session exists - should be empty
    h:open_url_buffer("/sessions")
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["reactivity: sessions after launch"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.url_buffer")

    -- Open buffer before launch
    h:open_url_buffer("/sessions")

    -- Launch a session
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    vim.loop.sleep(300) -- Wait for reactive update

    -- Screenshot shows session appeared reactively
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

end)
