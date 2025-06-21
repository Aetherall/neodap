local name = "BreakpointGutter"
return {
  name = name,
  description = "Plugin to display breakpoints in the gutter",
  ---@param api Api
  plugin = function(api)
    local nio = require("nio")

    ---@class api.FileSourceBreakpoint
    local FileSourceBreakpoint = require("neodap.api.Breakpoint.FileSourceBreakpoint")


    local signs = {
      DapBreakpoint = { text = "B", texthl = "SignColumn", linehl = "", numhl = "" },
      DapBreakpointCondition = { text = "C", texthl = "SignColumn", linehl = "", numhl = "" },
      DapBreakpointRejected = { text = 'R', texthl = "SignColumn", linehl = '', numhl = '' },
      DapLogPoint = { text = 'L', texthl = "SignColumn", linehl = '', numhl = '' },
      DapStopped = { text = '→', texthl = "SignColumn", linehl = 'debugPC', numhl = '' },
    }

    local function sign_try_define(name)
      local s = vim.fn.sign_getdefined(name)
      if vim.tbl_isempty(s) then
        local opts = signs[name]
        vim.fn.sign_define(name, opts)
      end
    end

    for name in pairs(signs) do
      sign_try_define(name)
    end


    function FileSourceBreakpoint:bufnr()
      local path = self.location.path
      local future = nio.control.future()
      vim.schedule(function()
        local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(path))
        if bufnr == -1 then
          future.set(nil)
        else
          future.set(bufnr)
        end
      end)
      return future
    end

    api:onBreakpoint(function(breakpoint)
      local id = math.random(1000000, 2000000)
      local bufnr = nil;


      breakpoint:onBound(function(binding)
        bufnr = breakpoint:bufnr().wait()
        vim.schedule(function()
          vim.fn.sign_place(id, "dap_breakpoints", "DapBreakpoint", bufnr,
            { lnum = breakpoint.location.line, priority = 21 })
        end)
      end)

      breakpoint:onHit(function(hit)
        if not bufnr then
          bufnr = breakpoint:bufnr().wait()
        end

        vim.schedule(function()
          vim.fn.sign_place(id, "dap_breakpoints", "DapStopped", bufnr,
            { lnum = breakpoint.location.line, priority = 21 })
        end)
      end)

      breakpoint.manager:onBreakpointRemoved(function(breakpoint)
        vim.schedule(function()
          if not bufnr then
            bufnr = breakpoint:bufnr().wait()
          end

          vim.fn.sign_unplace("dap_breakpoints", { id = id, buffer = bufnr })
        end)
      end)
    end)
  end
}
