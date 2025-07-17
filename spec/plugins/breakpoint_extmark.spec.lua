-- Test: BreakpointApi functionality with terminal snapshots
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
local nio = require("nio")

Test.Describe("BreakpointApi Functionality", function()
    Test.It("creates_and_removes_breakpoints_with_visual_markers", function()
        local api = prepare()

        -- Get plugin instances
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        api:getPluginInstance(BreakpointVirtualText)

        -- Open the loop.js fixture
        vim.cmd("edit spec/fixtures/loop.js")

        -- Move cursor to line 3 (inside the setInterval callback)
        vim.api.nvim_win_set_cursor(0, { 3, 0 })

        -- Take snapshot before breakpoint
        Test.TerminalSnapshot("before_breakpoint")

        -- Set breakpoint and wait for processing
        toggleBreakpoint:toggle()
        nio.sleep(20)

        -- Take snapshot after breakpoint (should show visual marker)
        Test.TerminalSnapshot("after_breakpoint")

        -- Remove breakpoint and wait for processing
        toggleBreakpoint:toggle()
        nio.sleep(20)

        -- Take snapshot after removal
        Test.TerminalSnapshot("after_removal")
    end)
end)

--[[ TERMINAL SNAPSHOT: before_breakpoint
Size: 24x80
Cursor: [3, 0]
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|         console.log("ALoop iteration: ", i++);
 4|         console.log("BLoop iteration: ", i++);
 5|         console.log("CLoop iteration: ", i++);
 6|         console.log("DLoop iteration: ", i++);
 7| }, 1000)
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/loop.js                                         3,1-8          All
24|
]]


--[[ TERMINAL SNAPSHOT: after_breakpoint
Size: 24x80
Cursor: [3, 0]
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3| ●       console.log("ALoop iteration: ", i++);
 4|         console.log("BLoop iteration: ", i++);
 5|         console.log("CLoop iteration: ", i++);
 6|         console.log("DLoop iteration: ", i++);
 7| }, 1000)
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/loop.js                                         3,1-8          All
24| ✓ Terminal snapshot 'before_breakpoint' matches
]]


--[[ TERMINAL SNAPSHOT: after_removal
Size: 24x80
Cursor: [3, 0]
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|         console.log("ALoop iteration: ", i++);
 4|         console.log("BLoop iteration: ", i++);
 5|         console.log("CLoop iteration: ", i++);
 6|         console.log("DLoop iteration: ", i++);
 7| }, 1000)
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/loop.js                                         3,1-8          All
24| ✓ Terminal snapshot 'after_breakpoint' matches
]]
