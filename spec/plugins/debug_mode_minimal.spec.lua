-- Minimal DebugMode tests demonstrating reduced boilerplate

local SimpleHelper = require("spec.helpers.simple_helper")
local DebugMode = require("neodap.plugins.DebugMode")
local nio = require("nio")

describe("DebugMode plugin (minimal)", function()
  it('can enter and exit debug mode at breakpoint', function()
    local api, start = SimpleHelper.prepare({ DebugMode })

    local ready = SimpleHelper.session_with_breakpoints(
      api, "simple-debug.js", { 6 },
      function(thread, body, session)
        -- Enter debug mode
        SimpleHelper.enter_debug_mode()

        -- Verify cursor position
        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.equals(6, cursor[1], "Should be at breakpoint line")

        -- Exit debug mode
        SimpleHelper.exit_debug_mode()
      end
    )

    start("simple-debug.js")
    assert.is_true(vim.wait(15000, ready.is_set), "Debug mode should work")
  end)

  it('can step through code', function()
    local api, start = SimpleHelper.prepare({ DebugMode })
    local steps_completed = 0

    local ready = SimpleHelper.session_with_breakpoints(
      api, "simple-debug.js", { 6 },
      function(thread, body, session)
        SimpleHelper.enter_debug_mode()

        -- Initial position
        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.equals(6, cursor[1], "Should start at line 6")

        -- Step over
        SimpleHelper.step('over')
        steps_completed = steps_completed + 1
      end
    )

    -- Handle step completion
    api:onSession(function(session)
      if session.ref.id == 1 then return end

      session:onThread(function(thread)
        thread:onStopped(function(body)
          if body.reason == "step" and steps_completed > 0 then
            nio.run(function()
              nio.sleep(100)

              -- Verify we stepped to next line
              local cursor = vim.api.nvim_win_get_cursor(0)
              assert.is_true(cursor[1] > 6, "Should have stepped forward")

              SimpleHelper.exit_debug_mode()
              ready.set(true)
            end)
          end
        end)
      end)
    end)

    start("simple-debug.js")
    assert.is_true(vim.wait(20000, ready.is_set), "Stepping should work")
  end)

  it('can handle loop debugging', function()
    local api, start = SimpleHelper.prepare({ DebugMode })

    local ready = SimpleHelper.session_with_breakpoints(
      api, "loop.js", { 3 },
      function(thread, body, session)
        SimpleHelper.enter_debug_mode()
        SimpleHelper.exit_debug_mode()
      end
    )

    start("loop.js")
    assert.is_true(vim.wait(15000, ready.is_set), "Loop debugging should work")
  end)
end)
