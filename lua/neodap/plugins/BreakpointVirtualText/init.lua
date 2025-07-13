local Logger = require("neodap.tools.logger")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local name = "BreakpointVirtualText"

return {
  name = name,
  description = "Plugin to display breakpoints with virtual text at precise column positions",
  ---@param api Api
  plugin = function(api)
    local log = Logger.get()

    -- Use BreakpointApi plugin through the plugin API
    local BP = api:getPluginInstance(BreakpointApi)

    local namespace_name = "neodap_bpvt_" .. tostring(api)
    local ns = vim.api.nvim_create_namespace(namespace_name)

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
    
    BP.onBreakpoint(function(breakpoint)      
      breakpoint:onBinding(function(binding)        
        local location = binding:getActualLocation()
        
        location:SourceFile():deferUntilLoaded()
        
        binding:onDispose(function () location:unmark(ns) end)

        binding:onUpdated(function()
          location:unmark(ns)
          location = binding:getActualLocation()
          location:mark(ns, marks.adjusted)
        end)
        
        -- Mark the binding with appropriate symbol
        local mark = binding:wasMoved() and marks.adjusted or marks.bound        
        
        binding:getActualLocation():mark(ns, mark)
        if binding:wasMoved() then
          breakpoint.location:unmark(ns)
        end
      end)

      -- Handle breakpoint hits - replace existing symbol with hit symbol
      breakpoint:onHit(function(hit)
        local hit_location = hit.binding:getActualLocation()

        hit_location:unmark(ns)
        hit_location:mark(ns, marks.hit)
        
        -- Track that this binding is currently hit (for future restoration)
        hit_bindings[hit.binding] = true
        
        hit.binding:onDispose(function()
          hit_bindings[hit.binding] = nil
        end)
      end)

      breakpoint:onDispose(function()
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
      end)


      breakpoint.location:SourceFile():deferUntilLoaded()
    end)

    -- Handle thread resume to restore symbols after hits
    api:onSession(function(session)
      session:onThread(function(thread)
        thread:onResumed(function()
          
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
                location:mark(ns, mark)
                
                restored_count = restored_count + 1
              else
                skipped_count = skipped_count + 1
              end
            else
              skipped_count = skipped_count + 1
            end
          end
                    
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
