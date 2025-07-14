local BreakpointApi = require("neodap.plugins.BreakpointApi")
local name = "BreakpointVirtualText"

return {
  name = name,
  description = "Plugin to display breakpoints with virtual text at precise column positions",
  ---@param api Api
  plugin = function(api)
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
      local mark = marks.normal
      
      breakpoint:onBinding(function(binding)
        local location = binding:getActualLocation()

        binding:onHit(function(_, resumed)
          location:mark(ns, marks.hit)
          resumed.wait()
          location:mark(ns, mark)
        end)
        
        binding:onDispose(function () location:unmark(ns) end)
        
        binding:onUpdated(function()
          location:unmark(ns)
          location = binding:getActualLocation()
          if binding:wasMoved() then
            mark = marks.adjusted
          end
          location:mark(ns, mark)
        end)
  
        mark = binding:wasMoved() and marks.adjusted or marks.bound
        location:mark(ns, mark)
      end)

      breakpoint:onDispose(function()
        breakpoint.location:unmark(ns)
      end)

      breakpoint.location:mark(ns, mark)
    end)


    return {
      destroy = function()
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
          end
        end
      end,

      -- Expose some debugging info
      getNamespace = function() return ns end,
    }
  end
}
