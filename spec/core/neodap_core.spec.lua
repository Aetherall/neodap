local Test = require("spec.helpers.testing")(describe, it)
local PrepareHelper = require("spec.helpers.prepare")
local prepare = PrepareHelper.prepare

-- local prepare = require("spec.helpers.prepare")
local nio = require("nio")

Test.Describe("neodap", function()
    print("\nSuite: neodap")
    Test.It("boots", function()
        print("\n\tTest: neodap boots\t")
        local api, start = prepare()

        local initialized_spy = Test.spy()
        local terminated_spy = Test.spy()
        local exited_spy = Test.spy()

        api:onSession(function(session)
            if session.ref.id == 1 then return end

            session:onInitialized(initialized_spy.trigger, { once = true })
            session:onTerminated(terminated_spy.trigger, { once = true })
            session:onExited(exited_spy.trigger, { once = true })
        end)

        start("second.js")

        initialized_spy.wait()
        terminated_spy.wait()
        exited_spy.wait()
    end)

    Test.It('pauses thread', function()
        print("\n\tTest: neodap pauses\t")
        local api, start = prepare()

        -- Use unique test identifier to avoid cross-test interference
        local paused_spy = Test.spy()
        local continued_spy = Test.spy()
        local resumed_spy = Test.spy()

        ---@type api.Thread | nil
        local t = nil

        api:onSession(function(session)
            if session.ref.id == 1 then return end
            session:onThread(function(thread)
                t = thread
                thread:onStopped(paused_spy.trigger, { once = true })
                thread:onContinued(continued_spy.trigger, { once = true })
                thread:onResumed(resumed_spy.trigger, { once = true })
                thread:pause()
            end)
        end)

        start("loop.js")

        paused_spy.wait()

        if t then t:continue() end

        resumed_spy.wait()
    end)

    Test.It('resumes thread', function()
        print("\n\tTest: neodap resumes\t")
        local api, start = prepare()

        local resumed_spy = Test.spy()

        api:onSession(function(session)
            if session.ref.id == 1 then return end
            session:onThread(function(thread)
                thread:onStopped(function() thread:continue() end, { once = true })
                thread:onResumed(resumed_spy.trigger, { once = true })
                thread:pause()
            end)
        end)

        start("loop.js")

        resumed_spy.wait()
    end)

    -- todo: use a debugee that supports stopping a single thread
    -- Test.it('stops thread', function()
    --   print("\n\tTest: neodap stops\t")
    --   local api, start = prepare()

    --   local stopped = nio.control.future()

    --   api:onSession(function(session)
    --     session:onThread(function(thread)
    --       thread:onPaused(stopped.set, { once = true })
    --       thread:stop()
    --     end)
    --   end)

    --   start("hello-world.js")

    --   assert.is_true(vim.wait(10000, stopped.is_set), "Session should be stopped")
    -- end)

    Test.Describe('stack', function()
        print("\n\t\tSuite: neodap stack\t")


        Test.It('accesses stack', function()
            print("\n\t\t\tTest: neodap accesses stack\t")

            local api, start = prepare()

            local stack_accessed_spy = Test.spy()

            api:onSession(function(session)
                if session.ref.id == 1 then return end
                session:onThread(function(thread)
                    thread:onStopped(function()
                        local stack = thread:stack()

                        assert(stack, "Stack should not be nil")

                        local frames = stack:frames()

                        assert(#frames > 0, "Stack should have frames")

                        stack_accessed_spy.trigger()
                    end)

                    thread:pause()
                end)
            end)

            start("loop.js")

            stack_accessed_spy.wait()
        end)

        --  Test.It('clears stack on continue', function()
        --     print("\n\t\t\tTest: neodap clears stack on continue\t")

        --     local api, start = prepare()

        --     local stack_cleared_spy = Test.spy()

        --     api:onSession(function(session)
        --       if session.ref.id == 1 then return end
        --       session:onThread(function(thread)
        --         thread:onStopped(function()
        --           local stack = thread:stack()
        --           assert(stack, "Stack should not be nil")
        --           assert(#stack:frames() > 0, "Stack should have frames")

        --           thread:continue()
        --         end)

        --         thread:onResumed(function()
        --           local stack = thread:stack()
        --           assert(stack, "Stack should be cleared on continue")
        --           stack_cleared_spy()
        --         end)

        --         thread:pause()
        --       end)
        --     end)

        --     start("loop.js")

        --     Test.assert.spy(stack_cleared_spy).was_called()
        --   end)

        --   Test.It('refreshes the stack on pause > continue', function()
        --     print("\n\t\t\tTest: neodap refreshes stack on pause > continue\t")

        --     local api, start = prepare()

        --     local stack_refreshed_spy = Test.spy()

        --     api:onSession(function(session)
        --       if session.ref.id == 1 then return end
        --       session:onThread(function(thread)
        --         thread:onStopped(function()
        --           local stack = thread:stack()
        --           assert(stack, "Stack should not be nil")
        --           assert(#stack:frames() > 0, "Stack should have frames")

        --           thread:continue()
        --         end, { once = true })

        --         thread:onResumed(function()
        --           thread:onStopped(function()
        --             local stack = thread:stack()
        --             assert(stack, "Stack should not be nil after resume")
        --             assert(#stack:frames() > 0, "Stack should have frames after resume")
        --             stack_refreshed_spy()
        --           end)

        --           thread:pause()
        --         end)

        --         thread:pause()
        --       end)
        --     end)

        --     start("loop.js")

        --     Test.assert.spy(stack_refreshed_spy).was_called()
        --   end)


        --   Test.It('triggers stack invalidation hooks on continue', function()
        --     print("\n\t\t\tTest: neodap triggers stack invalidation hooks on continue\t")

        --     local api, start = prepare()

        --     local stack_invalidated_spy = Test.spy()

        --     api:onSession(function(session)
        --       if session.ref.id == 1 then return end
        --       session:onThread(function(thread)
        --         thread:onStopped(function()
        --           local stack = thread:stack()

        --           assert(stack, "Stack should not be nil on pause")

        --           stack:onInvalidated(stack_invalidated_spy, { once = true })

        --           thread:continue()
        --         end)

        --         thread:pause()
        --       end)
        --     end)

        --     start("loop.js")

        --     Test.assert.spy(stack_invalidated_spy).was_called()
        --   end)
        -- end)

        -- Test.Describe('frame', function()
        --   Test.It('accesses frame', function()
        --     print("\n\t\t\tTest: neodap accesses frame\t")

        --     local api, start = prepare()

        --     local frame_accessed_spy = Test.spy()

        --     api:onSession(function(session)
        --       if session.ref.id == 1 then return end
        --       session:onThread(function(thread)
        --         thread:onStopped(function()
        --           local stack = thread:stack()

        --           assert(stack, "Stack should not be nil")

        --           local frames = stack:frames()

        --           assert(frames, "Stack should have frames")

        --           local frame = frames[1]

        --           assert(frame, "Frame should not be nil")

        --           frame_accessed_spy()
        --         end)

        --         thread:pause()
        --       end)
        --     end)

        --     start("loop.js")

        --     Test.assert.spy(frame_accessed_spy).was_called()
        --   end)

        --   Test.It('navigate frames', function()
        --     print("\n\t\t\tTest: neodap navigate frames\t")

        --     local api, start = prepare()

        --     local frame_navigation_spy = Test.spy()

        --     api:onSession(function(session)
        --       if session.ref.id == 1 then return end
        --       session:onThread(function(thread)
        --         thread:onStopped(function()
        --           local stack = thread:stack()

        --           assert(stack, "Stack should not be nil")

        --           local top = stack:top()

        --           assert(top, "Top frame should not be nil")

        --           local lowerFrame = top:down()
        --           assert(lowerFrame, "Lower frame should not be nil")

        --           local upperFrame = lowerFrame:up()
        --           assert(upperFrame, "Upper frame should not be nil")

        --           assert(top == upperFrame, "Upper frame should be the top frame")

        --           frame_navigation_spy()
        --         end)

        --         thread:pause()
        --       end)
        --     end)

        --     start("loop.js")

        --     Test.assert.spy(frame_navigation_spy).was_called()
        --   end)
        -- end)

        -- Test.Describe('scope', function()
        --   Test.It('accesses scope', function()
        --     print("\n\t\t\tTest: neodap accesses scope\t")

        --     local api, start = prepare()

        --     local scope_accessed_spy = Test.spy()

        --     api:onSession(function(session)
        --       if session.ref.id == 1 then return end
        --       session:onThread(function(thread)
        --         thread:onStopped(function()
        --           local stack = thread:stack()

        --           assert(stack, "Stack should not be nil")

        --           local frame = stack:top()
        --           assert(frame, "Frame should not be nil")

        --           local scopes = frame:scopes()
        --           assert(#scopes > 0, "Frame should have scopes")

        --           scope_accessed_spy()
        --         end)

        --         thread:pause()
        --       end)
        --     end)

        --     start("loop.js")

        --     Test.assert.spy(scope_accessed_spy).was_called()
        --   end)

        --   Test.It('accesses scope location', function()
        --     print("\n\t\t\tTest: neodap accesses scope location\t")

        --     local api, start = prepare()

        --     local scope_location_accessed_spy = Test.spy()

        --     api:onSession(function(session)
        --       if session.ref.id == 1 then return end
        --       session:onThread(function(thread)
        --         thread:onStopped(function()
        --           local stack = thread:stack()

        --           assert(stack, "Stack should not be nil")

        --           local frame = stack:top()
        --           assert(frame, "Frame should not be nil")

        --           print(frame:toString())

        --           local scopes = frame:scopes()
        --           assert(scopes, "Frame should have scopes")

        --           -- Find a scope with source information for location testing
        --           local scope_with_source = nil
        --           for _, scope in ipairs(scopes) do
        --             if scope:source() then
        --               scope_with_source = scope
        --               break
        --             end
        --           end

        --           -- Only test location if we found a scope with source information
        --           if scope_with_source then
        --             local source = scope_with_source:source()
        --             assert(source, "Scope source should not be nil")

        --             -- Check if it's a FileSource by checking for filename method
        --             if source.filename and type(source.filename) == "function" then
        --               local filename = source:filename()
        --               assert(filename == "loop.js", "Scope source filename should be 'loop.js'")
        --             else
        --               error("Scope source should be a file source")
        --             end

        --             local start, finish = scope_with_source:region()
        --             assert(start, "Scope region should not be nil")
        --             assert(finish, "Scope region should not be nil")

        --             assert(start[1] == 2, "Scope start line should be 2")
        --             assert(start[2] == 13, "Scope start column should be 13")

        --             assert(finish[1] == 7, "Scope finish line should be 7")
        --             assert(finish[2] == 2, "Scope finish column should be 2")
        --           else
        --             -- If no scope has source information, that's also a valid scenario
        --             print("No scopes with source information found - this is valid in some debugging contexts")
        --           end

        --           scope_location_accessed_spy()
        --         end)

        --         thread:pause()
        --       end)
        --     end)

        --     start("loop.js")

        --     Test.assert.spy(scope_location_accessed_spy).was_called()
        --   end)
        -- end)

        -- -- describe("Breakpoint Manager", function()
        -- --   it("handles DAP breakpoint events", function()
        -- --     print("\n\tTest: Breakpoint Manager handles DAP events\t")
        -- --     local api, start = prepare()

        -- --     local breakpointAdded = nio.control.future()
        -- --     local breakpointEvents = {}
        -- --     local addedBreakpoint = nil

        -- --     api:onSession(function(session)
        -- --       if session.ref.id == 1 then return end

        -- --       -- Track breakpoint manager events
        -- --       session:onBreakpointBound(function(breakpoint)
        -- --         table.insert(breakpointEvents, { type = "added", id = breakpoint.id })
        -- --         addedBreakpoint = breakpoint
        -- --         breakpointAdded.set(true)
        -- --       end)

        -- --       session:onInitialized(function()
        -- --         -- Set a breakpoint via DAP protocol to trigger events
        -- --         session.ref.calls:setBreakpoints({
        -- --           source = {
        -- --             path = vim.fn.fnamemodify("spec/fixtures/breakpoint-test.js", ":p")
        -- --           },
        -- --           breakpoints = {{ line = 2 }}
        -- --         }):wait()
        -- --       end, { once = true })

        -- --       session:onThread(function(thread)
        -- --         thread:onExited(function(body)
        -- --           if body.reason == "breakpoint" then
        -- --             -- Just continue for now, don't test removal yet
        -- --             thread:continue()
        -- --           end
        -- --         end)
        -- --       end)
        -- --     end)

        -- --     start("breakpoint-test.js")

        -- --     -- Wait for breakpoint to be added
        -- --     assert(vim.wait(10000, breakpointAdded.is_set), "Breakpoint should be added")
        -- --     assert(addedBreakpoint, "Breakpoint should be added")
        -- --     assert(addedBreakpoint.id, "Breakpoint should have an ID")

        -- --     -- Verify events were fired
        -- --     assert(#breakpointEvents >= 1, "Should have at least 1 breakpoint event")
        -- --     assert(breakpointEvents[1].type == "added", "First event should be 'added'")
        -- --   end)

        -- --   it("manages breakpoint bindings across sessions", function()
        -- --     print("\n\tTest: Breakpoint bindings management\t")
        -- --     local api, start = prepare()

        -- --     local bindingTest = nio.control.future()

        -- --     api:onSession(function(session)
        -- --       if session.ref.id == 1 then return end

        -- --       api:breakpoints():onBreakpointAdded(function(breakpoint)
        -- --         -- Test that breakpoint can track its binding to this session
        -- --         local binding = breakpoint:binding(session)
        -- --         assert(binding, "Breakpoint should have a binding for this session")
        -- --         assert(binding.session == session, "Binding should reference correct session")
        -- --         assert(binding.ref, "Binding should have DAP breakpoint reference")

        -- --         bindingTest.set(true)
        -- --       end)

        -- --       session:onInitialized(function()
        -- --         session.ref.calls:setBreakpoints({
        -- --           source = {
        -- --             path = vim.fn.fnamemodify("spec/fixtures/simple-debug.js", ":p")
        -- --           },
        -- --           breakpoints = {{ line = 1 }}
        -- --         }):wait()
        -- --       end, { once = true })
        -- --     end)

        -- --     start("simple-debug.js")

        -- --     assert(vim.wait(10000, bindingTest.is_set), "Binding test should complete")
        -- --   end)

        -- --   it("tracks breakpoints by source", function()
        -- --     print("\n\tTest: Breakpoints tracked by source\t")
        -- --     local api, start = prepare()

        -- --     local sourceTrackingTest = nio.control.future()
        -- --     local breakpointsAdded = 0

        -- --     api:onSession(function(session)
        -- --       if session.ref.id == 1 then return end

        -- --       -- Track when breakpoints are added to help debug
        -- --       api:breakpoints():onBreakpointAdded(function(breakpoint)
        -- --         print("DEBUG: Breakpoint added with ID:", breakpoint.id)
        -- --         breakpointsAdded = breakpointsAdded + 1
        -- --       end)

        -- --       session:onInitialized(function()
        -- --         print("DEBUG: INITIALIZED event received")
        -- --       end, { once = true })

        -- --       -- Wait for the source to be loaded before setting breakpoints
        -- --       session:onSourceLoaded(function(source)
        -- --         print("DEBUG: Source loaded:", source:identifier())
        -- --         if source:identifier():match("loop%.js") then
        -- --           print("DEBUG: Found loop.js source, setting breakpoints")
        -- --           local result = session.ref.calls:setBreakpoints({
        -- --             source = source.ref,  -- Use the actual loaded source reference
        -- --             breakpoints = {{ line = 3 }, { line = 4 }}
        -- --           }):wait()
        -- --           print("DEBUG: setBreakpoints result:", vim.inspect(result))
        -- --         end
        -- --       end)

        -- --       session:onThread(function(thread)
        -- --         print("DEBUG: Thread event received, ID:", thread.id)
        -- --         thread:onStopped(function(body)
        -- --           print("DEBUG: Thread paused/stopped, thread ID:", thread.id, "event threadId:", body.threadId, "reason:", body.reason)
        -- --           if body.reason == "breakpoint" then
        -- --             -- Get the stack to find the current source
        -- --             local stack = thread:stack()
        -- --             if stack then
        -- --               local frames = stack:frames()
        -- --               if frames and #frames > 0 then
        -- --                 local topFrame = frames[1]
        -- --                 if topFrame and topFrame.ref and topFrame.ref.source then
        -- --                   print("DEBUG: Got source from stack frame")
        -- --                   local source = session:getSourceFor(topFrame.ref.source)
        -- --                   if source then
        -- --                     print("DEBUG: Got source, getting breakpoints")
        -- --                     local sourceBreakpoints = api:breakpoints():getSourceBreakpoints(source)
        -- --                     print("DEBUG: Found", #sourceBreakpoints, "breakpoints for source")
        -- --                     if #sourceBreakpoints > 0 then
        -- --                       sourceTrackingTest.set(true)
        -- --                       return
        -- --                     end
        -- --                   else
        -- --                     print("DEBUG: No source found for frame source")
        -- --                   end
        -- --                 else
        -- --                   print("DEBUG: No source in top frame")
        -- --                 end
        -- --               else
        -- --                 print("DEBUG: No frames in stack")
        -- --               end
        -- --             else
        -- --               print("DEBUG: No stack available")
        -- --             end
        -- --             thread:continue()
        -- --           end
        -- --         end)
        -- --       end)
        -- --     end)

        -- --     start("loop.js")

        -- --     -- First wait for breakpoints to be added (check every 100ms)
        -- --     assert(vim.wait(5000, function() return breakpointsAdded >= 2 end), "Breakpoints should be added")
        -- --     print("DEBUG: Breakpoints added, now waiting for execution to hit them...")

        -- --     -- Then wait for source tracking test with longer timeout since loop runs every 1000ms
        -- --     assert(vim.wait(15000, sourceTrackingTest.is_set), "Source tracking test should complete")
        -- --   end)
    end)
end)
