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
        virt_text = { { "◐", "DiagnosticWarn" } },
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

    breakpoint_manager.onBreakpoint(function(breakpoint)
      log:info("BPVT2: onBreakpoint triggered for breakpoint:", breakpoint.id, "namespace:", ns)
      
      breakpoint:onBinding(function(binding)
        log:info("BPVT2: onBinding triggered for breakpoint:", breakpoint.id, "session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
        
        local current_location = binding:getActualLocation()
        binding:onUnbound(function ()
          log:info("BPVT2: onUnbound triggered for breakpoint:", breakpoint.id, "session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
          current_location:unmark(ns)
        end)

        binding:onUpdated(function()
          log:info("BPVT2: onUpdated triggered for breakpoint:", breakpoint.id, "session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
          current_location:unmark(ns)
          current_location = binding:getActualLocation()
          current_location:mark(ns, marks.adjusted)
        end)
        
        -- Mark the binding with appropriate symbol
        local mark = binding:wasMoved() and marks.adjusted or marks.bound
        log:info("BPVT2: Marking binding at", current_location.line, current_location.column, "with symbol:", mark.virt_text[1][1], "moved:", binding:wasMoved(), "session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
        binding:getActualLocation():mark(ns, mark)
        
        -- If binding was moved, unmark the original location
        if binding:wasMoved() then
          log:info("BPVT2: Unmarking original location for moved binding, session:", binding.session and binding.session.id or "no-session", "namespace:", ns)
          breakpoint.location:unmark(ns)
        end
      end)

      -- Handle breakpoint hits - disabled for now to test basic functionality
      -- TODO: Implement proper hit symbol replacement that doesn't create duplicates
      --[[
      breakpoint:onHit(function(hit)
        log:info("BPVT2: onHit triggered for breakpoint:", breakpoint.id, "session:", hit.binding.session and hit.binding.session.id or "no-session", "namespace:", ns)
        local hit_location = hit.binding:getActualLocation()
        log:info("BPVT2: Adding hit symbol at", hit_location.line, hit_location.column, "namespace:", ns)
        hit_location:mark(ns, marks.hit)
      end)
      --]]

      breakpoint:onRemoved(function()
        breakpoint.location:unmark(ns)
      end)


      breakpoint.location:deferUntilLoaded()

      -- Only show normal symbol if no bindings exist
      -- The onBinding handler will handle all bindings (new and existing)
      if breakpoint:getBindings():isEmpty() then
        log:info("BPVT2: No bindings exist, marking normal symbol for breakpoint:", breakpoint.id, "namespace:", ns)
        breakpoint.location:mark(ns, marks.normal)
      else
        log:info("BPVT2: Bindings exist for breakpoint:", breakpoint.id, "count:", breakpoint:getBindings():count(), "- letting onBinding handler manage them, namespace:", ns)
      end
    end)

    return {
      destroy = function()
        log:info("BreakpointVirtualText: Destroying plugin instance and clearing namespace", namespace_name)
        
        -- Clear namespace from all valid buffers
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
