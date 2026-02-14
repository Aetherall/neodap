local harness = require("helpers.test_harness")

return harness.integration("components", function(T, ctx)

  -- Helpers
  local function launch_and_focus(h)
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  end

  local function setup_bp(h)
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
  end

  local function setup_bp_verified(h)
    setup_bp(h)
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")
  end

  -- ========================================================================
  -- Session icon
  -- ========================================================================

  T["session icon stopped"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local icon = h:query_component("icon", "@session")
    MiniTest.expect.equality(icon.text, "⏸")
    MiniTest.expect.equality(icon.hl, "DapStopped")
  end

  T["session icon terminated"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    -- Use absolute URL since @session becomes nil when focus is cleared during termination
    local index = h.adapter.name == "javascript" and 1 or 0
    local session_url = string.format("/sessions[%d]", index)
    h:cmd("DapTerminate")
    h:wait_field(session_url, "state", "terminated")
    local icon = h:query_component("icon", session_url)
    MiniTest.expect.equality(icon.text, "⏹")
    MiniTest.expect.equality(icon.hl, "DapTerminated")
  end

  -- ========================================================================
  -- Session title
  -- ========================================================================

  T["session title shows name"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local title = h:query_component("title", "@session")
    MiniTest.expect.equality(title.text ~= nil and title.text ~= "", true)
    MiniTest.expect.equality(title.hl, "DapSession")
  end

  -- ========================================================================
  -- Session state
  -- ========================================================================

  T["session state stopped"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local state = h:query_component("state", "@session")
    MiniTest.expect.equality(state.text, "stopped")
    MiniTest.expect.equality(state.hl, "DapStopped")
  end

  T["session state terminated"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    -- Use absolute URL since @session becomes nil when focus is cleared during termination
    local index = h.adapter.name == "javascript" and 1 or 0
    local session_url = string.format("/sessions[%d]", index)
    h:cmd("DapTerminate")
    h:wait_field(session_url, "state", "terminated")
    local state = h:query_component("state", session_url)
    MiniTest.expect.equality(state.text, "terminated")
    MiniTest.expect.equality(state.hl, "DapTerminated")
  end

  T["session components returns all registered"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local all = h:query_components("@session")
    MiniTest.expect.equality(all.icon ~= nil, true)
    MiniTest.expect.equality(all.title ~= nil, true)
    MiniTest.expect.equality(all.state ~= nil, true)
  end

  -- ========================================================================
  -- Thread icon
  -- ========================================================================

  T["thread icon stopped"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local icon = h:query_component("icon", "@session/threads[0]")
    MiniTest.expect.equality(icon.text, "⏸")
    MiniTest.expect.equality(icon.hl, "DapStopped")
  end

  -- ========================================================================
  -- Thread title
  -- ========================================================================

  T["thread title shows name"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local title = h:query_component("title", "@session/threads[0]")
    MiniTest.expect.equality(title.text ~= nil and title.text ~= "", true)
    MiniTest.expect.equality(title.hl, "DapThread")
  end

  -- ========================================================================
  -- Thread detail
  -- ========================================================================

  T["thread detail shows thread id"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local detail = h:query_component("detail", "@session/threads[0]")
    MiniTest.expect.equality(detail ~= nil, true)
    MiniTest.expect.equality(detail.text:match("^id=") ~= nil, true)
    MiniTest.expect.equality(detail.hl, "DapComment")
  end

  -- ========================================================================
  -- Thread state
  -- ========================================================================

  T["thread state stopped"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local state = h:query_component("state", "@session/threads[0]")
    MiniTest.expect.equality(state.text, "stopped")
    MiniTest.expect.equality(state.hl, "DapStopped")
  end

  -- ========================================================================
  -- Frame index
  -- ========================================================================

  T["frame index shows frame number"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local index = h:query_component("index", "@frame")
    MiniTest.expect.equality(index.text, "#0")
    MiniTest.expect.equality(index.hl, "DapFrameIndex")
  end

  -- ========================================================================
  -- Frame title
  -- ========================================================================

  T["frame title shows name with default hl"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local title = h:query_component("title", "@frame")
    MiniTest.expect.equality(title.text ~= nil and title.text ~= "", true)
    MiniTest.expect.equality(title.hl, "DapFrame")
  end

  -- ========================================================================
  -- Frame location
  -- ========================================================================

  T["frame location shows file and line"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local loc = h:query_component("location", "@frame")
    MiniTest.expect.equality(loc ~= nil, true)
    MiniTest.expect.equality(loc.text:match("main%.") ~= nil, true)
    MiniTest.expect.equality(loc.text:match(":%d+") ~= nil, true)
    MiniTest.expect.equality(loc.hl, "DapSource")
  end

  -- ========================================================================
  -- Breakpoint icon — all displayState branches
  -- ========================================================================

  T["breakpoint icon unverified"] = function()
    local h = ctx.create()
    setup_bp(h)
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    local icon = h:query_component("icon", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(icon.text, "●")
    MiniTest.expect.equality(icon.hl, "DapBreakpointUnverified")
  end

  T["breakpoint icon disabled"] = function()
    local h = ctx.create()
    setup_bp(h)
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:run_action("disable", "/breakpoints(line=2)[0]")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", false)
    local icon = h:query_component("icon", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(icon.text, "○")
    MiniTest.expect.equality(icon.hl, "DapBreakpointDisabled")
  end

  T["breakpoint icon verified"] = function()
    local h = ctx.create()
    setup_bp_verified(h)
    local icon = h:query_component("icon", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(icon.text, "◉")
    MiniTest.expect.equality(icon.hl, "DapBreakpointVerified")
  end

  T["breakpoint icon hit"] = function()
    local h = ctx.create()
    setup_bp_verified(h)
    h:use_plugin("neodap.plugins.hit_polyfill")
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("/breakpoints(line=2)/bindings(hit=true)")
    local icon = h:query_component("icon", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(icon.text, "◆")
    MiniTest.expect.equality(icon.hl, "DapBreakpointHit")
  end

  -- ========================================================================
  -- Breakpoint state text — all displayState branches
  -- ========================================================================

  T["breakpoint state unverified"] = function()
    local h = ctx.create()
    setup_bp(h)
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    local state = h:query_component("state", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(state.text, "unverified")
    MiniTest.expect.equality(state.hl, "DapBreakpointUnverified")
  end

  T["breakpoint state disabled"] = function()
    local h = ctx.create()
    setup_bp(h)
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:run_action("disable", "/breakpoints(line=2)[0]")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", false)
    local state = h:query_component("state", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(state.text, "disabled")
    MiniTest.expect.equality(state.hl, "DapBreakpointDisabled")
  end

  T["breakpoint state verified"] = function()
    local h = ctx.create()
    setup_bp_verified(h)
    local state = h:query_component("state", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(state.text, "verified")
    MiniTest.expect.equality(state.hl, "DapBreakpointVerified")
  end

  T["breakpoint state hit"] = function()
    local h = ctx.create()
    setup_bp_verified(h)
    h:use_plugin("neodap.plugins.hit_polyfill")
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("/breakpoints(line=2)/bindings(hit=true)")
    local state = h:query_component("state", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(state.text, "hit")
    MiniTest.expect.equality(state.hl, "DapBreakpointHit")
  end

  -- ========================================================================
  -- Breakpoint title
  -- ========================================================================

  T["breakpoint title shows file and line"] = function()
    local h = ctx.create()
    setup_bp(h)
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    local title = h:query_component("title", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(title ~= nil, true)
    MiniTest.expect.equality(title.text:match("main%.") ~= nil, true)
    MiniTest.expect.equality(title.text:match(":2") ~= nil, true)
    MiniTest.expect.equality(title.hl, "DapSource")
  end

  -- ========================================================================
  -- Breakpoint condition — nil / condition / logMessage
  -- ========================================================================

  T["breakpoint condition nil when no condition"] = function()
    local h = ctx.create()
    setup_bp(h)
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    local cond = h:query_component("condition", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(cond, vim.NIL)
  end

  T["breakpoint condition shows condition text"] = function()
    local h = ctx.create()
    setup_bp(h)
    h:cmd("DapBreakpoint condition 2 x > 0")
    h:wait_url("/breakpoints(line=2)")
    local cond = h:query_component("condition", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(cond.text, "x > 0")
    MiniTest.expect.equality(cond.hl, "DapCondition")
  end

  T["breakpoint condition shows logMessage text"] = function()
    local h = ctx.create()
    setup_bp(h)
    h:cmd("DapBreakpoint log 2 Value: {x}")
    h:wait_url("/breakpoints(line=2)")
    local cond = h:query_component("condition", "/breakpoints(line=2)[0]")
    MiniTest.expect.equality(cond.text, "Value: {x}")
    MiniTest.expect.equality(cond.hl, "DapLogMessage")
  end

  -- ========================================================================
  -- Variable components
  -- ========================================================================

  T["variable title shows name"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")
    local title = h:query_component("title", "@frame/scopes[0]/variables[0]")
    MiniTest.expect.equality(title ~= nil, true)
    MiniTest.expect.equality(title.hl, "DapVarName")
  end

  T["variable value shows value"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")
    local value = h:query_component("value", "@frame/scopes[0]/variables[0]")
    MiniTest.expect.equality(value ~= nil, true)
    MiniTest.expect.equality(value.hl, "DapVarValue")
  end

  T["variable type shows type when available"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")
    local vtype = h:query_component("type", "@frame/scopes[0]/variables[0]")
    -- Both adapters provide type info for simple variables
    if vtype ~= vim.NIL then
      MiniTest.expect.equality(vtype.text ~= nil and vtype.text ~= "", true)
      MiniTest.expect.equality(vtype.hl, "DapVarType")
    end
  end

  -- ========================================================================
  -- Scope components
  -- ========================================================================

  T["scope title shows scope name"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    local title = h:query_component("title", "@frame/scopes[0]")
    MiniTest.expect.equality(title ~= nil, true)
    MiniTest.expect.equality(title.hl, "DapScope")
  end

  -- ========================================================================
  -- Source components
  -- ========================================================================

  T["source title shows display name"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("/sources[0]")
    local title = h:query_component("title", "/sources[0]")
    MiniTest.expect.equality(title ~= nil, true)
    MiniTest.expect.equality(title.text ~= nil and title.text ~= "", true)
    MiniTest.expect.equality(title.hl, "DapSource")
  end

  -- ========================================================================
  -- ExceptionFilter components
  -- ========================================================================

  T["exception filter icon reflects enabled state"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("/exceptionFilters[0]")
    local icon = h:query_component("icon", "/exceptionFilters[0]")
    MiniTest.expect.equality(icon ~= nil, true)
    -- Icon is ● (enabled) or ○ (disabled) depending on adapter defaults
    local valid = (icon.text == "●" and icon.hl == "DapEnabled")
              or (icon.text == "○" and icon.hl == "DapDisabled")
    MiniTest.expect.equality(valid, true)
  end

  T["exception filter icon flips after toggle"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("/exceptionFilters[0]")
    local before = h:query_component("icon", "/exceptionFilters[0]")
    h:run_action("toggle", "/exceptionFilters[0]")
    h:yield(100)
    local after = h:query_component("icon", "/exceptionFilters[0]")
    -- Text should flip between ● and ○
    MiniTest.expect.equality(before.text ~= after.text, true)
  end

  T["exception filter title shows label"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("/exceptionFilters[0]")
    local title = h:query_component("title", "/exceptionFilters[0]")
    MiniTest.expect.equality(title ~= nil, true)
    MiniTest.expect.equality(title.text ~= nil and title.text ~= "", true)
    MiniTest.expect.equality(title.hl, "DapFilter")
  end

  -- ========================================================================
  -- ExceptionFilterBinding components
  -- ========================================================================

  T["exception filter binding icon default has no override marker"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("@session/exceptionFilterBindings[0]")
    local icon = h:query_component("icon", "@session/exceptionFilterBindings[0]")
    MiniTest.expect.equality(icon ~= nil, true)
    -- No override: ● (enabled) or ○ (disabled)
    local is_no_override = (icon.text == "●" or icon.text == "○")
    MiniTest.expect.equality(is_no_override, true)
  end

  T["exception filter binding icon shows override marker after toggle"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("@session/exceptionFilterBindings[0]")
    h:run_action("toggle", "@session/exceptionFilterBindings[0]")
    h:yield(100)
    local icon = h:query_component("icon", "@session/exceptionFilterBindings[0]")
    -- With override: ◉ (enabled) or ◎ (disabled)
    local is_override = (icon.text == "◉" or icon.text == "◎")
    MiniTest.expect.equality(is_override, true)
  end

  T["exception filter binding icon cycles through all override states"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("@session/exceptionFilterBindings[0]")

    -- Default: no override (● or ○)
    local icon0 = h:query_component("icon", "@session/exceptionFilterBindings[0]")
    local is_no_override = (icon0.text == "●" or icon0.text == "○")
    MiniTest.expect.equality(is_no_override, true)

    -- First toggle: override created, enabled flipped (◉ or ◎)
    h:run_action("toggle", "@session/exceptionFilterBindings[0]")
    h:yield(100)
    local icon1 = h:query_component("icon", "@session/exceptionFilterBindings[0]")
    local is_override1 = (icon1.text == "◉" or icon1.text == "◎")
    MiniTest.expect.equality(is_override1, true)

    -- Second toggle: still override, enabled flipped again (other of ◉/◎)
    h:run_action("toggle", "@session/exceptionFilterBindings[0]")
    h:yield(100)
    local icon2 = h:query_component("icon", "@session/exceptionFilterBindings[0]")
    local is_override2 = (icon2.text == "◉" or icon2.text == "◎")
    MiniTest.expect.equality(is_override2, true)
    MiniTest.expect.equality(icon1.text ~= icon2.text, true)
  end

  T["exception filter binding title shows label"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("@session/exceptionFilterBindings[0]")
    local title = h:query_component("title", "@session/exceptionFilterBindings[0]")
    MiniTest.expect.equality(title ~= nil, true)
    MiniTest.expect.equality(title.text ~= nil and title.text ~= "", true)
    MiniTest.expect.equality(title.hl, "DapFilter")
  end

  T["exception filter binding condition nil by default"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("@session/exceptionFilterBindings[0]")
    local cond = h:query_component("condition", "@session/exceptionFilterBindings[0]")
    MiniTest.expect.equality(cond, vim.NIL)
  end

  T["exception filter binding condition shows value after set"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:use_plugin("neodap.plugins.exception_cmd")
    h:wait_url("@session/exceptionFilterBindings[0]")
    local filter_id = h:query_field("/exceptionFilters[0]", "filterId")
    h:cmd("DapException condition " .. filter_id .. " x > 0")
    h:yield(100)
    local cond = h:query_component("condition", "@session/exceptionFilterBindings[0]")
    MiniTest.expect.equality(cond.text, "x > 0")
    MiniTest.expect.equality(cond.hl, "DapCondition")
  end

  -- ========================================================================
  -- query_component_text shorthand
  -- ========================================================================

  T["query_component_text returns text directly"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local text = h:query_component_text("icon", "@session")
    MiniTest.expect.equality(text, "⏸")
  end

  T["query_component_text returns nil for missing component"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    -- Session has no "index" component
    local text = h:query_component_text("index", "@session")
    MiniTest.expect.equality(text, vim.NIL)
  end

  -- ========================================================================
  -- actions_for
  -- ========================================================================

  T["actions_for returns available actions for breakpoint"] = function()
    local h = ctx.create()
    setup_bp(h)
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    local actions = h:query_actions_for("/breakpoints(line=2)[0]")
    local has_toggle = vim.tbl_contains(actions, "toggle")
    local has_enable = vim.tbl_contains(actions, "enable")
    local has_disable = vim.tbl_contains(actions, "disable")
    local has_remove = vim.tbl_contains(actions, "remove")
    MiniTest.expect.equality(has_toggle, true)
    MiniTest.expect.equality(has_enable, true)
    MiniTest.expect.equality(has_disable, true)
    MiniTest.expect.equality(has_remove, true)
  end

  T["actions_for returns available actions for session"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local actions = h:query_actions_for("@session")
    local has_focus = vim.tbl_contains(actions, "focus")
    local has_focus_jump = vim.tbl_contains(actions, "focus_and_jump")
    MiniTest.expect.equality(has_focus, true)
    MiniTest.expect.equality(has_focus_jump, true)
  end

  T["actions_for returns available actions for frame"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    local actions = h:query_actions_for("@frame")
    local has_focus = vim.tbl_contains(actions, "focus")
    local has_focus_jump = vim.tbl_contains(actions, "focus_and_jump")
    MiniTest.expect.equality(has_focus, true)
    MiniTest.expect.equality(has_focus_jump, true)
  end

  T["actions_for returns available actions for variable"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")
    local actions = h:query_actions_for("@frame/scopes[0]/variables[0]")
    local has_yank_value = vim.tbl_contains(actions, "yank_value")
    local has_yank_name = vim.tbl_contains(actions, "yank_name")
    MiniTest.expect.equality(has_yank_value, true)
    MiniTest.expect.equality(has_yank_name, true)
  end

  T["actions_for returns available actions for exception filter binding"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("@session/exceptionFilterBindings[0]")
    local actions = h:query_actions_for("@session/exceptionFilterBindings[0]")
    local has_toggle = vim.tbl_contains(actions, "toggle")
    MiniTest.expect.equality(has_toggle, true)
  end

  T["actions_for returns available actions for exception filter"] = function()
    local h = ctx.create()
    launch_and_focus(h)
    h:wait_url("/exceptionFilters[0]")
    local actions = h:query_actions_for("/exceptionFilters[0]")
    local has_toggle = vim.tbl_contains(actions, "toggle")
    MiniTest.expect.equality(has_toggle, true)
  end

end)
