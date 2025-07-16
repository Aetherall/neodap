-- Simple test for lazy.nvim interpreter
print("Testing lazy.nvim interpreter...")

-- Test basic Lua functionality
local x = 5
local y = 10
print("Math test:", x + y)

-- Test if we can access vim
print("Vim version:", vim.version())

-- Test simple module loading
local success, result = pcall(require, "nio")
if success then
  print("✓ nvim-nio loaded successfully")
else
  print("✗ nvim-nio failed to load:", result)
end

print("✓ Basic tests completed successfully!")