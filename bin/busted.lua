#!/usr/bin/env -S nvim -l

-- lazy.nvim minit-based test interpreter for neodap
-- Uses lazy.nvim's built-in testing functionality for automatic dependency management

-- Prevent recursive loading
if _G._LAZY_BUSTED_LOADED then
    return
end
_G._LAZY_BUSTED_LOADED = true

-- Set up isolated test environment
vim.env.LAZY_STDPATH = ".cache/tests"

-- Bootstrap lazy.nvim
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Disable unnecessary features for testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.shortmess:append("c") -- Don't show completion messages
vim.opt.cmdheight = 1

-- Set tabstop=1 to ensure buffer positions match screen positions in tests
-- This is critical for terminal snapshot tests where visual markers need to align
vim.opt.tabstop = 1
vim.opt.shiftwidth = 1
vim.opt.expandtab = false

-- Set up project paths for neodap
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.opt.rtp:prepend(cwd .. "/lua")

-- Debug output if enabled
if os.getenv("BUSTED_DEBUG") then
    print("lazy-busted-interpreter: Starting lazy.nvim minit with busted")
    print("lazy-busted-interpreter: Working directory:", cwd)
    print("lazy-busted-interpreter: LAZY_STDPATH:", vim.env.LAZY_STDPATH)
end

if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    package.loaded["lldebugger"] = assert(loadfile(os.getenv("LOCAL_LUA_DEBUGGER_FILEPATH")))()
    -- require("lldebugger").start()
    require("lldebugger").start()
end

-- Use lazy.nvim's minit functionality for busted testing
require("lazy.minit").busted({
    spec = {
        -- Core dependencies for neodap
        {
            "nvim-neotest/nvim-nio",
            lazy = false, -- Always load for testing
        },

        {
            "nvim-neo-tree/neo-tree.nvim",
            branch = "v3.x",
            dependencies = {
                "nvim-lua/plenary.nvim",
                "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
                "MunifTanjim/nui.nvim",
                -- Optional image support for file preview: See `# Preview Mode` for more information.
                -- {"3rd/image.nvim", opts = {}},
                -- OR use snacks.nvim's image module:
                -- "folke/snacks.nvim",
            },
            lazy = false, -- neo-tree will lazily load itself
            ---@module "neo-tree"
            ---@type neotree.Config?
            opts = {
                -- add options here
            },
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

        -- Add neodap itself as a plugin from current directory
        {
            dir = ".",
            name = "neodap",
            lazy = false,
            dev = true
        },

        -- Add busted as a plugin for testing
        {
            "olivine-labs/busted",
            lazy = false,
        },
    },

    -- Additional lazy.nvim configuration for testing
    install = {
        missing = true, -- Install missing plugins
    },

    -- Performance optimizations for testing
    performance = {
        cache = {
            enabled = true,
        },
        reset_packpath = false, -- Keep existing packpath
    },

    -- Minimal UI for testing
    ui = {
        border = "none",
        backdrop = 100,
    },

    headless = {
        process = false,
        log = os.getenv("LAZY_DEBUG") and true or false,
        task = os.getenv("LAZY_DEBUG") and true or false,
        colors = os.getenv("LAZY_DEBUG") and true or false,
    },
})

-- Debug output after setup
if os.getenv("BUSTED_DEBUG") then
    print("lazy-busted-interpreter: lazy.nvim minit setup complete")
    print("lazy-busted-interpreter: Ready to execute tests")
end
