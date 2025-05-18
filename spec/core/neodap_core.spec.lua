-- Tests for neodap functionality
-- This file tests the actual neodap modules and functionality

describe("neodap", function()
  local Manager              = require("neodap.session.manager")
  local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")
  local Session              = require("neodap.session.session")
  local nio                  = require("nio")
  local Api                  = require("neodap.api.Api")
  local JumpToStoppedFrame   = require("neodap.plugins.JumpToStoppedFrame")


  local function prepare()
    local manager = Manager.create()
    local adapter = ExecutableTCPAdapter.create({
      executable = {
        cmd = "js-debug",
        cwd = vim.fn.getcwd(),
      },
      connection = {
        host = "::1",
      },
    })

    local api = Api.register(manager)


    local function start(fixture)
      local session = Session.create({
        manager = manager,
        adapter = adapter,
      })

      ---@async
      nio.run(function()
        session:start({
          configuration = {
            type = "pwa-node",
            program = vim.fn.fnamemodify("spec/fixtures/" .. fixture, ":p"),
            cwd = vim.fn.getcwd(),
          },
          request = "launch",
        })
      end)

      return session
    end

    return api, start
  end

  it("start and exits", function()
    local api, start = prepare()

    local initialized = nio.control.future()
    local terminated = nio.control.future()
    local exited = nio.control.future()

    api:onSession(function(session)
      if session.ref.id == 1 then return end

      session:onInitialized(initialized.set, { once = true })
      session:onTerminated(terminated.set, { once = true })
      session:onExited(exited.set, { once = true })
    end)

    start("hello-world.js")

    assert.is_true(vim.wait(10000, initialized.is_set), "Session should be initialized")
    assert.is_true(vim.wait(10000, terminated.is_set), "Session should be terminated")
    assert.is_true(vim.wait(10000, exited.is_set), "Session should be exited")
  end)

  it('pauses execution', function()
    local api, start = prepare()

    local paused = nio.control.future()

    api:onSession(function(session)
      session:onThread(function(thread)
        thread:onStopped(paused.set, { once = true })
        thread:pause()
      end)
    end)

    start("hello-world.js")

    assert.is_true(vim.wait(10000, paused.is_set), "Session should be paused")
  end)
end)
