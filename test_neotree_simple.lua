-- Simple test to debug Neo-tree integration
print("=== Testing Neo-tree integration ===")

-- 1. Load Neo-tree
local ok, neotree = pcall(require, "neo-tree")
if not ok then
  print("ERROR: Could not load neo-tree")
  return
end
print("✓ Neo-tree loaded")

-- 2. Load our source
local ok, source = pcall(require, "neodap.plugins.SimpleVariableTree4")
if not ok then
  print("ERROR: Could not load our source")
  return
end
print("✓ Our source loaded")

-- 3. Check source structure
print("Source name:", source.name)
print("Source display_name:", source.display_name)
print("Has get_items:", type(source.get_items))
print("Has navigate:", type(source.navigate))

-- 4. Try to setup Neo-tree with our source
local setup_ok, setup_err = pcall(function()
  neotree.setup({
    sources = {
      "filesystem",
      "neodap.plugins.SimpleVariableTree4",
    },
  })
end)

if not setup_ok then
  print("ERROR: Neo-tree setup failed:", setup_err)
  return
end
print("✓ Neo-tree setup successful")

-- 5. Simulate having a current frame (mock)
source.current_frame = {
  scopes = function()
    return {
      { ref = { name = "Local", variablesReference = 123 } },
      { ref = { name = "Global", variablesReference = 456 } }
    }
  end
}
print("✓ Mock frame set")

-- 6. Try to open our source
print("Attempting to open Neo-tree with our source...")
vim.cmd("Neotree left neodap_variables")

-- 7. Wait and check if window opened
vim.wait(1000)
print("Windows after open:", #vim.api.nvim_list_wins())
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  print("Window", win, "filetype:", ft)
end