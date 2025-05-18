#!/usr/bin/env -S nvim -u NONE -U NONE -N -i NONE -V1 --headless -l

-- Neovim Lua interpreter for busted tests
-- This file acts as both an executable script and a Lua interpreter

-- Prevent recursive loading
if _G._NVIM_BUSTED_LOADED then
  return
end
_G._NVIM_BUSTED_LOADED = true

-- Set up runtime paths for neodap and dependencies
-- Try to find nvim-nio from environment or common locations
local nvim_nio_path = os.getenv("NVIM_NIO_PATH")
if nvim_nio_path and vim.fn.isdirectory(nvim_nio_path) == 1 then
  vim.opt.rtp:prepend(nvim_nio_path)
else
  -- Fallback: try to detect if nvim-nio is available in runtime
  local ok = pcall(require, "nio")
  if not ok then
    -- If nio is not found, we'll continue without it for basic functionality
    print("Warning: nvim-nio not found, some features may not work")
  end
end

vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/lua")
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/lua/neodap")

-- Disable unnecessary features for testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.shortmess:append("c") -- Don't show completion messages
vim.opt.cmdheight = 1

-- Set up global environment
_G.vim = vim

-- Ensure package.path includes Lua paths
local lua_paths = {
  "lua/?.lua",
  "lua/?/init.lua",
  "./?.lua",
  "./?/init.lua"
}

for _, path in ipairs(lua_paths) do
  if not package.path:find(path, 1, true) then
    package.path = package.path .. ";" .. path
  end
end

-- Set up C extension paths for LuaJIT compatibility
local luajit_cpath = os.getenv("LUA_CPATH") or ""
if luajit_cpath ~= "" then
  package.cpath = luajit_cpath .. ";" .. package.cpath
end

-- Handle special cases when run directly
local args = vim.v.argv or {}
for i = 1, #args do
  local arg = args[i]
  if arg == "--version" or arg == "-V" then
    local version_output = vim.fn.execute("version")
    local nvim_version = version_output:match("NVIM v([%d%.%-dev%+%w]+)")
    print("nvim-busted-interpreter 1.0.0 (Neovim " .. (nvim_version or "unknown") .. ")")
    vim.cmd("quit")
    return
  elseif arg == "--help" or arg == "-h" then
    print("nvim-busted-interpreter - Neovim Lua interpreter for busted")
    print("Usage: nvim-busted-interpreter [options] [script.lua]")
    vim.cmd("quit")
    return
  end
end

-- Debug: print that we've started
if os.getenv("BUSTED_DEBUG") then
  print("nvim-busted-interpreter: Environment setup complete")
  print("nvim-busted-interpreter: Ready to execute Lua code")
  print("nvim-busted-interpreter: Arguments received:")
  for i, arg in ipairs(args) do
    print("  arg[" .. i .. "]: " .. arg)
  end
end

-- Check if we're being run by busted vs directly
-- If busted is in the arguments, find and execute the busted script
local is_busted_run = false
local busted_script = nil
for i = 1, #args do
  local arg = args[i]
  if arg:match("busted") and vim.fn.filereadable(arg) == 1 and not arg:match("nvim%-busted%-interpreter") then
    is_busted_run = true
    busted_script = arg
    break
  end
end

if not is_busted_run then
  -- Check if a script file was provided as argument
  -- Look for .lua files that come after the -l flag and are not the interpreter itself
  local script_file = nil
  local found_l_flag = false
  for i = 1, #args do
    local arg = args[i]
    if arg == "-l" then
      found_l_flag = true
    elseif found_l_flag and arg:match("%.lua$") and vim.fn.filereadable(arg) == 1 then
      -- This is the first .lua file after -l, skip it (it's the interpreter)
      found_l_flag = false
    elseif arg:match("%.lua$") and vim.fn.filereadable(arg) == 1 then
      -- This should be our test file
      script_file = arg
      break
    end
  end

  if script_file then
    -- Execute the script file
    if os.getenv("BUSTED_DEBUG") then
      print("nvim-busted-interpreter: Executing script: " .. script_file)
    end
    local ok, err = pcall(dofile, script_file)
    if not ok then
      io.stderr:write("Error executing " .. script_file .. ": " .. tostring(err) .. "\n")
      vim.cmd("cquit 1") -- Exit with error code
    else
      vim.cmd("quit")    -- Exit successfully
    end
  end
end

-- If we reach here, either no script file or we're being run by busted
-- Execute busted script if detected
if is_busted_run and busted_script then
  if os.getenv("BUSTED_DEBUG") then
    print("nvim-busted-interpreter: Executing busted script: " .. busted_script)
  end
  local ok, err = pcall(dofile, busted_script)
  if not ok then
    io.stderr:write("Error executing busted: " .. tostring(err) .. "\n")
    vim.cmd("cquit 1") -- Exit with error code
  else
    vim.cmd("quit")    -- Exit successfully
  end
elseif is_busted_run then
  if os.getenv("BUSTED_DEBUG") then
    print("nvim-busted-interpreter: Busted run detected but no script found")
  end
  vim.cmd("quit")
else
  -- Stay alive for other interactions
  if os.getenv("BUSTED_DEBUG") then
    print("nvim-busted-interpreter: No script file found, staying alive")
  end
end
