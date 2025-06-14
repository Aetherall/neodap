-- Try to find nvim-nio in environment or fallback gracefully
local function setup_runtime_paths()
  -- Check if nvim-nio is available from environment (e.g., Nix)
  local nvim_nio_path = os.getenv("NVIM_NIO_PATH")
  if nvim_nio_path and vim.fn.isdirectory(nvim_nio_path) == 1 then
    vim.opt.rtp:prepend(nvim_nio_path)
  else
    -- Try to require nio directly (it might already be in runtime path)
    local ok = pcall(require, "nio")
    if not ok then
      -- If nio is not found, we can still function for basic operations
      vim.notify("nvim-nio not found, some async features may not work", vim.log.levels.WARN)
    end
  end

  -- Set up project paths relative to current working directory
  local cwd = vim.fn.getcwd()
  vim.opt.rtp:prepend(cwd)
  vim.opt.rtp:prepend(cwd .. "/lua")
  vim.opt.rtp:prepend(cwd .. "/lua/neodap")
end

setup_runtime_paths()

vim.g.mapleader            = " "

local Manager              = require("neodap.session.manager")
local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")
local Session              = require("neodap.session.session")
local nio                  = require("nio")
local Api                  = require("neodap.api.SessionApi")
local DebugMode            = require("neodap.plugins.DebugMode")


local function go()
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

  DebugMode.plugin(api)


  api:onSession(function(session)
    -- session:onInitialized(function()
    --   print("\nSession initialized: " .. session.ref.id)
    -- end)

    -- session:onTerminated(function()
    --   print("\nSession terminated: " .. session.ref.id)
    -- end)

    -- session:onExited(function()
    --   print("\nSession exited: " .. session.ref.id)
    -- end)

    -- session:onOutput(function(body)
    --   if body.category == 'console' then return end
    --   print("\nSession Output: " .. body.output)
    -- end, { name = "log" })

    session:onThread(function(thread)
      -- thread:onStopped(function()
      --   print("\nThread stopped: " .. thread.id)

      --   local stack = thread:stack()

      --   local frames = stack:frames()

      --   print("\nStack trace for thread " .. thread.id .. ":")
      --   for _, frame in ipairs(frames) do
      --     print(string.format("\n  %d:%d - %s", frame.ref.line, frame.ref.column,
      --       frame.ref.name or "unknown"))
      --   end
      -- end)


      nio.run(function()
        nio.sleep(1000)
        thread:pause():wait()
      end)
    end)
  end)

  local session = Session.create({
    manager = manager,
    adapter = adapter,
  })


  ---@async
  nio.run(function()
    session:start({
      configuration = {
        type = "pwa-node",
        program = vim.fn.getcwd() .. "/index.js",
        cwd = vim.fn.getcwd(),
      },
      request = "launch",
    })

    nio.sleep(1000)
  end)
end


go()
