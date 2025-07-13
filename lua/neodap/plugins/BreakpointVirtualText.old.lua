-- local name = "BreakpointVirtualText"

-- return {
--   name = name,
--   description = "Plugin to display breakpoints with virtual text at precise column positions",
--   ---@param api Api
--   plugin = function(api)
--     local nio = require("nio")
--     local Logger = require("neodap.tools.logger")
--     local log = Logger.get()

--     -- Use BreakpointManager plugin through the plugin API
--     local BreakpointManagerPlugin = require("neodap.plugins.BreakpointManager")
--     local breakpoint_manager = api:getPluginInstance(BreakpointManagerPlugin)
    
--     log:info("BreakpointVirtualText: Plugin loading with BreakpointManager plugin integration")

--     -- Virtual text symbols for different breakpoint states
--     local symbols = {
--       normal = "●",     -- Normal breakpoint at intended location
--       adjusted = "◐",   -- Breakpoint moved by debug adapter
--       hit = "◆",        -- Hit breakpoint (stopped)
--       hit_adjusted = "◈", -- Hit breakpoint that was moved by debug adapter
--       disabled = "○",   -- Disabled breakpoint
--       rejected = "✗"    -- Rejected/failed breakpoint
--     }

--     -- Highlight groups for different breakpoint states
--     local highlight_groups = {
--       normal = "DiagnosticInfo",      -- Blue-ish
--       adjusted = "DiagnosticWarn",    -- Orange/Yellow - indicates location changed
--       hit = "DiagnosticWarn",         -- Orange/Yellow
--       hit_adjusted = "DiagnosticError", -- Red - hit breakpoint that was moved
--       disabled = "Comment",           -- Grayed out
--       rejected = "DiagnosticError"    -- Red
--     }

--     -- Create unique namespace for this plugin instance to prevent conflicts
--     local namespace_name = "neodap_bpvt_" .. tostring(api)
--     local namespace = vim.api.nvim_create_namespace(namespace_name)
--     log:info("BreakpointVirtualText: Created namespace", namespace_name, "with ID", namespace, "for API instance", tostring(api))
    
--     -- Track if plugin is destroyed to prevent operations after destruction
--     local plugin_destroyed = false
    
--     -- Log namespace info for debugging
--     log:debug("NAMESPACE_INFO: Created namespace with details:", {
--       name = namespace_name,
--       id = namespace,
--       api_instance = tostring(api),
--       api_hash = tostring(api):match("0x%x+") or "unknown"
--     })

--     -- Track virtual text for cleanup - each breakpoint can have multiple extmarks due to timing issues
--     local virtual_texts = {}
    
--     -- Track recent breakpoint events separately to avoid contaminating virtual_texts
--     local recent_events = {}
    
--     -- Track pending operations for buffers that aren't loaded yet
--     local pending_operations = {}
    
--     -- Helper function to execute operation when buffer is loaded
--     local function when_buffer_loaded(bufnr, operation)
--       vim.schedule(function()
--         if not vim.api.nvim_buf_is_valid(bufnr) then
--           return
--         end
        
--         local line_count = vim.api.nvim_buf_line_count(bufnr)
--         if line_count > 0 then
--           -- Buffer is loaded, execute immediately
--           operation()
--         else
--           -- Buffer not loaded, queue operation and set up autocommand
--           if not pending_operations[bufnr] then
--             pending_operations[bufnr] = {}
            
--             -- Set up autocommand to trigger when buffer loads
--             vim.api.nvim_create_autocmd({"BufRead", "BufReadPost"}, {
--               buffer = bufnr,
--               once = true,
--               callback = function()
--                 local ops = pending_operations[bufnr]
--                 if ops then
--                   pending_operations[bufnr] = nil
--                   for _, op in ipairs(ops) do
--                     vim.schedule(op)
--                   end
--                 end
--               end
--             })
--           end
          
--           table.insert(pending_operations[bufnr], operation)
          
--           -- Force load the buffer
--           vim.api.nvim_buf_call(bufnr, function()
--             vim.cmd("silent! edit!")
--           end)
--         end
--       end)
--     end

--     -- Helper function to get display information for a breakpoint
--     local function get_breakpoint_display(breakpoint, binding, is_hit)
--       local requested = breakpoint.location
--       local actual = binding and binding.verified and {
--         line = binding.actualLine or requested.line,
--         column = binding.actualColumn or requested.column
--       } or requested
      
--       -- Check for location mismatch
--       local has_mismatch = binding and binding.verified and (
--         binding.actualLine ~= requested.line or
--         binding.actualColumn ~= requested.column
--       )
      
--       -- Determine symbol and highlight based on state
--       local symbol, highlight
--       if is_hit then
--         symbol = has_mismatch and symbols.hit_adjusted or symbols.hit
--         highlight = has_mismatch and highlight_groups.hit_adjusted or highlight_groups.hit
--       else
--         symbol = has_mismatch and symbols.adjusted or symbols.normal
--         highlight = has_mismatch and highlight_groups.adjusted or highlight_groups.normal
--       end
      
--       -- Generate tooltip for mismatches
--       local tooltip = has_mismatch and (
--         "Breakpoint moved by debug adapter\n" ..
--         "Requested: line " .. requested.line .. ", col " .. (requested.column or 0) .. "\n" ..
--         "Actual: line " .. actual.line .. ", col " .. (actual.column or 0)
--       ) or nil
      
--       return {
--         location = actual,  -- Use actual location for display
--         symbol = symbol,
--         highlight = highlight,
--         tooltip = tooltip,
--         has_mismatch = has_mismatch
--       }
--     end

--     -- Helper function to place virtual text
--     local function place_virtual_text(bufnr, line, col, symbol, highlight, breakpoint_id, tooltip)
--       vim.schedule(function()
--         -- Check if plugin was destroyed before executing
--         if plugin_destroyed then
--           return
--         end
        
--         local log = Logger.get()
--         log:info("VTEXT_PLACE: Placing virtual text:", symbol, "at line", line, "col", col, "in buffer", bufnr, "for breakpoint", breakpoint_id, "at timestamp", os.clock())
--         log:debug("EXTMARK: Placing virtual text:", symbol, "at line", line, "col", col, "in buffer", bufnr, "for breakpoint", breakpoint_id)
--         log:debug("NAMESPACE_USAGE: Using namespace", namespace, "(name:", namespace_name, ") for API", tostring(api))
        
--         -- Log current extmarks at this location before placing new one
--         local existing_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {details = true})
--         local existing_at_line = {}
--         for _, extmark in ipairs(existing_extmarks) do
--           if extmark[2] == math.max(0, math.min(line - 1, vim.api.nvim_buf_line_count(bufnr) - 1)) then
--             table.insert(existing_at_line, {id = extmark[1], line = extmark[2], col = extmark[3], text = extmark[4].virt_text and extmark[4].virt_text[1] and extmark[4].virt_text[1][1] or "none"})
--           end
--         end
--         if #existing_at_line > 0 then
--           log:warn("EXTMARK: Found", #existing_at_line, "existing extmarks at line", line, "before placing new one:", vim.inspect(existing_at_line))
--         else
--           log:debug("EXTMARK: No existing extmarks at line", line)
--         end

--         -- Clear any existing virtual text for this breakpoint
--         if virtual_texts[breakpoint_id] then
--           local old_vt = virtual_texts[breakpoint_id]
--           log:debug("Clearing existing virtual text for breakpoint", breakpoint_id)
--           -- Clean up all previous extmarks for this breakpoint
--           if old_vt.extmark_ids then
--             for _, extmark_id in ipairs(old_vt.extmark_ids) do
--               log:debug("Removing extmark ID:", extmark_id)
--               pcall(vim.api.nvim_buf_del_extmark, old_vt.bufnr, namespace, extmark_id)
--             end
--           elseif old_vt.extmark_id then
--             -- Backward compatibility with single extmark_id
--             log:debug("Removing single extmark ID:", old_vt.extmark_id)
--             pcall(vim.api.nvim_buf_del_extmark, old_vt.bufnr, namespace, old_vt.extmark_id)
--           end
--           -- Reset the tracking for this breakpoint
--           virtual_texts[breakpoint_id] = nil
--         end

--         -- Place new virtual text (ensure line is valid and 0-indexed)
--         local line_count = vim.api.nvim_buf_line_count(bufnr)
--         local extmark_line = math.max(0, math.min(line - 1, line_count - 1))
        
--         log:debug("Buffer", bufnr, "has", line_count, "lines, placing extmark at line", extmark_line, "col", col)
        
--         -- Prepare extmark options
--         local extmark_opts = {
--           virt_text = {{symbol, highlight}},
--           virt_text_pos = "inline",
--           priority = 200  -- Higher priority than frame highlights
--         }
        
--         -- Add tooltip support if available (Neovim 0.10+)
--         if tooltip and vim.fn.has('nvim-0.10') == 1 then
--           extmark_opts.sign_text = symbol
--           extmark_opts.sign_hl_group = highlight
--           -- Note: Tooltip support would need additional implementation
--           -- For now, we'll log the tooltip information
--           log:debug("Tooltip for breakpoint", breakpoint_id, ":", tooltip)
--         end

        
        
--         -- Place virtual text just before the target character (to the left)
--         local virtual_text_col = math.max(0, col - 1)
--         local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, extmark_line, virtual_text_col, extmark_opts)
        
--         log:info("VTEXT_PLACED: Virtual text placed successfully with extmark ID:", extmark_id, "at timestamp", os.clock())

--         -- Track for cleanup - always create new entry since we cleared existing above
--         virtual_texts[breakpoint_id] = {
--           bufnr = bufnr,
--           line = line,
--           col = col,
--           extmark_ids = {extmark_id}
--         }
        
--         -- Capture buffer snapshot after placing virtual text
--         log:snapshot(bufnr, "After placing " .. symbol .. " for " .. breakpoint_id)
--       end)
--     end

--     -- Helper function to remove virtual text
--     local function remove_virtual_text(breakpoint_id)
--       local vt = virtual_texts[breakpoint_id]
--       if vt then
--         vim.schedule(function()
--           -- Check if plugin was destroyed before executing
--           if plugin_destroyed then
--             return
--           end
          
--           local log = Logger.get()
--           log:info("VTEXT_REMOVE: Removing virtual text for breakpoint", breakpoint_id, "at timestamp", os.clock())
--           -- Remove all extmarks for this breakpoint
--           if vt.extmark_ids then
--             for _, extmark_id in ipairs(vt.extmark_ids) do
--               log:debug("Removing extmark ID:", extmark_id)
--               pcall(vim.api.nvim_buf_del_extmark, vt.bufnr, namespace, extmark_id)
--             end
--           elseif vt.extmark_id then
--             -- Backward compatibility
--             log:debug("Removing extmark ID:", vt.extmark_id)
--             pcall(vim.api.nvim_buf_del_extmark, vt.bufnr, namespace, vt.extmark_id)
--           end
--         end)
--         virtual_texts[breakpoint_id] = nil
--       end
--     end

--     -- Note: Refresh function removed - the extmark ID cleanup logic handles placement properly

--     log:info("BreakpointVirtualText registering onBreakpoint handler")
    
--     breakpoint_manager.onBreakpoint(function(breakpoint)
--       local handler_log = Logger.get()
--       local timestamp = os.clock()
--       handler_log:info("EVENT: BreakpointVirtualText onBreakpoint handler triggered at", timestamp, "for:", breakpoint.id)
      
--       -- Check if we've seen this breakpoint recently (within 100ms)
--       local recent_key = "recent_" .. breakpoint.id
--       local last_time = recent_events[recent_key] or 0
--       if timestamp - last_time < 0.1 then
--         handler_log:warn("EVENT: Duplicate/rapid breakpoint event for", breakpoint.id, "- last seen", timestamp - last_time, "seconds ago")
--       end
--       recent_events[recent_key] = timestamp

--       -- nio.run(function()
--       local bufnr = breakpoint.location:bufnr()
--       log:debug("BreakpointVirtualText: Breakpoint bound to buffer:", bufnr)

--       if not bufnr then
--         log:warn("Could not get buffer number for breakpoint at", breakpoint.location.path)
--         return
--       end

--       -- Place virtual text when buffer is loaded
--       when_buffer_loaded(bufnr, function()
--         log:debug("BreakpointVirtualText: Buffer", bufnr, "is loaded, placing virtual text")
        
--         -- Get display information (initially no binding, so use requested location)
--         local display = get_breakpoint_display(breakpoint, nil, false)
        
--         place_virtual_text(
--           bufnr, 
--           display.location.line, 
--           display.location.column or 0,
--           display.symbol,
--           display.highlight,
--           breakpoint.id,
--           display.tooltip
--         )
--       end)

--         -- Handle breakpoint bindings (when bound to a session)
--         breakpoint:onBound(function(binding)
--           log:debug("BreakpointVirtualText: Breakpoint bound in session", binding.session.id)
          
--           -- Update display based on binding information
--           when_buffer_loaded(bufnr, function()
--             local display = get_breakpoint_display(breakpoint, binding, false)
            
--             if display.has_mismatch then
--               log:info("BreakpointVirtualText: Location mismatch detected, updating display to actual location")
--             end
            
--             place_virtual_text(
--               bufnr,
--               display.location.line,
--               display.location.column or 0,
--               display.symbol,
--               display.highlight,
--               breakpoint.id,
--               display.tooltip
--             )
--           end)
--         -- end)

--         -- Handle breakpoint hits - change to hit symbol
--         breakpoint:onHit(function(hit)
--           nio.run(function()
--             local hit_bufnr = breakpoint.location:bufnr()
--             if not hit_bufnr then return end

--             when_buffer_loaded(hit_bufnr, function()
--               log:debug("BreakpointVirtualText: Updating to hit symbol")
              
--               local display = get_breakpoint_display(breakpoint, hit.binding, true)
              
--               place_virtual_text(
--                 hit_bufnr,
--                 display.location.line,
--                 display.location.column or 0,
--                 display.symbol,
--                 display.highlight,
--                 breakpoint.id,
--                 display.tooltip
--               )
--             end)
--           end)
--         end)

--         -- Handle breakpoint removal
--         handler_log:debug("BreakpointVirtualText: Registering removal handler for breakpoint", breakpoint.id)
--         local cleanup_handler
--         cleanup_handler = breakpoint_manager.onBreakpointRemoved(function(removed_breakpoint)
--           handler_log:debug("BreakpointVirtualText: Removal event received for breakpoint", removed_breakpoint.id)
--           if removed_breakpoint.id == breakpoint.id then
--             handler_log:info("BreakpointVirtualText: Removing virtual text for breakpoint", breakpoint.id)
--             remove_virtual_text(breakpoint.id)
            
--             -- Remove this handler since the breakpoint is gone
--             if cleanup_handler then
--               handler_log:debug("BreakpointVirtualText: Cleaning up removal handler for", breakpoint.id)
--               cleanup_handler()
--             end
--           end
--         end)
--       end)
--     end)

--     -- Handle session cleanup - clear all virtual text when sessions terminate
--     api:onSession(function(session)
--       log:debug("BreakpointVirtualText: Registering cleanup and thread handlers for session", session.id)
      
--       -- Handle thread events to reset hit breakpoints when execution resumes
--         session:onThread(function(thread)
--           thread:onResumed(function()
--             log:debug("BreakpointVirtualText: Thread resumed, resetting hit breakpoints to normal")

--             vim.schedule(function()
--               -- Check if plugin was destroyed before executing
--               if plugin_destroyed then
--                 return
--               end
              
--               -- Reset all hit breakpoints back to normal state
--               for breakpoint_id, vt in pairs(virtual_texts) do
--                 if vt and vt.bufnr and vim.api.nvim_buf_is_valid(vt.bufnr) then
--                 -- Find the corresponding breakpoint
--                 for breakpoint in breakpoint_manager.getBreakpoints():each() do
--                   if breakpoint.id == breakpoint_id then
--                     when_buffer_loaded(vt.bufnr, function()
--                       log:debug("BreakpointVirtualText: Resetting breakpoint", breakpoint_id, "to normal symbol")
                      
--                       -- Get the current binding for this breakpoint
--                       local current_binding = nil
--                       for binding in breakpoint_manager.getBindings():forBreakpoint(breakpoint):each() do
--                         if binding.verified then
--                           current_binding = binding
--                           break
--                         end
--                       end
                      
--                       local display = get_breakpoint_display(breakpoint, current_binding, false)
                      
--                       place_virtual_text(
--                         vt.bufnr,
--                         display.location.line,
--                         display.location.column or 0,
--                         display.symbol,
--                         display.highlight,
--                         breakpoint.id,
--                         display.tooltip
--                       )
--                     end)
--                     break
--                   end
--                 end
--               end
--             end
--           end)
--         end)
--       end)
      
--       -- Listen for session termination events
--       session:onTerminated(function()
--         log:info("VTEXT_SESSION_TERMINATED: Session", session.id, "terminated, cleaning up virtual text at timestamp", os.clock())
        
--         -- Clear all virtual text for this session
--         vim.schedule(function()
--           -- Check if plugin was destroyed before executing
--           if plugin_destroyed then
--             return
--           end
          
--           for breakpoint_id, vt in pairs(virtual_texts) do
--             if vt and vt.bufnr and vim.api.nvim_buf_is_valid(vt.bufnr) then
--               log:debug("BreakpointVirtualText: Cleaning up virtual text for breakpoint", breakpoint_id, "in session", session.id)
--               remove_virtual_text(breakpoint_id)
--             end
--           end
--         end)
--       end)
      
--       -- Also listen for session exit events
--       session:onExited(function()
--         log:info("VTEXT_SESSION_EXITED: Session", session.id, "exited, ensuring virtual text cleanup at timestamp", os.clock())
        
--         -- Additional cleanup for any remaining virtual text
--         vim.schedule(function()
--           -- Check if plugin was destroyed before executing
--           if plugin_destroyed then
--             return
--           end
          
--           -- Clear the entire namespace for safety
--           for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
--             if vim.api.nvim_buf_is_valid(bufnr) then
--               vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
--             end
--           end
          
--           -- Clear tracking tables
--           virtual_texts = {}
--           recent_events = {}
--           pending_operations = {}
          
--           log:debug("BreakpointVirtualText: Complete virtual text cleanup completed for session", session.id)
--         end)
--       end)
--     end)

--     -- Note: Thread onStopped refresh removed - individual breakpoint onHit handlers manage state correctly
    
--     -- Return API for cleanup and debugging
--     return {
--       destroy = function()
--         log:info("BreakpointVirtualText: Destroying plugin instance for API", tostring(api), "namespace", namespace_name, "at timestamp", os.clock())
        
--         -- Mark plugin as destroyed to prevent pending operations
--         plugin_destroyed = true
        
--         -- Count virtual texts before cleanup
--         local vt_count = 0
--         for _ in pairs(virtual_texts) do
--           vt_count = vt_count + 1
--         end
--         log:info("BreakpointVirtualText: Cleaning up", vt_count, "tracked virtual texts")
        
--         -- Clear all virtual text from this plugin instance
--         local buffers_cleared = 0
--         for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
--           if vim.api.nvim_buf_is_valid(bufnr) then
--             local extmarks_before = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {})
--             vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
--             local extmarks_after = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {})
            
--             if #extmarks_before > 0 then
--               buffers_cleared = buffers_cleared + 1
--               log:info("BreakpointVirtualText: Cleared", #extmarks_before, "extmarks from buffer", bufnr, 
--                       "(", #extmarks_after, "remaining)")
--             end
--           end
--         end
        
--         -- Clear tracking tables
--         virtual_texts = {}
--         recent_events = {}
--         pending_operations = {}
        
--         log:info("BreakpointVirtualText: Plugin instance destroyed successfully - cleared", buffers_cleared, "buffers")
--       end,
      
--       -- Expose some debugging info
--       getNamespace = function() return namespace end,
--       getNamespaceName = function() return namespace_name end,
--       getVirtualTexts = function() return virtual_texts end,
--     }
--   end
-- }