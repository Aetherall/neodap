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
end)
