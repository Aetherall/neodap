-- Simple test to debug Variables plugin expansion
vim.cmd("edit lua/testing/fixtures/variables/complex.js")
vim.cmd("NeodapToggleBreakpoint")

-- Move to line with actual code
vim.cmd("normal! 5j")
vim.cmd("NeodapToggleBreakpoint")
vim.cmd("NeodapLaunchClosest Variables [variables]")

-- Wait for breakpoint
vim.wait(2000, function() return false end)

-- Open Variables window
vim.cmd("VariablesShow")
vim.wait(500, function() return false end)

-- Move to Variables window
vim.cmd("wincmd h")

-- Try to expand Local scope
vim.cmd("normal! 2G")  -- Move to Local scope
vim.cmd("execute \"normal o\"")  -- Expand

-- Wait and check
vim.wait(1000, function() return false end)

-- Print debug info
print("=== Variables Window Debug ===")
local bufnr = vim.api.nvim_get_current_buf()
local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
for i, line in ipairs(lines) do
  print(string.format("%2d: %s", i, line))
end