local Manager              = require("neodap.session.manager")
local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")
local Session              = require("neodap.session.session")
local nio                  = require("nio")
local Api                  = require("neodap.api.Api")

---@return Api, fun(fixture: string): Session
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


return prepare;
