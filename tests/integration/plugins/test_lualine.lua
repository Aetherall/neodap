local harness = require("helpers.test_harness")

return harness.integration("lualine", function(T, ctx)
  -- User scenario: Component returns empty when no debug session
  T["component returns empty with no session"] = function()
    local h = ctx.create()

    -- Load lualine plugin and store component
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine_component = _G.neodap.use(lualine)
    ]])

    -- Component should return empty string
    local result = h:get("_G.lualine_component()")
    MiniTest.expect.equality(result, "")
  end

  -- User scenario: Component shows session info after launch
  T["component shows session after launch"] = function()
    local h = ctx.create()

    -- Load plugins
    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine_component = _G.neodap.use(lualine)
    ]])

    -- Launch debug session
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Component should include "stopped" (thread state)
    local result = h:get("_G.lualine_component()")
    MiniTest.expect.equality(result:match("stopped") ~= nil, true)
  end

  -- User scenario: Component updates when stepping
  T["component updates on step"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine_component = _G.neodap.use(lualine, { session = false, thread = false, frame = true })
    ]])

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Get initial result
    local initial = h:get("_G.lualine_component()")

    -- Step to next line
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Component should show different line
    local after_step = h:get("_G.lualine_component()")
    MiniTest.expect.equality(after_step:match(":2") ~= nil, true)
    MiniTest.expect.equality(initial ~= after_step, true)
  end

  -- User scenario: Custom format function
  T["custom format function works"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine_component = _G.neodap.use(lualine, {
        format = function(ctx)
          if not ctx.session then return "idle" end
          return "DEBUG"
        end
      })
    ]])

    -- Before launch: custom format returns "idle"
    local result = h:get("_G.lualine_component()")
    MiniTest.expect.equality(result, "idle")

    -- After launch: custom format returns "DEBUG"
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    result = h:get("_G.lualine_component()")
    MiniTest.expect.equality(result, "DEBUG")
  end

  -- User scenario: Separator configuration
  T["separator configuration works"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine_component = _G.neodap.use(lualine, { separator = " | " })
    ]])

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    local result = h:get("_G.lualine_component()")
    MiniTest.expect.equality(result:match(" | ") ~= nil, true)
  end

  -- User scenario: Empty config option
  T["empty config option works"] = function()
    local h = ctx.create()

    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine_component = _G.neodap.use(lualine, { empty = "no debug" })
    ]])

    local result = h:get("_G.lualine_component()")
    MiniTest.expect.equality(result, "no debug")
  end

  -- New API tests: Individual components

  -- User scenario: Returns table of component factories with new API
  T["new API returns table of components"] = function()
    local h = ctx.create()

    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine = _G.neodap.use(lualine)
    ]])

    -- Should have individual component factory functions
    MiniTest.expect.equality(h:get("type(_G.lualine.status)"), "function")
    MiniTest.expect.equality(h:get("type(_G.lualine.session)"), "function")
    MiniTest.expect.equality(h:get("type(_G.lualine.thread)"), "function")
    MiniTest.expect.equality(h:get("type(_G.lualine.frame)"), "function")
    MiniTest.expect.equality(h:get("type(_G.lualine.context)"), "function")

    -- Calling them should return component functions
    MiniTest.expect.equality(h:get("type(_G.lualine.status())"), "function")
  end

  -- User scenario: Status component shows icon for stopped state
  T["status component shows stopped icon"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine = _G.neodap.use(lualine)
      _G.status_component = _G.lualine.status()
    ]])

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Status should show stopped icon (from presentation layer)
    local result = h:get("_G.status_component()")
    MiniTest.expect.equality(result, "⏸")
  end

  -- User scenario: Session component shows adapter name
  T["session component shows adapter name"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine = _G.neodap.use(lualine)
      _G.session_component = _G.lualine.session()
    ]])

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Session should show the adapter name
    local result = h:get("_G.session_component()")
    MiniTest.expect.equality(result ~= "", true)
  end

  -- User scenario: Thread component shows state
  T["thread component shows state"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine = _G.neodap.use(lualine)
      _G.thread_component = _G.lualine.thread()
    ]])

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Thread should include "stopped"
    local result = h:get("_G.thread_component()")
    MiniTest.expect.equality(result:match("stopped") ~= nil, true)
  end

  -- User scenario: Frame component shows function:line
  T["frame component shows function and line"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine = _G.neodap.use(lualine)
      _G.frame_component = _G.lualine.frame()
    ]])

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Frame should show function name with line number
    local result = h:get("_G.frame_component()")
    MiniTest.expect.equality(result:match(":1") ~= nil or result:match(":2") ~= nil, true)
  end

  -- User scenario: Table is callable for backward compat
  T["new API table is callable"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine = _G.neodap.use(lualine)
      _G.context_component = _G.lualine.context()
    ]])

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Calling the table should return context (same as context component)
    local call_result = h:get("_G.lualine()")
    local context_result = h:get("_G.context_component()")
    MiniTest.expect.equality(call_result, context_result)
  end

  -- User scenario: Component factory functions accept options
  T["component factory functions work"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h.child.lua([[
      local lualine = require("neodap.plugins.lualine")
      _G.lualine = _G.neodap.use(lualine)
      -- Create status component and frame component with options
      _G.custom_status = _G.lualine.status()
      _G.custom_frame = _G.lualine.frame({ show_line = false })
    ]])

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Status should show stopped icon from presentation layer
    local status_result = h:get("_G.custom_status()")
    MiniTest.expect.equality(status_result, "⏸")

    -- Frame with show_line=false should not include ":"
    local frame_result = h:get("_G.custom_frame()")
    MiniTest.expect.equality(frame_result:match(":") == nil, true)
  end
end)
