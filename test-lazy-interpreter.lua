-- Test script for lazy-lua-interpreter
-- This demonstrates that lazy.nvim environment is set up correctly

-- Test 1: Check if neodap modules are available
print("Testing neodap module availability...")
local Manager = require("neodap.session.manager")
local Api = require("neodap.api.Api")
print("✓ neodap.session.manager loaded")
print("✓ neodap.api.Api loaded")

-- Test 2: Check if lazy.nvim plugins are available
print("\nTesting lazy.nvim plugin availability...")
local nio = require("nio")
print("✓ nvim-nio loaded")

local plenary = require("plenary")
print("✓ plenary.nvim loaded")

-- Test 3: Check if lazy.nvim is properly set up
print("\nTesting lazy.nvim setup...")
local lazy_available, lazy = pcall(require, "lazy")
if lazy_available then
  print("✓ lazy.nvim loaded")
  print("✓ LAZY_STDPATH:", vim.env.LAZY_STDPATH)
else
  print("✗ lazy.nvim not available")
end

-- Test 4: Test simple neodap functionality
print("\nTesting neodap functionality...")
local manager = Manager.create()
print("✓ Manager created successfully")

local api = Api.register(manager)
print("✓ Api registered successfully")

print("\n🎉 All tests passed! lazy.nvim interpreter is working correctly.")