-- Test: Stack Navigation visual demonstration
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
local StackNavigation = require("neodap.plugins.StackNavigation")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local nio = require("nio")

Test.Describe("Stack Navigation Visual Demo", function()
    Test.It("shows_recursive_stack_frames", function()
        local api, start = prepare()

        -- Get plugin instances
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        api:getPluginInstance(BreakpointVirtualText) -- Enable visual markers
        local stackNav = api:getPluginInstance(StackNavigation)
        local frameHighlight = api:getPluginInstance(FrameHighlight)

        -- Open the recurse.js file
        vim.cmd("edit spec/fixtures/recurse.js")

        -- Move cursor to line 2 (inside the recursive function)
        vim.api.nvim_win_set_cursor(0, { 2, 1 })

        -- Set breakpoint inside the recursive function
        toggleBreakpoint:toggle()
        nio.sleep(20)

        -- Take snapshot with breakpoint set
        Test.TerminalSnapshot("recurse_with_breakpoint")

        -- Set up promises to wait for session events
        local session_promise = nio.control.future()
        local stopped_promise = nio.control.future()
        local stack_ready = nio.control.future()
        
        api:onSession(function(session)
            if not session_promise.is_set() then
                session_promise.set(session)
            end
            
            session:onThread(function(thread)
                thread:onStopped(function()
                    if not stopped_promise.is_set() then
                        -- Give time for stack to be available
                        nio.sleep(100)
                        local stack = thread:stack()
                        if stack and not stack_ready.is_set() then
                            stack_ready.set(true)
                        end
                        stopped_promise.set(true)
                    end
                end)
            end)
        end)
        
        -- Start the debug session
        start("recurse.js")
        
        -- Wait for session to start and hit breakpoint
        session_promise.wait()
        stopped_promise.wait()
        stack_ready.wait()
        
        -- Small delay to ensure UI updates
        nio.sleep(200)

        -- Take snapshot when stopped at breakpoint
        Test.TerminalSnapshot("stopped_at_recursive_breakpoint")

        -- Navigate up the stack
        stackNav:Up()
        nio.sleep(100)
        
        -- Take snapshot after navigating up
        Test.TerminalSnapshot("navigated_up_one_frame")

        -- Navigate up again
        stackNav:Up()
        nio.sleep(100)
        
        -- Take snapshot after second navigation
        Test.TerminalSnapshot("navigated_up_two_frames")

        -- Navigate to top frame
        stackNav:Top()
        nio.sleep(100)
        
        -- Take snapshot at top frame
        Test.TerminalSnapshot("back_at_top_frame")

        -- Clean up
        api:destroy()
    end)
end)


--[[ TERMINAL SNAPSHOT: recurse_with_breakpoint
Size: 24x80
Cursor: [2, 1] (line 2, col 1)
Mode: n

 1| function fibo(n) {
 2| ● if (n <= 1) return n;
 3|  return fibo(n - 1) + fibo(n - 2);
 4| }
 5| 
 6| // Test with smaller number for debugging
 7| setTimeout(() => fibo(5), 1000);
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
23| spec/fixtures/recurse.js                                      2,2-3          All
24| 
]]

--[[ TERMINAL SNAPSHOT: stopped_at_recursive_breakpoint
Size: 24x80
Cursor: [2, 1] (line 2, col 1)
Mode: n

Highlights:
  NeodapTopFrameHighlight[2:2-2:23]
  NeodapOtherFrameHighlight[7:1-7:33]
  NeodapOtherFrameHighlight[7:18-7:33]

 1| function fibo(n) {
 2| ● ◆if (n <= 1) return n;
 3|  return fibo(n - 1) + fibo(n - 2);
 4| }
 5| 
 6| // Test with smaller number for debugging
 7| setTimeout(() => fibo(5), 1000);
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
23| spec/fixtures/recurse.js                                      2,2-4          All
24| 
]]













--[[ TERMINAL SNAPSHOT: navigated_up_one_frame
Size: 24x80
Cursor: [519, 6] (line 519, col 6)
Mode: n

Highlights:
  NeodapOtherFrameHighlight[165:5-165:55]
  NeodapOtherFrameHighlight[199:5-199:40]
  NeodapOtherFrameHighlight[519:7-519:32]
  NeodapOtherFrameHighlight[581:17-581:30]

 1|     let ranAtLeastOneList = false;
 2|     while ((list = timerListQueue.peek()) != null) {
 3|       if (list.expiry > now) {
 4|         nextExpiry = list.expiry;
 5|         return timeoutInfo[0] > 0 ? nextExpiry : -nextExpiry;
 6|       }
 7|       if (ranAtLeastOneList)
 8|         runNextTicks();
 9|       else
10|         ranAtLeastOneList = true;
11|       listOnTimeout(list, now);
12|     }
13|     return 0;
14|   }
15| 
16|   function listOnTimeout(list, now) {
17|     const msecs = list.msecs;
18| 
19|     debug('timeout callback %d', msecs);
20| 
21|     let ranAtLeastOneTimer = false;
22|     let timer;
23| virtual://eaeead21/<node_internals>/internal/timers           519,7          75%
24| 
]]


--[[ TERMINAL SNAPSHOT: navigated_up_two_frames
Size: 24x80
Cursor: [581, 16] (line 581, col 16)
Mode: n

Highlights:
  NeodapOtherFrameHighlight[165:5-165:55]
  NeodapOtherFrameHighlight[199:5-199:40]
  NeodapOtherFrameHighlight[519:7-519:32]
  NeodapOtherFrameHighlight[581:17-581:30]

 1| 
 2|       let start;
 3|       if (timer._repeat) {
 4|         // We need to use the binding as the receiver for fast API calls.
 5|         start = binding.getLibuvNow();
 6|       }
 7| 
 8|       try {
 9|         const args = timer._timerArgs;
10|         if (args === undefined)
11|           timer._onTimeout();
12|         else
13|           ReflectApply(timer._onTimeout, timer, args);
14|       } finally {
15|         if (timer._repeat && timer._idleTimeout !== -1) {
16|           timer._idleTimeout = timer._repeat;
17|           insert(timer, timer._idleTimeout, start);
18|         } else if (!timer._idleNext && !timer._idlePrev && !timer._destroyed) {
19|           timer._destroyed = true;
20| 
21|           if (timer[kHasPrimitive])
22|             delete knownTimersById[asyncId];
23| virtual://eaeead21/<node_internals>/internal/timers           581,17         84%
24| 
]]

--[[ TERMINAL SNAPSHOT: back_at_top_frame
Size: 24x80
Cursor: [2, 1] (line 2, col 1)
Mode: n

Highlights:
  NeodapTopFrameHighlight[2:2-2:23]
  NeodapOtherFrameHighlight[7:1-7:33]
  NeodapOtherFrameHighlight[7:18-7:33]

 1| function fibo(n) {
 2| ● ◆if (n <= 1) return n;
 3|  return fibo(n - 1) + fibo(n - 2);
 4| }
 5| 
 6| // Test with smaller number for debugging
 7| setTimeout(() => fibo(5), 1000);
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
23| spec/fixtures/recurse.js                                      2,2-4          All
24| 
]]