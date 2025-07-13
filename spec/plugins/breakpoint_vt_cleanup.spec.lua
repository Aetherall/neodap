local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.api.Breakpoint.BreakpointManager")
local Location = require("neodap.api.Breakpoint.Location")
local nio = require("nio")

Test.Describe("breakpoint virtual text thread continue cleanup", function()
  Test.It("should not restore extmarks for removed breakpoints on thread continue", function()
    local api, start = prepare()
    
    -- Create breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    -- Load BreakpointVirtualText plugin
    local BreakpointVirtualTextPlugin = require("neodap.plugins.BreakpointVirtualText")
    local virtualTextInstance = BreakpointVirtualTextPlugin.plugin(api)
    local ns = virtualTextInstance.getNamespace()
    
    local breakpointAdded = Test.spy("breakpointAdded")
    local bindingBound = Test.spy("bindingBound")
    local breakpointHit = Test.spy("breakpointHit")
    local breakpointRemoved = Test.spy("breakpointRemoved")
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    local threadResumed = Test.spy("threadResumed")
    
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added:", breakpoint.id)
      breakpointAdded.trigger()
      
      breakpoint:onBinding(function(binding)
        print("✓ Binding created - session:", binding.session and binding.session.id or "no-session")
        bindingBound.trigger()
        
        binding:onHit(function(hit)
          print("✓ Breakpoint hit detected")
          breakpointHit.trigger()
        end)
      end)
      
      breakpoint:onDispose(function()
        print("✓ Breakpoint disposed/removed")
        breakpointRemoved.trigger()
      end)
    end)
    
    -- Create breakpoint
    local originalLocation = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    print("Creating breakpoint at:", originalLocation.key)
    local breakpoint = breakpointManager:addBreakpoint(originalLocation)
    breakpointAdded.wait()
    
    -- Start session and wait for binding
    api:onSession(function(session)
      session:onInitialized(function()
        sessionInitialized.trigger()
      end)
      
      session:onSourceLoaded(function(source)
        local fileSource = source:asFile()
        if fileSource and fileSource:filename() == "loop.js" then
          sourceLoaded.trigger()
        end
      end)
      
      session:onThread(function(thread)
        thread:onResumed(function()
          print("✓ Thread resumed")
          threadResumed.trigger()
        end)
      end)
    end)
    
    start("loop.js")
    sessionInitialized.wait()
    sourceLoaded.wait()
    bindingBound.wait()
    
    -- Verify that the breakpoint has an extmark
    local bufnr = originalLocation:bufnr()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local extmarks_after_bind = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      print("Extmarks after binding:", #extmarks_after_bind)
      assert(#extmarks_after_bind > 0, "Should have extmarks after binding")
    end
    
    -- Simulate a breakpoint hit
    local binding = breakpoint:getBindings():first()
    if binding then
      -- Trigger a hit manually (in real scenarios this would come from DAP)
      print("Simulating breakpoint hit...")
      local hit = {
        binding = binding,
        thread = nil, -- Would be populated in real scenario
        stackFrame = nil -- Would be populated in real scenario  
      }
      
      -- Fire the hit event (this would normally be done by the DAP system)
      breakpoint:_fireHit(hit)
      breakpointHit.wait()
      
      -- Verify hit symbol is shown
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local extmarks_after_hit = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
        print("Extmarks after hit:", #extmarks_after_hit)
        
        -- Check that we have a hit symbol (◆)
        local has_hit_symbol = false
        for _, extmark in ipairs(extmarks_after_hit) do
          if extmark[4] and extmark[4].virt_text and extmark[4].virt_text[1] and extmark[4].virt_text[1][1] == "◆" then
            has_hit_symbol = true
            break
          end
        end
        assert(has_hit_symbol, "Should have hit symbol (◆) after breakpoint hit")
        print("✓ Hit symbol (◆) correctly displayed")
      end
      
      -- Remove the breakpoint BEFORE thread resume
      print("Removing breakpoint before thread resume...")
      breakpointManager:removeBreakpoint(breakpoint)
      breakpointRemoved.wait()
      
      -- Verify extmarks are cleaned up after removal
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local extmarks_after_removal = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
        print("Extmarks after removal:", #extmarks_after_removal)
        assert(#extmarks_after_removal == 0, "Should have no extmarks after breakpoint removal")
        print("✓ Extmarks properly cleaned up after breakpoint removal")
      end
      
      -- Now resume the thread - this should NOT create any new extmarks
      print("Resuming thread after breakpoint removal...")
      
      -- Find a thread to resume (simulate thread resume)
      local sessions = api:getSessions()
      for session in sessions:each() do
        local threads = session:getThreads()
        for thread in threads:each() do
          if thread.ref.id then
            print("Simulating thread resume for thread:", thread.ref.id)
            thread:_fireResumed()
            break
          end
        end
        break
      end
      
      threadResumed.wait()
      
      -- Final verification: still no extmarks after thread resume
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local extmarks_after_resume = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
        print("Extmarks after thread resume:", #extmarks_after_resume)
        assert(#extmarks_after_resume == 0, "Should still have no extmarks after thread resume (breakpoint was removed)")
        print("✓ No extmarks created on thread resume for removed breakpoint")
      end
      
      print("✓ Test completed successfully - removed breakpoints don't create extmarks on thread resume!")
    end
    
    -- Cleanup
    virtualTextInstance.destroy()
  end)
end)
