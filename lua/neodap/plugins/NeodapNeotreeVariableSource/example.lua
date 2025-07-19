-- example.lua
-- Example of how to integrate NeodapNeotreeVariableSource with your Neovim setup

-- 1. Basic Integration Example
-- Add this to your neodap plugin setup:

local function setup_neodap_with_neotree_variables()
  -- Your neodap setup
  local api = require("neodap").setup({
    -- your neodap config
  })
  
  -- Add the Neo-tree variable source plugin
  api:getPluginInstance(require("neodap.plugins.NeodapNeotreeVariableSource"))
  
  return api
end

-- 2. Neo-tree Configuration Example
-- Add this to your Neo-tree setup:

local function setup_neotree_with_variables()
  require("neo-tree").setup({
    sources = { 
      "filesystem", 
      "buffers", 
      "git_status",
      "neodap-variable-tree"  -- Our debug variables source
    },
    
    -- Global window settings
    window = {
      position = "left",
      width = 40,
    },
    
    -- Source-specific configurations
    ["neodap-variable-tree"] = {
      window = {
        position = "float",  -- Override global position for variables
        mappings = {
          ["<cr>"] = "toggle_node",
          ["<space>"] = "toggle_node", 
          ["o"] = "toggle_node",
          ["q"] = "close_window",
          -- Copy variable value to clipboard
          ["y"] = function(state)
            local node = state.tree:get_node()
            if node.extra and node.extra.value then
              vim.fn.setreg("+", node.extra.value)
              vim.notify("Copied: " .. node.extra.value)
            end
          end,
        },
      },
      popup = {
        size = {
          height = "70%",
          width = "60%", 
        },
        position = "50%",
      },
    },
    
    -- Keep your existing filesystem, buffers, git_status configs...
    filesystem = {
      -- your filesystem config
    },
  })
end

-- 3. Keymaps Example  
-- Add convenient keymaps for debugging workflow:

local function setup_debug_keymaps()
  local opts = { noremap = true, silent = true }
  
  -- Debug variables
  vim.keymap.set('n', '<leader>dv', ':Neotree float neodap-variable-tree<CR>', 
    vim.tbl_extend('force', opts, { desc = "Show debug variables (floating)" }))
  
  vim.keymap.set('n', '<leader>dV', ':Neotree right neodap-variable-tree<CR>', 
    vim.tbl_extend('force', opts, { desc = "Show debug variables (sidebar)" }))
    
  vim.keymap.set('n', '<leader>dc', ':Neotree close neodap-variable-tree<CR>', 
    vim.tbl_extend('force', opts, { desc = "Close debug variables" }))
    
  -- Toggle between different views
  vim.keymap.set('n', '<leader>dt', ':Neotree toggle neodap-variable-tree<CR>', 
    vim.tbl_extend('force', opts, { desc = "Toggle debug variables" }))
end

-- 4. Complete Workflow Example
-- How it all works together:

local function complete_debug_workflow_setup()
  -- 1. Setup neodap with variable source
  local neodap_api = setup_neodap_with_neotree_variables()
  
  -- 2. Setup Neo-tree with variable source  
  setup_neotree_with_variables()
  
  -- 3. Setup convenient keymaps
  setup_debug_keymaps()
  
  -- 4. Optional: Auto-open variables when debugging starts
  vim.api.nvim_create_autocmd("User", {
    pattern = "NeodapDebugStart", -- This would be a custom event you could fire
    callback = function()
      vim.cmd("Neotree float neodap-variable-tree")
    end
  })
  
  return neodap_api
end

-- 5. Advanced Integration with Other Debug Tools
-- Example of using variables source alongside other debug UIs:

local function advanced_debug_setup()
  setup_neodap_with_neotree_variables()
  
  require("neo-tree").setup({
    sources = { 
      "filesystem", 
      "buffers", 
      "git_status",
      "neodap-variable-tree"
    },
    
    -- Multi-panel debug layout
    ["neodap-variable-tree"] = {
      window = {
        position = "right",
        width = 50,
      },
    },
  })
  
  -- Keymaps for complete debug workflow
  local debug_maps = {
    -- Breakpoints
    ['<F9>'] = ':lua require("neodap.plugins.ToggleBreakpoint"):toggle()<CR>',
    
    -- Debug control  
    ['<F5>'] = ':lua require("neodap").continue()<CR>',
    ['<F10>'] = ':lua require("neodap").step_over()<CR>',
    ['<F11>'] = ':lua require("neodap").step_into()<CR>',
    
    -- Debug UI
    ['<leader>dv'] = ':Neotree show neodap-variable-tree<CR>',
    ['<leader>df'] = ':Neotree show filesystem<CR>',
    ['<leader>db'] = ':Neotree show buffers<CR>',
  }
  
  for key, cmd in pairs(debug_maps) do
    vim.keymap.set('n', key, cmd, { noremap = true, silent = true })
  end
end

return {
  setup_neodap_with_neotree_variables = setup_neodap_with_neotree_variables,
  setup_neotree_with_variables = setup_neotree_with_variables,
  setup_debug_keymaps = setup_debug_keymaps, 
  complete_debug_workflow_setup = complete_debug_workflow_setup,
  advanced_debug_setup = advanced_debug_setup,
}