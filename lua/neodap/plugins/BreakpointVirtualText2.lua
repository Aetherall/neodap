local logger = require("neodap.tools.logger")
local name = "BreakpointVirtualText"

return {
  name = name,
  description = "Plugin to display breakpoints with virtual text at precise column positions",
  ---@param api Api
  plugin = function(api)
    local nio = require("nio")
    local Logger = require("neodap.tools.logger")
    local log = Logger.get()

    -- Use BreakpointManager plugin through the plugin API
    local BreakpointManagerPlugin = require("neodap.plugins.BreakpointManager")
    local breakpoint_manager = api:getPluginInstance(BreakpointManagerPlugin)

    log:info("BreakpointVirtualText: Plugin loading with BreakpointManager plugin integration")

    -- Virtual text symbols for different breakpoint states
    local symbols = {
      normal = "●", -- Normal breakpoint at intended location
      bound = "◉", -- Bound breakpoint (verified by debug adapter)
      adjusted = "◐", -- Breakpoint moved by debug adapter
      hit = "◆", -- Hit breakpoint (stopped)
      hit_adjusted = "◈", -- Hit breakpoint that was moved by debug adapter
      disabled = "○", -- Disabled breakpoint
      rejected = "✗" -- Rejected/failed breakpoint
    }

    -- Highlight groups for different breakpoint states
    local highlight_groups = {
      normal = "DiagnosticInfo",        -- Blue-ish
      adjusted = "DiagnosticWarn",      -- Orange/Yellow - indicates location changed
      hit = "DiagnosticWarn",           -- Orange/Yellow
      hit_adjusted = "DiagnosticError", -- Red - hit breakpoint that was moved
      disabled = "Comment",             -- Grayed out
      rejected = "DiagnosticError"      -- Red
    }

    -- Create unique namespace for this plugin instance to prevent conflicts
    local namespace_name = "neodap_bpvt_" .. tostring(api)
    local ns = vim.api.nvim_create_namespace(namespace_name)
    log:info("BreakpointVirtualText: Created namespace", namespace_name, "with ID", ns, "for API instance",
      tostring(api))

    -- Track if plugin is destroyed to prevent operations after destruction
    local plugin_destroyed = false

    -- Log namespace info for debugging
    log:debug("NAMESPACE_INFO: Created namespace with details:", {
      name = namespace_name,
      id = ns,
      api_instance = tostring(api),
      api_hash = tostring(api):match("0x%x+") or "unknown"
    })


    local marks = {
      normal = {
        virt_text = { { symbols.normal, highlight_groups.normal } },
        virt_text_pos = "inline",
        priority = 200,
      },
      bound = {
        virt_text = { { symbols.bound, highlight_groups.normal } },
        virt_text_pos = "inline",
        priority = 200,
      },
      adjusted = {
        virt_text = { { symbols.adjusted, highlight_groups.adjusted } },
        virt_text_pos = "inline",
        priority = 200,
      },
      hit = {
        virt_text = { { symbols.hit, highlight_groups.hit } },
        virt_text_pos = "inline",
        priority = 200,
      },
      disabled = {
        virt_text = { { symbols.disabled, highlight_groups.disabled } },
        virt_text_pos = "inline",
        priority = 200,
      },
    }

    -- TODO: FIX BREAKPOINT ISSUES (BAD LIFECYCLE MANAGEMENT, BREAKPOINT CORRELATION ISSUES)

    breakpoint_manager.onBreakpoint(function(breakpoint)
    log:debug('--------------------- BreakpointVirtualText: onBreakpoint',
      breakpoint.location.path, breakpoint.location.line, breakpoint.location.column)
      local set_idle = function() end

      breakpoint:onBound(function(binding)  
      -- local bindingLocation = binding:location()

        -- local exact = bindingLocation:matches(breakpoint.location)
        -- set_idle = function()
        --   -- if exact then
        --   -- else
        --   --   breakpoint.location:mark(ns, marks.disabled)
        --   --   bindingLocation:mark(ns, marks.adjusted)
        --   -- end
        -- end
        log:debug('--------------------- BreakpointVirtualText: onBound',
          breakpoint.location.path, breakpoint.location.line, breakpoint.location.column)
        breakpoint.location:mark(ns, marks.bound)


        -- set_idle()

        -- binding:onUnbound(function()
        --   bindingLocation:unmark(ns)
        --   set_idle = function() end
        -- end, { once = true })

        -- binding:onHit(function(hit)
        --   -- hit.thread:onResumed(set_idle, { once = true })
        --   -- bindingLocation:mark(ns, marks.hit)
        -- end)
      end)

      breakpoint:onRemoved(function()
        -- set_idle = function() end
        logger.get():debug('--------------------- BreakpointVirtualText: onRemoved',
          breakpoint.location.path, breakpoint.location.line, breakpoint.location.column)
        breakpoint.location:unmark(ns)
      end, { once = true })

      -- vim.api.nvim_create_autocmd({ "BufRead", "BufReadPost" }, {
      --   buffer = breakpoint.location:bufnr(),
      --   once = true,
      --   callback = set_idle
      -- })
      logger.get():debug('--------------------- BreakpointVirtualText: onBreakpoint',
        breakpoint.location.path, breakpoint.location.line, breakpoint.location.column)
      breakpoint.location:mark(ns, marks.normal)
    end)

    return {
      destroy = function()

      end,

      -- Expose some debugging info
      getNamespace = function() return ns end,
    }
  end
}
