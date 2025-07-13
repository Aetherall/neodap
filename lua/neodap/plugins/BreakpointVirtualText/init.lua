local Logger = require("neodap.tools.logger")
local name = "BreakpointVirtualText"

return {
  name = name,
  description = "Plugin to display breakpoints with virtual text at precise column positions",
  ---@param api Api
  plugin = function(api)
    local log = Logger.get()

    -- Use BreakpointManager plugin through the plugin API
    local BreakpointManagerPlugin = require("neodap.plugins.BreakpointManager")
    local breakpoint_manager = api:getPluginInstance(BreakpointManagerPlugin)

    log:info("BreakpointVirtualText: Plugin loading with BreakpointManager plugin integration")

    -- Create unique namespace for this plugin instance to prevent conflicts
    local namespace_name = "neodap_bpvt_" .. tostring(api)
    local ns = vim.api.nvim_create_namespace(namespace_name)


    log:info("BreakpointVirtualText: Created namespace", namespace_name, "with ID", ns, "for API instance",
      tostring(api))

    log:debug("NAMESPACE_INFO: Created namespace with details:", {
      name = namespace_name,
      id = ns,
      api_instance = tostring(api),
      api_hash = tostring(api):match("0x%x+") or "unknown"
    })


    local marks = {
      normal = {
        virt_text = { { "●", "DiagnosticInfo" } },
        virt_text_pos = "inline",
        priority = 200,
      },
      bound = {
        virt_text = { { "◉", "DiagnosticInfo" } },
        virt_text_pos = "inline",
        priority = 200,
      },
      adjusted = {
        virt_text = { { "◐", "DiagnosticInfo" } },
        virt_text_pos = "inline",
        priority = 200,
      },
      hit = {
        virt_text = { { "◆", "DiagnosticWarn" } },
        virt_text_pos = "inline",
        priority = 200,
      },
      disabled = {
        virt_text = { { "○", "Comment" } },
        virt_text_pos = "inline",
        priority = 200,
      },
    }

    -- Track bindings that are currently hit
    local hit_bindings = {}
    
    breakpoint_manager.onBreakpoint(function(breakpoint)
      log:info("BPVT2: onBreakpoint triggered for breakpoint:", breakpoint.id, "namespace:", ns)
      
      breakpoint:onBinding(function(binding)
        log:info("BPVT2: onBinding triggered for breakpoint:", breakpoint.id, "session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
        
        local current_location = binding:getActualLocation()
        
        -- Ensure buffer is loaded before marking
        current_location:deferUntilLoaded()
        
        binding:onDispose(function ()
          log:info("BPVT2: onDispose triggered for breakpoint:", breakpoint.id, "session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
          current_location:unmark(ns)
        end)  -- onDispose is non-preemptible by default

        binding:onUpdated(function()
          log:info("BPVT2: onUpdated triggered for breakpoint:", breakpoint.id, "session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
          current_location:unmark(ns)
          current_location = binding:getActualLocation()
          current_location:mark(ns, marks.adjusted)
        end)
        
        -- Mark the binding with appropriate symbol
        local mark = binding:wasMoved() and marks.adjusted or marks.bound
        log:info("BPVT2: Marking binding at", current_location.line, current_location.column, "with symbol:", mark.virt_text[1][1], "moved:", binding:wasMoved(), "session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
        
        -- Debug: Check buffer state before marking
        local bufnr = current_location:bufnr()
        local loaded = bufnr and vim.api.nvim_buf_is_loaded(bufnr)
        log:info("BPVT2: Buffer state before mark - bufnr:", bufnr, "loaded:", loaded)
        
        local extmark_id = binding:getActualLocation():mark(ns, mark)
        log:info("BPVT2: Mark result - extmark_id:", extmark_id)
        
        -- Debug: Verify extmark was actually placed
        if bufnr and loaded then
          local placed_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
          log:info("BPVT2: Extmarks after mark:", #placed_extmarks)
        end
        
        -- If binding was moved, unmark the original location
        if binding:wasMoved() then
          log:info("BPVT2: Unmarking original location for moved binding, session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
          breakpoint.location:unmark(ns)
        end
      end)

      -- Handle breakpoint hits - replace existing symbol with hit symbol
      breakpoint:onHit(function(hit)
        log:info("BPVT2: onHit triggered for breakpoint:", breakpoint.id, "session:", hit.binding.session and hit.binding.session.id or "no-session", "namespace:", ns)
        local hit_location = hit.binding:getActualLocation()
        
        -- Debug: Log location details and existing extmarks
        local bufnr = hit_location:bufnr()
        log:info("BPVT2: Hit location details - line:", hit_location.line, "column:", hit_location.column, "buffer:", bufnr)
        
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
          local existing_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
          log:info("BPVT2: Found", #existing_extmarks, "existing extmarks in namespace", ns, "before unmark")
          for i, extmark in ipairs(existing_extmarks) do
            local line_0based = extmark[2]
            local col_0based = extmark[3]
            local virt_text = "none"
            if extmark[4] and extmark[4].virt_text and extmark[4].virt_text[1] then
              virt_text = extmark[4].virt_text[1][1] or "none"
            end
            log:info("BPVT2: Extmark", i, "- id:", extmark[1], "line:", line_0based + 1, "col:", col_0based + 1, "text:", virt_text)
          end
        end
        
        -- First unmark the existing symbol at this location
        log:info("BPVT2: Unmarking existing symbol at", hit_location.line, hit_location.column, "namespace:", ns)
        hit_location:unmark(ns)
        
        -- Debug: Check extmarks after unmark
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
          local remaining_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
          log:info("BPVT2: Found", #remaining_extmarks, "remaining extmarks in namespace", ns, "after unmark")
        end
        
        -- Then mark with hit symbol
        log:info("BPVT2: Marking with hit symbol at", hit_location.line, hit_location.column, "namespace:", ns)
        hit_location:mark(ns, marks.hit)
        
        -- Track that this binding is currently hit (for future restoration)
        hit_bindings[hit.binding] = true
        
        -- Clean up hit_bindings when the binding is disposed
        hit.binding:onDispose(function()
          log:info("BPVT2: Cleaning up hit binding from tracking due to disposal, namespace:", ns)
          hit_bindings[hit.binding] = nil
        end)
      end)

      breakpoint:onDispose(function()
        log:info("BPVT2: Breakpoint disposed, cleaning up location and hit tracking, namespace:", ns)
        breakpoint.location:unmark(ns)
        
        -- Clean up any hit bindings associated with this breakpoint
        local cleaned_bindings = 0
        for binding, _ in pairs(hit_bindings) do
          -- Check if this binding belongs to the disposed breakpoint
          if binding and binding.breakpoint == breakpoint then
            hit_bindings[binding] = nil
            cleaned_bindings = cleaned_bindings + 1
          end
        end
        
        if cleaned_bindings > 0 then
          log:info("BPVT2: Cleaned", cleaned_bindings, "hit binding references for disposed breakpoint:", breakpoint.id, "namespace:", ns)
        end
      end)


      breakpoint.location:deferUntilLoaded()

      -- Only show normal symbol if no bindings exist
      -- The onBinding handler will handle all bindings (new and existing)
      if breakpoint:getBindings():isEmpty() then
        log:info("BPVT2: No bindings exist, marking normal symbol for breakpoint:", breakpoint.id, "namespace:", ns)
        
        -- Debug: Check buffer state before marking
        local bufnr = breakpoint.location:bufnr()
        local loaded = bufnr and vim.api.nvim_buf_is_loaded(bufnr)
        log:info("BPVT2: Buffer state before normal mark - bufnr:", bufnr, "loaded:", loaded)
        
        local extmark_id = breakpoint.location:mark(ns, marks.normal)
        log:info("BPVT2: Normal mark result - extmark_id:", extmark_id)
        
        -- Debug: Verify extmark was actually placed
        if bufnr and loaded then
          local placed_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
          log:info("BPVT2: Extmarks after normal mark:", #placed_extmarks)
        end
      else
        log:info("BPVT2: Bindings exist for breakpoint:", breakpoint.id, "count:", breakpoint:getBindings():count(), "- letting onBinding handler manage them, namespace:", ns)
      end
    end)

    -- Handle thread resume to restore symbols after hits
    api:onSession(function(session)
      session:onThread(function(thread)
        thread:onResumed(function()
          log:info("BPVT2: Thread resumed, restoring hit breakpoint symbols")
          
          -- Restore all hit bindings to their original symbols
          local restored_count = 0
          local skipped_count = 0
          
          for binding, _ in pairs(hit_bindings) do
            -- Validate that the binding still exists and has a valid location
            if binding and binding:getActualLocation() then
              local location = binding:getActualLocation()
              
              -- Additional validation: check if the binding's breakpoint still exists
              -- by trying to access its properties safely
              local success, is_moved = pcall(function() return binding:wasMoved() end)
              
              if success then
                -- Unmark hit symbol
                location:unmark(ns)
                
                -- Restore original symbol based on whether binding was moved
                local mark = is_moved and marks.adjusted or marks.bound
                log:info("BPVT2: Restoring symbol at", location.line, location.column, "to", mark.virt_text[1][1], "namespace:", ns)
                location:mark(ns, mark)
                
                restored_count = restored_count + 1
              else
                log:info("BPVT2: Skipping restoration for invalid binding (breakpoint likely removed), namespace:", ns)
                skipped_count = skipped_count + 1
              end
            else
              log:info("BPVT2: Skipping restoration for disposed binding, namespace:", ns)
              skipped_count = skipped_count + 1
            end
          end
          
          log:info("BPVT2: Resume restoration complete - restored:", restored_count, "skipped:", skipped_count, "namespace:", ns)
          
          -- Clear hit bindings tracking
          hit_bindings = {}
        end)
      end)
    end)

    return {
      destroy = function()
        log:info("BreakpointVirtualText: Destroying plugin instance and clearing namespace", namespace_name)
        
        -- Clear namespace from all valid buffers
        local buffers_cleared = 0
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(bufnr) then
            local extmarks_before = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
            vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
            local extmarks_after = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
            
            if #extmarks_before > 0 then
              buffers_cleared = buffers_cleared + 1
              log:info("BreakpointVirtualText: Cleared", #extmarks_before, "extmarks from buffer", bufnr, 
                      "namespace", ns, "(", #extmarks_after, "remaining)")
            end
          end
        end
        log:info("BreakpointVirtualText: Destroyed namespace", ns, "- cleared", buffers_cleared, "buffers")
      end,

      -- Expose some debugging info
      getNamespace = function() return ns end,
    }
  end
}
