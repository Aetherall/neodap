-- Test manual expansion of a global variable to confirm 3+ level nesting
print("=== Testing Variable Expansion ===")

-- Load our plugin and set up Neo-tree
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

-- Simulate expansion state - expand Global scope AND a specific variable
SimpleVariableTree4.expanded_nodes = {
  ["scope_456"] = true,  -- Global scope (assuming variablesReference 456)
  ["scope_456/process"] = true,  -- Expand the process variable
}

-- Mock current frame with realistic data
SimpleVariableTree4.current_frame = {
  scopes = function()
    return {
      { ref = { name = "Local", variablesReference = 123 } },
      { ref = { name = "Global", variablesReference = 456 } }
    }
  end,
  variables = function(ref)
    if ref == 456 then -- Global scope
      return {
        { name = "process", value = "process {...}", variablesReference = 789, type = "object" },
        { name = "console", value = "console {...}", variablesReference = 800, type = "object" },
      }
    elseif ref == 789 then -- process object
      return {
        { name = "env", value = "{...}", variablesReference = 900, type = "object" },
        { name = "argv", value = "[...]", variablesReference = 901, type = "Array" },
        { name = "pid", value = "12345", variablesReference = 0, type = "number" },
      }
    elseif ref == 900 then -- process.env
      return {
        { name = "PATH", value = "/usr/bin:/bin", variablesReference = 0, type = "string" },
        { name = "HOME", value = "/home/user", variablesReference = 0, type = "string" },
      }
    end
    return {}
  end
}

-- Build cached tree
print("Building cached tree...")
SimpleVariableTree4.cached_tree = {
  {
    id = "scope_456",
    name = "Global",
    type = "scope",
    has_children = true,
    variables = {
      {
        id = "scope_456/process",
        name = "process: process {...}",
        type = "variable", 
        has_children = true,
        extra = { variable_reference = 789, level = 1 }
      },
      {
        id = "scope_456/console",
        name = "console: console {...}",
        type = "variable",
        has_children = true, 
        extra = { variable_reference = 800, level = 1 }
      }
    },
    extra = { variables_reference = 456, level = 0 }
  }
}

print("Cached tree built")

-- Set up Neo-tree 
require('neo-tree').setup({
  sources = {
    "filesystem",
    "neodap.plugins.SimpleVariableTree4",
  },
})

-- Open Neo-tree to see the expanded structure
print("Opening Neo-tree with expanded variables...")
vim.cmd("Neotree left neodap_variables")

-- Wait a moment for rendering
vim.wait(1000)

-- Check window content
print("Checking window content...")
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  if ft == "neo-tree" then
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    print("Neo-tree content:")
    for i, line in ipairs(lines) do
      if i <= 10 then -- Show first 10 lines
        print(i, line)
      end
    end
    break
  end
end