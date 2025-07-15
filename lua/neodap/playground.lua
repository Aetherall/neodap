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
      -- vim.notify("nvim-nio not found, some async features may not work", vim.log.levels.WARN)
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
local Api                  = require("neodap.api.Api")


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

  local namespace = vim.api.nvim_create_namespace("neodap")
  vim.api.nvim_set_hl(namespace, "Default", { fg = "#ffffff", bg = "#000000" })

  


  local api = Api.register(manager)

  local JumpToStoppedFrame = require("neodap.plugins.JumpToStoppedFrame")
  -- local HighlightCurrentFrame = require("neodap.plugins.HighlightCurrentFrame")
  local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
  local BreakpointApi = require("neodap.plugins.BreakpointApi")
  local FrameVariables = require("neodap.plugins.FrameVariables")
  local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
  local StackNavigation = require("neodap.plugins.StackNavigation")
  local FrameHighlight = require("neodap.plugins.FrameHighlight")

  api:getPluginInstance(JumpToStoppedFrame)
  -- api:getPluginInstance(HighlightCurrentFrame)
  api:getPluginInstance(BreakpointVirtualText)
  api:getPluginInstance(BreakpointApi)
  api:getPluginInstance(FrameVariables)
  local stack = api:getPluginInstance(StackNavigation)
  local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
  api:getPluginInstance(FrameHighlight)
  api:getPluginInstance(require("neodap.plugins.DebugMode"))


  -- DebugMode.plugin(api)

  local currentStopped = nil


  api:onSession(function(session)
    session:onOutput(function(body)
      -- print("Output from session " .. session.id .. ": " .. body.output)
    end)

    session:onThread(function(thread, body)
      vim.t = thread
      thread:onStopped(function(body)
        currentStopped = thread
      end)

      thread:onResumed(function()
        currentStopped = nil
      end)
    end)
  end)

  vim.keymap.set("n", "<leader>db", function()
    nio.run(function()
      toggleBreakpoint:toggle()
    end)
  end, { noremap = true, silent = true, desc = "Toggle Breakpoint" })

  vim.keymap.set("n", "<leader>dc", function()
    if currentStopped then
      currentStopped:continue()
    end
  end, { noremap = true, silent = true, desc = "Continue All Threads" })

  vim.keymap.set("n", "<leader>ds", function()
    if currentStopped then
      currentStopped:stepIn()
    end
  end, { noremap = true, silent = true, desc = "Step Into" })

  vim.keymap.set("n", "<leader>do", function()
    if currentStopped then
      currentStopped:stepOver()
    end
  end, { noremap = true, silent = true, desc = "Step Over" })


  vim.keymap.set("n", "<leader>du", function()
   stack:up()
  end, { noremap = true, silent = true, desc = "Step Out" })


  vim.keymap.set("n", "<leader>dd", function()
    stack:down()
  end, { noremap = true, silent = true, desc = "Jump to Stopped Frame" })

  -- Add command to show log file path
  vim.keymap.set("n", "<leader>dl", function()
    local get_log_path = require('neodap.tools.get_log_path')
    local log_path = get_log_path()
    -- Write to cmdline instead of notify to avoid prompt
    vim.api.nvim_echo({{"Log file: " .. log_path, "Normal"}}, false, {})
  end, { noremap = true, silent = true, desc = "Show Debug Log Path" })

  -- Add keybinding for frame variables
  vim.keymap.set("n", "<leader>dv", function()
    vim.cmd("NeodapVariablesFloat")
  end, { noremap = true, silent = true, desc = "Show Frame Variables" })

  api:onSession(function(session)
    session:onSourceLoaded(function(source)
      -- Only process file sources
      if source:isFile() then
        if source:filename() == "recurse.js" then
          -- Use ToggleBreakpoint plugin to add breakpoint
          local Location = require('neodap.api.Location')
          local location = Location.fromSource(source, { line = 3, column = 1 })
          toggleBreakpoint:toggle(location)
        end
      end
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
        program = vim.fn.getcwd() .. "/spec/fixtures/recurse.js",
        cwd = vim.fn.getcwd(),
      },
      request = "launch",
    })

    nio.sleep(1000)
  end)
end


go()
