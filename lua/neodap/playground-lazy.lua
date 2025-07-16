-- Enhanced playground using lazy.nvim minit for better development experience
-- This provides a modern plugin management system for the neodap playground

-- Set up isolated playground environment
vim.env.LAZY_STDPATH = ".playground"

-- Bootstrap lazy.nvim
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Set up leader key early
vim.g.mapleader = " "

-- Use lazy.nvim's minit functionality for playground
require("lazy.minit").repro({
  spec = {
    -- Core dependencies for neodap
    {
      "nvim-neotest/nvim-nio",
      lazy = false,
    },
    {
      "nvim-lua/plenary.nvim",
      lazy = false,
    },
    {
      "MunifTanjim/nui.nvim", 
      lazy = false,
    },
    {
      "nvim-telescope/telescope.nvim",
      lazy = false,
    },
    
    -- Additional development plugins for enhanced playground experience
    {
      "folke/trouble.nvim",
      lazy = true,
      cmd = "Trouble",
      keys = {
        { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
        { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics (Trouble)" },
      },
    },
    
    {
      "nvim-treesitter/nvim-treesitter",
      lazy = false,
      config = function()
        require("nvim-treesitter.configs").setup({
          ensure_installed = { "lua", "javascript", "typescript" },
          highlight = { enable = true },
          indent = { enable = true },
        })
      end,
    },
    
    -- Add neodap itself as a plugin from current directory
    {
      dir = ".",
      name = "neodap",
      lazy = false,
    },
  },
  
  -- Enhanced configuration for playground
  performance = {
    cache = {
      enabled = true,
    },
    reset_packpath = false,
  },
  
  -- Better UI for development
  ui = {
    border = "rounded",
    backdrop = 60,
  },
  
  -- Development-friendly settings
  dev = {
    path = ".",
    patterns = { "neodap" },
    fallback = false,
  },
})

-- Enhanced playground setup
local Manager = require("neodap.session.manager")
local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")
local Session = require("neodap.session.session")
local nio = require("nio")
local Api = require("neodap.api.Api")

local function setup_playground()
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

    -- Load all neodap plugins
    local JumpToStoppedFrame = require("neodap.plugins.JumpToStoppedFrame")
    local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
    local BreakpointApi = require("neodap.plugins.BreakpointApi")
    local FrameVariables = require("neodap.plugins.FrameVariables")
    local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
    local StackNavigation = require("neodap.plugins.StackNavigation")
    local FrameHighlight = require("neodap.plugins.FrameHighlight")
    local CallStackViewer = require("neodap.plugins.CallStackViewer")
    local ScopeViewer = require("neodap.plugins.ScopeViewer")
    local DebugMode = require("neodap.plugins.DebugMode")

    -- Initialize all plugins
    api:getPluginInstance(JumpToStoppedFrame)
    api:getPluginInstance(BreakpointVirtualText)
    api:getPluginInstance(BreakpointApi)
    api:getPluginInstance(FrameVariables)
    local stack = api:getPluginInstance(StackNavigation)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(FrameHighlight)
    api:getPluginInstance(DebugMode)
    api:getPluginInstance(CallStackViewer)
    api:getPluginInstance(ScopeViewer)

    local currentStopped = nil

    -- Enhanced session management
    api:onSession(function(session)
        session:onOutput(function(body)
            -- Enhanced output handling with lazy.nvim
            if body.output and body.output:len() > 0 then
                print("Session " .. session.ref.id .. " output: " .. body.output)
            end
        end)

        session:onThread(function(thread, body)
            vim.t = thread
            thread:onStopped(function(body)
                currentStopped = thread
                print("Thread " .. thread.ref.id .. " stopped")
            end)

            thread:onResumed(function()
                currentStopped = nil
                print("Thread " .. thread.ref.id .. " resumed")
            end)
        end)
    end)

    -- Enhanced keybindings with better descriptions
    vim.keymap.set("n", "<leader>db", function()
        toggleBreakpoint:Toggle()
    end, { noremap = true, silent = true, desc = "Toggle Breakpoint" })

    vim.keymap.set("n", "<leader>dc", function()
        if currentStopped then
            currentStopped:continue()
        else
            print("No stopped thread to continue")
        end
    end, { noremap = true, silent = true, desc = "Continue All Threads" })

    vim.keymap.set("n", "<leader>ds", function()
        if currentStopped then
            currentStopped:stepIn()
        else
            print("No stopped thread to step into")
        end
    end, { noremap = true, silent = true, desc = "Step Into" })

    vim.keymap.set("n", "<leader>do", function()
        if currentStopped then
            currentStopped:stepOver()
        else
            print("No stopped thread to step over")
        end
    end, { noremap = true, silent = true, desc = "Step Over" })

    vim.keymap.set("n", "<leader>du", function()
        stack:Up()
    end, { noremap = true, silent = true, desc = "Navigate Up Stack" })

    vim.keymap.set("n", "<leader>dd", function()
        stack:Down()
    end, { noremap = true, silent = true, desc = "Navigate Down Stack" })

    -- Enhanced logging commands
    vim.keymap.set("n", "<leader>dl", function()
        local Logger = require('neodap.tools.logger')
        local logger = Logger.get("playground")
        logger:info("Log file:", logger:getFilePath())
        vim.api.nvim_echo({ { "Log file: " .. logger:getFilePath(), "Normal" } }, false, {})
    end, { noremap = true, silent = true, desc = "Show Debug Log Path" })

    vim.keymap.set("n", "<leader>dv", function()
        vim.cmd("NeodapVariablesFloat")
    end, { noremap = true, silent = true, desc = "Show Frame Variables" })

    -- Enhanced lazy.nvim integration commands
    vim.keymap.set("n", "<leader>lz", function()
        vim.cmd("Lazy")
    end, { noremap = true, silent = true, desc = "Open Lazy UI" })

    vim.keymap.set("n", "<leader>lp", function()
        vim.cmd("Lazy profile")
    end, { noremap = true, silent = true, desc = "Lazy Profile" })

    -- Auto-set breakpoint on recurse.js
    api:onSession(function(session)
        session:onSourceLoaded(function(source)
            if source:isFile() and source:filename() == "recurse.js" then
                local Location = require('neodap.api.Location')
                local location = Location.fromSource(source, { line = 3, column = 1 })
                toggleBreakpoint:toggle(location)
                print("Auto-set breakpoint on recurse.js:3")
            end
        end)
    end)

    -- Create and start session
    local session = Session.create({
        manager = manager,
        adapter = adapter,
    })

    -- Enhanced session startup
    nio.run(function()
        print("Starting neodap playground session...")
        session:start({
            configuration = {
                type = "pwa-node",
                program = vim.fn.getcwd() .. "/spec/fixtures/recurse.js",
                cwd = vim.fn.getcwd(),
            },
            request = "launch",
        })

        nio.sleep(1000)
        print("Neodap playground ready! Use <leader>d* for debug commands, <leader>lz for Lazy UI")
    end)
end

-- Welcome message
print("🚀 Neodap Playground with lazy.nvim")
print("   Enhanced with modern plugin management!")
print("   Commands: <leader>d* for debug, <leader>lz for Lazy UI")

-- Initialize the playground
setup_playground()