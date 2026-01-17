local neodap = require("neodap")

local M = {}

---@class neodap.BoostConfig : neodap.Config
---@field keys? boolean Set default keymaps (default: false)
---@field icons? table Icon configuration for plugins
---@field plugins? table<string, table> Configuration for individual plugins

local defaults = {
  keys = false,
  adapters = {},
  plugins = {},
  icons = {
    -- Tree buffer icons
    expanded = "▼",
    collapsed = "▶",
    -- Breakpoint signs
    breakpoint = "●",
    breakpoint_verified = "◉",
    breakpoint_hit = "◆",
    breakpoint_condition = "◐",
    breakpoint_log = "▤",
    -- Exceptions
    exception = "‼",
  },
}

---Setup neodap with "batteries included"
---@param opts? neodap.BoostConfig
---@return neodap.entities.Debugger
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", defaults, opts or {})

  -- 1. Core Setup
  local debugger = neodap.setup({ adapters = opts.adapters })
  local plugins_config = opts.plugins or {}

  ---Helper to use a plugin with merged config
  ---@param plugin function Plugin module
  ---@param name string Plugin name key in config
  ---@param default_cfg? table Default configuration from boost
  local function use(plugin, name, default_cfg)
    local user_cfg = plugins_config[name] or {}
    local final_cfg = vim.tbl_deep_extend("force", default_cfg or {}, user_cfg)
    debugger:use(plugin, final_cfg)
  end

  -- 2. Core Logic Plugins
  use(neodap.plugins.dap, "dap")
  use(neodap.plugins.command_router, "command_router")
  use(neodap.plugins.control_cmd, "control_cmd")
  use(neodap.plugins.step_cmd, "step_cmd")
  use(neodap.plugins.breakpoint_cmd, "breakpoint_cmd")
  use(neodap.plugins.exception_cmd, "exception_cmd")
  use(neodap.plugins.jump_stop, "jump_stop")
  use(neodap.plugins.cursor_focus, "cursor_focus")
  use(neodap.plugins.leaf_session, "leaf_session")
  use(neodap.plugins.stack_nav, "stack_nav")
  use(neodap.plugins.code_workspace, "code_workspace")
  use(neodap.plugins.hit_polyfill, "hit_polyfill")

  -- 3. Command Plugins
  use(neodap.plugins.list_cmd, "list_cmd")
  use(neodap.plugins.focus_cmd, "focus_cmd")
  use(neodap.plugins.bulk_cmd, "bulk_cmd")
  use(neodap.plugins.jump_cmd, "jump_cmd")
  use(neodap.plugins.run_to_cursor_cmd, "run_to_cursor_cmd")

  -- 4. UI Plugins
  -- Breakpoint Signs
  use(neodap.plugins.breakpoint_signs, "breakpoint_signs", {
    icons = {
      unbound = opts.icons.breakpoint,
      bound = opts.icons.breakpoint_verified,
      adjusted = opts.icons.breakpoint_condition,
      hit = opts.icons.breakpoint_hit,
      log = opts.icons.breakpoint_log,
    },
  })

  -- Frame Highlights
  use(neodap.plugins.frame_highlights, "frame_highlights")

  -- Inline Values
  use(neodap.plugins.inline_values, "inline_values")

  -- Tree Buffer
  use(neodap.plugins.tree_buffer, "tree_buffer", {
    icons = {
      expanded = opts.icons.expanded,
      collapsed = opts.icons.collapsed,
    },
  })
  use(neodap.plugins.tree_preview, "tree_preview")

  -- UI Utilities
  use(neodap.plugins.preview_handler, "preview_handler")
  use(neodap.plugins.uri_picker, "uri_picker")

  -- Input/Output Buffers
  use(neodap.plugins.input_buffer, "input_buffer")
  use(neodap.plugins.source_buffer, "source_buffer")
  use(neodap.plugins.url_buffer, "url_buffer")
  use(neodap.plugins.replline, "replline")
  use(neodap.plugins.completion, "completion")
  use(neodap.plugins.variable_edit, "variable_edit")
  use(neodap.plugins.stdio_buffers, "stdio_buffers")

  -- 5. Optional Keymaps
  if opts.keys then
    local map = vim.keymap.set
    -- Stepping
    map("n", "<F10>", "<cmd>Dap step over<cr>", { desc = "Step Over" })
    map("n", "<F11>", "<cmd>Dap step into<cr>", { desc = "Step Into" })
    map("n", "<S-F11>", "<cmd>Dap step out<cr>", { desc = "Step Out" })
    -- Execution
    map("n", "<F5>", "<cmd>Dap continue<cr>", { desc = "Continue" })
    map("n", "<S-F5>", "<cmd>Dap terminate<cr>", { desc = "Terminate" })
    map("n", "<F6>", "<cmd>Dap pause<cr>", { desc = "Pause" })
    -- Breakpoints
    map("n", "<F9>", "<cmd>Dap breakpoint<cr>", { desc = "Toggle Breakpoint" })
    map("n", "<leader>db", "<cmd>Dap list breakpoints<cr>", { desc = "List Breakpoints" })
    -- UI
    map("n", "<leader>do", "<cmd>edit dap://tree/@debugger<cr>", { desc = "Open Debug Tree" })
    map("n", "<leader>du", "<cmd>edit dap://url/@session<cr>", { desc = "Open Session Info" })
  end

  return debugger
end

return M