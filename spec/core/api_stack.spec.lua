local prepare = require("spec.helpers.prepare")
local nio = require("nio")

describe("neodap public API", function()
  local JumpToStoppedFrame = require("neodap.plugins.JumpToStoppedFrame")

  it('can access variables via public API', function()
    local api, start = prepare()

    local variablesAccessed = nio.control.future()

    api:onSession(function(session)
      if session.ref.id == 1 then return end

      session:onInitialized(function()
        session.ref.calls:setBreakpoints({
          source = {
            path = vim.fn.fnamemodify("spec/fixtures/simple-debug.js", ":p")
          },
          breakpoints = {
            { line = 6 } -- console.log("Breakpoint here") line (actual line 6)
          }
        }):wait()
      end, { once = true })

      session:onThread(function(thread)
        thread:onPaused(function(body)
          if body.reason == "breakpoint" then
            -- Use public API to access variables
            local stack = thread:stack()
            local frames = stack:frames()
            local topFrame = frames[1]

            assert.is_not_nil(topFrame, "Top frame should exist")

            assert.is_equal(topFrame.ref.name, 'global.testFunction', "Top frame should be 'global.testFunction'")
            assert.is_equal(topFrame.ref.line, 6, "Top frame should be at line 6")

            -- Get scopes using public API
            local scopes = topFrame:scopes()
            assert.is_not_nil(scopes, "Scopes should be accessible")

            local localScope = scopes[1] -- Usually the first scope is locals
            assert.is_not_nil(localScope, "Should have at least one scope")

            -- Get variables from the local scope using public API
            local variables = localScope:variables()
            assert.is_not_nil(variables, "Variables should be accessible")

            local variable1 = variables[1]
            assert.is_equal(variable1.ref.name, 'localVar', "First variable should be 'localVar'")
            assert.is_equal(variable1.ref.value, "'test value'", "First variable should have value 'test value'")

            local variable2 = variables[2]
            assert.is_equal(variable2.ref.name, 'numberVar', "Second variable should be 'numberVar'")
            assert.is_equal(variable2.ref.value, '42', "Second variable should have value 42")

            local variable3 = variables[3]
            assert.is_equal(variable3.ref.name, 'this', "Third variable should be 'this'")

            -- print('\n\n')
            -- print(vim.inspect(variable3.ref))
            -- print('\n\n')

            variablesAccessed.set(true)
          end
        end, { once = true })
      end)
    end)

    start("simple-debug.js")

    assert.is_true(vim.wait(15000, variablesAccessed.is_set), "Variables should be accessed via public API")
  end)

  it('works with a plugin', function()
    local api, start = prepare()

    JumpToStoppedFrame.plugin(api)

    local stopped = nio.control.future()

    api:onSession(function(session)
      session:onThread(function(thread)
        thread:onPaused(function()
          nio.run(function()
            nio.sleep(200)
            local current_buffer = vim.api.nvim_get_current_buf()
            local file_name = vim.api.nvim_buf_get_name(current_buffer)
            if file_name:find("loop.js$") ~= nil then
              stopped.set(true)
            else
              error("Jump to stopped frame failed: " .. file_name)
            end
          end)
        end)

        thread:pause()
      end)
    end)

    start("loop.js")

    assert.is_true(vim.wait(15000, stopped.is_set), "Stopped frame should be jumped to via plugin")
  end)


  it('works with a plugin 2', function()
    local api, start = prepare()

    JumpToStoppedFrame.plugin(api)

    local stopped = nio.control.future()

    api:onSession(function(session)
      session:onThread(function(thread)
        thread:onPaused(function()
          nio.run(function()
            nio.sleep(200)
            local current_buffer = vim.api.nvim_get_current_buf()
            local file_name = vim.api.nvim_buf_get_name(current_buffer)
            if file_name:find("loop.js$") ~= nil then
              stopped.set(true)
            else
              error("Jump to stopped frame failed: " .. file_name)
            end
          end)
        end)

        thread:pause()
      end)
    end)

    start("loop.js")

    assert.is_true(vim.wait(15000, stopped.is_set), "Stopped frame should be jumped to via plugin")
  end)
end)
