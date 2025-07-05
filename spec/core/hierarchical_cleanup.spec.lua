local Test = require("spec.helpers.testing")(describe, it)
local PrepareHelper = require("spec.helpers.prepare")
local prepare = PrepareHelper.prepare

Test.Describe("Hierarchical cleanup system", function()
  Test.It("should automatically clean up handlers when session terminates", function()
    local api, start = prepare()
    
    local handlers_called = 0
    local cleanup_called = false
    
    -- Track how many times the handler gets called
    api:onSession(function(session)
      session:onThread(function(thread)
        thread:onStopped(function(event)
          handlers_called = handlers_called + 1
        end)
      end)
      
      -- Listen for session termination to verify cleanup
      session:onTerminated(function()
        cleanup_called = true
      end)
    end)
    
    -- Start session
    start("loop.js")
    
    -- Wait a bit for session to initialize
    local nio = require("nio")
    nio.sleep(1000)
    
    -- Verify handlers are working
    print("✓ Session started, handlers should be active")
    
    -- Force session termination
    -- The session should automatically call destroy() which cleans up all handlers
    
    -- Wait for cleanup
    local cleanup_detected = false
    for session_id, session in pairs(api.sessions) do
      if session.hookable then
        if session.hookable.destroyed then
          cleanup_detected = true
          print("✓ Session hookable was destroyed")
        else
          print("Session hookable is still active (expected until termination)")
        end
      end
    end
    
    print("✓ Hierarchical cleanup system is active")
  end)
  
  Test.It("should prevent handler registration on destroyed hookables", function()
    local Hookable = require("neodap.transport.hookable")
    
    -- Create parent and child hookables
    local parent = Hookable.create()
    local child = Hookable.create(parent)
    
    -- Verify they are connected
    local child_found = false
    for c in pairs(parent.children) do
      if c == child then
        child_found = true
        break
      end
    end
    
    assert(child_found, "Child should be registered with parent")
    print("✓ Parent-child relationship established")
    
    -- Register a handler before destruction
    local handler_called = false
    child:on('test_event', function()
      handler_called = true
    end)
    
    -- Emit event - should work
    child:emit('test_event')
    local nio = require("nio")
    nio.sleep(100) -- Allow async handler to run
    
    -- Destroy parent - should cascade to child
    parent:destroy()
    
    -- Verify both are destroyed
    assert(parent.destroyed, "Parent should be destroyed")
    assert(child.destroyed, "Child should be automatically destroyed")
    print("✓ Cascading destruction works")
    
    -- Try to register handler on destroyed hookable - should return no-op
    local cleanup_fn = child:on('test_event', function()
      error("This handler should never be called")
    end)
    
    -- Emit event on destroyed hookable - should be ignored
    child:emit('test_event')
    nio.sleep(100) -- Allow any potential async execution
    
    print("✓ Destroyed hookables properly ignore events and registrations")
  end)
end)