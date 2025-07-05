local Test = require("spec.helpers.testing")(describe, it)
local Neodap = require("neodap")
local nio = require("nio")
local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")
local PrepareHelper = require("spec.helpers.prepare")
local prepare = PrepareHelper.prepare

Test.Describe("BreakpointVirtualText plugin", function()
  Test.It("should register plugin", function()
    local manager, api = Neodap.setup()
    BreakpointVirtualText.plugin(api)
    -- Plugin should load without errors
  end)

  Test.It("should place virtual text at breakpoint location", function()
    local api, start = prepare()

    BreakpointVirtualText.plugin(api)

    start("loop.js")

    local spy = Test.spy("onBreakpoint")

    api:onBreakpoint(function(breakpoint)
      nio.run(function()
        nio.sleep(100)
        
        -- Use the same method as BreakpointVirtualText plugin
        local path = breakpoint.location.path
        local future = nio.control.future()
        -- vim.schedule(function()
          local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(path))
          if bufnr == -1 then
            future.set(nil)
          else
            future.set(bufnr)
          end
        -- end)
        local buffer = future.wait()

        if not buffer then
          error("Breakpoint buffer not found")
        end

        -- vim.schedule(function()
          -- Check for virtual text at the breakpoint location
          local namespace = vim.api.nvim_create_namespace("neodap_breakpoint_virtual_text")
          local extmarks = vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {details = true})
          
          if #extmarks > 0 then
            local extmark = extmarks[1]
            -- extmark[1] = id, extmark[2] = line, extmark[3] = col, extmark[4] = details
            if extmark[4] and extmark[4].virt_text and #extmark[4].virt_text > 0 then
              local virt_text = extmark[4].virt_text[1]
              if virt_text[1] == "●" or virt_text[1] == "◐" then -- Normal or adjusted breakpoint symbol
                spy.trigger()
              else
                error("Expected virtual text symbol '●' or '◐', got: " .. (virt_text[1] or "nil"))
              end
            else
              error("No virtual text found in extmark")
            end
          else
            error("No extmarks found in buffer")
          end
        -- end)
      end)
    end)

    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        local filesource = source:asFile()
        if not filesource then
          return
        end

        if filesource:filename() == "loop.js" then
          filesource:addBreakpoint({ line = 3 })
        end
      end)
    end)

    spy.wait()
  end)
end)