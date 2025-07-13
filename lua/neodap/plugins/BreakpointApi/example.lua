-- -- Example usage of the new hierarchical breakpoint API
-- local Location = require('neodap.plugins.BreakpointApi.Location')

-- -- This demonstrates how plugins would use the hierarchical API
-- -- Note: All events now follow proper hierarchical responsibility!
-- local function setupBreakpointPlugin(manager)
  
--   -- Hierarchical event registration - the key innovation
--   manager:onBreakpoint(function(breakpoint)
--     print("New breakpoint added:", breakpoint.id)
    
--     -- Set up a hit counter for this breakpoint
--     local totalHits = 0
    
--     -- Register for bindings within this breakpoint's lifetime
--     breakpoint:onBinding(function(binding)
--       print("  Binding created in session:", binding.session.id)
      
--       -- Track hits per binding (session-specific)
--       local sessionHits = 0
      
--       binding:onHit(function(hit)
--         sessionHits = sessionHits + 1
--         totalHits = totalHits + 1
        
--         print("    Hit #" .. sessionHits .. " in session " .. binding.session.id)
--         print("    Total hits for breakpoint: " .. totalHits)
        
--         -- Show variables at hit point
--         hit.thread:getTopFrame(function(frame)
--           frame:getScopes(function(scopes)
--             local locals = scopes:locals()
--             if locals then
--               print("    Local variables:")
--               for variable in locals:eachVariable() do
--                 print("      " .. variable.name .. " = " .. variable.value)
--               end
--             end
--           end)
--         end)
--       end)
      
--       binding:onUpdated(function(dapBreakpoint)
--         if binding:wasMoved() then
--           print("    Binding moved from line " .. binding.line .. 
--                 " to line " .. binding.actualLine)
--         end
--       end)
      
--       binding:onUnbound(function()
--         print("    Binding removed from session:", binding.session.id)
--         print("    Final hit count for this session:", sessionHits)
--       end)
      
--       -- Automatic cleanup when binding is removed
--     end)
    
--     breakpoint:onConditionChanged(function(condition)
--       print("  Condition changed to:", condition or "none")
--     end)
    
--     breakpoint:onRemoved(function()
--       print("Breakpoint removed:", breakpoint.id)
--       print("Final total hits:", totalHits)
--       -- All child event registrations automatically cleaned up
--       -- Note: This event comes from the breakpoint itself, not the manager!
--     end)
    
--     -- Automatic cleanup when breakpoint is removed
--   end)
  
--   -- Source-level pending events for UI feedback
--   manager:onSourceSyncPending(function(event)
--     print("Syncing " .. #event.breakpoints .. " breakpoints to " .. 
--           event.session.id .. " for " .. event.source:identifier())
--   end)
  
--   manager:onSourceSyncComplete(function(event)
--     print("Sync complete for " .. event.source:identifier() .. 
--           " in session " .. event.session.id)
--   end)
-- end

-- -- Example API usage
-- local function demonstrateAPI(manager)
--   -- Create a breakpoint
--   local location = Location.SourceFile.fromCursor()
--   local breakpoint = manager:addBreakpoint(location, {
--     condition = "x > 10",
--     logMessage = "x is now {x}"
--   })
  
--   -- Modify breakpoint
--   breakpoint:setCondition("x > 20")
--   breakpoint:setLogMessage("x changed to {x}")
  
--   -- Query breakpoint state
--   print("Breakpoint location:", breakpoint:getLocation().path .. ":" .. breakpoint:getLocation().line)
--   print("Active bindings:")
--   for binding in breakpoint:getBindings():each() do
--     print("  Session:", binding.session.id)
--     if binding:wasMoved() then
--       print("    Moved to line:", binding.actualLine)
--     end
--   end
  
--   -- Toggle breakpoint
--   manager:toggleBreakpoint(location) -- Removes it
-- end

-- -- The API provides clean scoping and automatic cleanup:
-- -- 1. Events are scoped to resource lifetime
-- -- 2. No manual unregistration needed
-- -- 3. Hierarchical structure matches mental model
-- -- 4. Plugin code is simpler and more readable

-- -- Event Source Responsibility (corrected):
-- -- Manager emits: BreakpointAdded, BindingBound, SourceSyncPending/Complete
-- -- Breakpoint emits: Removed, ConditionChanged, LogMessageChanged
-- -- Binding emits: Hit, Updated, Unbound
-- -- No duplicate events - single source of truth for each event type!

-- return {
--   setupBreakpointPlugin = setupBreakpointPlugin,
--   demonstrateAPI = demonstrateAPI,
-- }