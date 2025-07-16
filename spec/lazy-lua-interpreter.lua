#!/usr/bin/env -S nvim -l

-- Non-interactive lazy.nvim interpreter for piped lua code execution
-- This sets up lazy.nvim environment and then executes piped Lua code

-- Prevent recursive loading
if _G._LAZY_LUA_INTERPRETER_LOADED then
  return
end
_G._LAZY_LUA_INTERPRETER_LOADED = true

-- Set up isolated environment
vim.env.LAZY_STDPATH = ".lazy-interpreter"

-- Bootstrap lazy.nvim
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Disable unnecessary features for headless operation
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.shortmess:append("c")
vim.opt.cmdheight = 1

-- Suppress lazy.nvim output unless debugging
local original_notify = vim.notify
local original_print = print
local silent_mode = not os.getenv("LAZY_DEBUG")

if silent_mode then
  -- Redirect vim.notify to suppress lazy.nvim messages
  vim.notify = function(msg, level, opts)
    -- Only show errors unless in debug mode
    if level == vim.log.levels.ERROR then
      original_notify(msg, level, opts)
    end
  end
  
  -- Suppress print statements from lazy.nvim
  print = function(...)
    -- Suppress all print output during lazy.nvim setup
  end
end

-- Set up project paths for neodap
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.opt.rtp:prepend(cwd .. "/lua")

-- Debug output if enabled
if os.getenv("LAZY_DEBUG") then
  print("lazy-lua-interpreter: Starting lazy.nvim setup")
  print("lazy-lua-interpreter: Working directory:", cwd)
  print("lazy-lua-interpreter: LAZY_STDPATH:", vim.env.LAZY_STDPATH)
end

-- Use lazy.nvim's minit functionality for simpler setup
-- This is more reliable than manual setup for headless use
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
    
    -- Optional development plugins
    {
      "folke/trouble.nvim",
      lazy = true,
    },
    
    {
      "nvim-treesitter/nvim-treesitter",
      lazy = true,
    },
    
    -- Add neodap itself as a plugin from current directory
    {
      dir = ".",
      name = "neodap",
      lazy = false,
    },
  },
  
  -- Configuration for non-interactive use
  install = {
    missing = true,
  },
  
  performance = {
    cache = {
      enabled = true,
    },
    reset_packpath = false,
  },
  
  -- Minimal UI for headless operation
  ui = {
    border = "none",
    backdrop = 100,
  },
  
  -- Control headless output
  headless = {
    process = false,
    log = os.getenv("LAZY_DEBUG") and true or false,
    task = os.getenv("LAZY_DEBUG") and true or false,
    colors = os.getenv("LAZY_DEBUG") and true or false,
  },
})

-- Debug output after setup
if os.getenv("LAZY_DEBUG") then
  print("lazy-lua-interpreter: lazy.nvim setup complete")
  print("lazy-lua-interpreter: Ready to execute piped Lua code")
end

-- Function to execute piped lua code
local function execute_piped_code()
  -- Read all input from stdin
  local input_lines = {}
  
  -- Try to read from stdin (works better with piped input)
  local ok, stdin_input = pcall(io.read, "*a")
  if ok and stdin_input and stdin_input:len() > 0 then
    -- Clean up the input - remove trailing whitespace but preserve the code structure
    stdin_input = stdin_input:gsub("%s*$", "")
    
    -- Don't split by lines, keep the input as a single block of code
    if stdin_input:len() > 0 then
      table.insert(input_lines, stdin_input)
    end
  end
  
  -- Also check command line arguments for code
  local args = vim.v.argv or {}
  for i = 1, #args do
    local arg = args[i]
    if arg:match("^%-%-exec=") then
      -- Extract code from --exec=<code> argument
      local code = arg:match("^%-%-exec=(.+)")
      if code then
        table.insert(input_lines, code)
      end
    end
  end
  
  -- Join all input lines into a single string
  local lua_code = table.concat(input_lines, "\n")
  
  if lua_code and lua_code:len() > 0 then
    if os.getenv("LAZY_DEBUG") then
      print("lazy-lua-interpreter: Executing Lua code:")
      print("--- BEGIN CODE ---")
      print(lua_code)
      print("--- END CODE ---")
    end
    
    -- Execute the lua code with better error handling
    local success, result = pcall(function()
      -- Use load() instead of loadstring() for better Lua 5.1+ compatibility
      local func, err = load(lua_code, "piped_code", "t")
      if not func then
        error("Syntax error: " .. tostring(err))
      end
      return func()
    end)
    
    if success then
      if os.getenv("LAZY_DEBUG") then
        print("lazy-lua-interpreter: Code executed successfully")
      end
      if result ~= nil then
        print(vim.inspect(result))
      end
    else
      print("Error executing Lua code:", result)
      vim.cmd("cquit 1")
    end
  else
    if os.getenv("LAZY_DEBUG") then
      print("lazy-lua-interpreter: No code to execute")
    end
  end
end

-- Use vim.schedule to ensure lazy.nvim has finished setup before executing code
vim.schedule(function()
  -- Restore original functions after lazy.nvim setup
  if silent_mode then
    vim.notify = original_notify
    print = original_print
  end
  
  execute_piped_code()
  -- Exit successfully
  vim.cmd("quit")
end)