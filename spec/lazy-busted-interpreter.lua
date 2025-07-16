#!/usr/bin/env -S nvim -l

-- lazy.nvim minit-based test interpreter for neodap
-- This replaces the custom nvim-busted-interpreter.lua with lazy.nvim's built-in testing functionality

-- Prevent recursive loading
if _G._LAZY_BUSTED_LOADED then
  return
end
_G._LAZY_BUSTED_LOADED = true

-- Set up isolated test environment
vim.env.LAZY_STDPATH = ".tests"

-- Bootstrap lazy.nvim
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Disable unnecessary features for testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.shortmess:append("c") -- Don't show completion messages
vim.opt.cmdheight = 1

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

-- Use lazy.nvim's minit functionality for busted testing
require("lazy.minit").busted({
  spec = {
    -- Core dependencies for neodap
    {
      "nvim-neotest/nvim-nio",
      lazy = false, -- Always load for testing
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
})

-- Debug output after setup
if os.getenv("BUSTED_DEBUG") then
  print("lazy-busted-interpreter: lazy.nvim minit setup complete")
  print("lazy-busted-interpreter: Ready to execute tests")
end