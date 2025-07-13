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
    
    BP.onBreakpoint(function(breakpoint)      
      local hits = 0;
      local mark = marks.normal
      
      breakpoint:onBinding(function(binding)        
        local location = binding:getActualLocation()

        binding:onHit(function(hit)
          hits = hits + 1
    
          hit.thread:onResumed(function()
            if binding.hookable.destroyed then
              return
            end
            hits = hits - 1
            if hits <= 0 then
              hits = 0
              location:mark(ns, mark)
            end
          end)
  
          location:mark(ns, marks.hit)
        end)
        
        location:SourceFile():deferUntilLoaded()
        
        binding:onDispose(function () location:unmark(ns) end)

        binding:onUpdated(function()
          location:unmark(ns)
          location = binding:getActualLocation()
          if binding:wasMoved() then
            mark = marks.adjusted
          end
          location:mark(ns, mark)
        end)
        
        -- Mark the binding with appropriate symbol
        local mark = binding:wasMoved() and marks.adjusted or marks.bound        
        
        binding:getActualLocation():mark(ns, mark)
        if binding:wasMoved() then
          breakpoint.location:unmark(ns)
        end
      end)

      breakpoint:onDispose(function()
        breakpoint.location:unmark(ns)
      end)


      breakpoint.location:SourceFile():deferUntilLoaded()
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
