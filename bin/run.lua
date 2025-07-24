#!/usr/bin/env -S nvim -l

-- print("hello")
local argv = vim.v.argv or {}

local lastarg = argv[#argv] or ""

-- print("Last argument:", lastarg)



-- Non-interactive lazy.nvim interpreter for piped lua code execution
-- This sets up lazy.nvim environment and then executes piped Lua code

-- Prevent recursive loading
if _G._LAZY_LUA_INTERPRETER_LOADED then
  return
end
_G._LAZY_LUA_INTERPRETER_LOADED = true

-- Set up isolated environment
vim.env.LAZY_STDPATH = ".cache/interpreter"

-- -- Bootstrap lazy.nvim
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Disable unnecessary features for headless operation
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.shortmess:append("c")
vim.opt.cmdheight = 1

-- Set tabstop=1 to ensure buffer positions match screen positions
-- This is critical for terminal snapshot tests where visual markers need to align
vim.opt.tabstop = 1
vim.opt.shiftwidth = 1
vim.opt.expandtab = false

_G.it = function(name, fn) fn() end
_G.describe = function(name, fn) fn() end

-- -- Suppress lazy.nvim output unless debugging
-- local original_notify = vim.notify
-- local original_print = print
-- local silent_mode = not os.getenv("LAZY_DEBUG")

-- if silent_mode then
--   -- Redirect vim.notify to suppress lazy.nvim messages
--   vim.notify = function(msg, level, opts)
--     -- Only show errors unless in debug mode
--     if level == vim.log.levels.ERROR then
--       original_notify(msg, level, opts)
--     end
--   end

--   -- Suppress print statements from lazy.nvim
--   print = function(...)
--     -- Suppress all print output during lazy.nvim setup
--   end
-- end

-- Set up project paths for neodap
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.opt.rtp:prepend(cwd .. "/lua")

-- Debug output if enabled
-- if os.getenv("LAZY_DEBUG") then
--   print("lazy-lua-interpreter: Starting lazy.nvim setup")
--   print("lazy-lua-interpreter: Working directory:", cwd)
--   print("lazy-lua-interpreter: LAZY_STDPATH:", vim.env.LAZY_STDPATH)
-- end

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
    {
      "olivine-labs/busted",
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
    log = true,
    task = false,
    colors = false,
  },
})

-- -- -- Debug output after setup
-- -- if os.getenv("LAZY_DEBUG") then
-- --   print("lazy-lua-interpreter: lazy.nvim setup complete")
-- --   print("lazy-lua-interpreter: Ready to execute piped Lua code")
-- -- end

-- -- -- Function to get lua code from various sources
-- -- local function get_lua_code()
-- --   local input_lines = {}

-- --   -- Check command line arguments first
-- --   local args = vim.v.argv or {}

-- --   if os.getenv("LAZY_DEBUG") then
-- --     print("lazy-lua-interpreter: Processing args:", vim.inspect(args))
-- --   end

-- --   -- Look for arguments that come after the script name
-- --   local script_found = false
-- --   for i = 1, #args do
-- --     local arg = args[i]

-- --     -- Skip until we find our interpreter script
-- --     if arg:match("interpreter%.lua$") then
-- --       script_found = true
-- --     elseif script_found and not arg:match("^-") then
-- --       -- This is our argument after the script name
-- --       if vim.fn.filereadable(arg) == 1 then
-- --         -- It's a file, read it
-- --         local file_content = vim.fn.readfile(arg)
-- --         if file_content then
-- --           table.insert(input_lines, table.concat(file_content, "\n"))
-- --           if os.getenv("LAZY_DEBUG") then
-- --             print("lazy-lua-interpreter: Reading code from file:", arg)
-- --           end
-- --         end
-- --       else
-- --         -- Treat as lua code string
-- --         if arg:len() > 0 then
-- --           table.insert(input_lines, arg)
-- --           if os.getenv("LAZY_DEBUG") then
-- --             print("lazy-lua-interpreter: Using code from argument:", arg)
-- --           end
-- --         end
-- --       end
-- --       -- Only process the first non-flag argument after script name
-- --       break
-- --     end
-- --   end

-- --   -- If no arguments, try to read from stdin
-- --   if #input_lines == 0 then
-- --     local ok, stdin_input = pcall(io.read, "*a")
-- --     if ok and stdin_input and stdin_input:len() > 0 then
-- --       -- Clean up the input - remove trailing whitespace but preserve the code structure
-- --       stdin_input = stdin_input:gsub("%s*$", "")

-- --       -- Don't split by lines, keep the input as a single block of code
-- --       if stdin_input:len() > 0 then
-- --         table.insert(input_lines, stdin_input)
-- --         if os.getenv("LAZY_DEBUG") then
-- --           print("lazy-lua-interpreter: Reading code from stdin")
-- --         end
-- --       end
-- --     end
-- --   end

-- --   -- Join all input lines into a single string
-- --   return table.concat(input_lines, "\n")
-- -- end

-- -- -- Function to execute lua code
-- -- local function execute_code()
-- --   local lua_code = get_lua_code()

-- --   if lua_code and lua_code:len() > 0 then
-- --     if os.getenv("LAZY_DEBUG") then
-- --       print("lazy-lua-interpreter: Executing Lua code:")
-- --       print("--- BEGIN CODE ---")
-- --       print(lua_code)
-- --       print("--- END CODE ---")
-- --     end

-- --     -- Execute the lua code with better error handling
-- --     local success, result = pcall(function()
-- --       -- Use load() instead of loadstring() for better Lua 5.1+ compatibility
-- --       local func, err = load(lua_code, "user_code", "t")
-- --       if not func then
-- --         error("Syntax error: " .. tostring(err))
-- --       end
-- --       return func()
-- --     end)

-- --     if success then
-- --       if os.getenv("LAZY_DEBUG") then
-- --         print("lazy-lua-interpreter: Code executed successfully")
-- --       end
-- --       if result ~= nil then
-- --         print(vim.inspect(result))
-- --       end
-- --     else
-- --       print("Error executing Lua code:", result)
-- --       -- vim.cmd("cquit 1")
-- --     end
-- --   else
-- --     if os.getenv("LAZY_DEBUG") then
-- --       print("lazy-lua-interpreter: No code to execute")
-- --     end
-- --   end
-- -- end

-- -- vim.schedule(function()
-- --   -- local NvimAsync = require("neodap.tools.async")
-- --   -- local nio = require("nio")

-- --   require("neodap.test_nested_async_returns")
-- --   -- NvimAsync.run(function()
-- --   --   -- -- Execute the code provided via stdin or command line arguments
-- --   --   -- execute_code()

-- --   --   -- Run the test suite if available
-- --   --   if vim.fn.filereadable("test_nested_async_returns.lua") == 1 then
-- --   --   else
-- --   --     print("No test file found, skipping tests")
-- --   --   end

-- --   --   -- Exit successfully
-- --   --   -- nio.sleep(2000) -- Give time for all async tasks to complete
-- --   --   vim.cmd("quit")
-- --   -- end)
-- --   -- require("neodap.test_nested_async_returns")
-- --   vim.wait(1000, function() return false end)
-- -- end)

-- -- -- execute_code()
-- -- -- -- Use vim.schedule to ensure lazy.nvim has finished setup before executing code
-- -- -- vim.schedule(function()
-- -- --   -- Restore original functions after lazy.nvim setup
-- -- --   if silent_mode then
-- -- --     vim.notify = original_notify
-- -- --     print = original_print
-- -- --   end

-- -- --   local NvimAsync = require("neodap.tools.async")
-- -- --   local nio = require("nio")

-- -- --   NvimAsync.run(function()
-- -- --     -- Exit successfully
-- -- --     -- nio.sleep(2000) -- Give time for all async tasks to complete
-- -- --     -- vim.cmd("quit")
-- -- --   end)
-- -- -- end)

-- we cannot require last arg directly because even if it is a file, the path may not be in the runtime path.
-- we must first set the runtime path to include the directory of the last argument
if lastarg:match("%.lua$") then
  local dir = vim.fn.fnamemodify(lastarg, ":p:h")
  if dir and dir ~= "" then
    vim.opt.rtp:prepend(dir)
    -- print("Prepending runtime path with directory of last argument:", dir)
  else
    -- print("No directory found for last argument, skipping runtime path prepend")
  end

  --- replace all / by .
  local modulename = lastarg:match("(.+)%..+$"):gsub("/", ".")

  -- Now we can require the last argument
  local ok, module = pcall(require, modulename)
  if ok then
    -- print("Successfully required module from last argument:", module)
  else
    print("Failed to require module from last argument:", module)
  end

  local NvimAsync = require("neodap.tools.async")

  -- vim.wait(100, function() return end)

  vim.wait(10000, function() return not NvimAsync.has_pending_tasks() end)
  -- print("All async tasks completed, exiting...")
end
