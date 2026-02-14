-- Keybind handlers for tree buffer

local navigate = require("neodap.plugins.utils.navigate")
local is_dap_window = navigate.is_dap_window

--- Find or create a window suitable for opening source files
--- Avoids DAP buffer windows (tree, repl, etc.)
---@return number win Window ID
local function find_source_window()
  local current = vim.api.nvim_get_current_win()
  -- Try to find an existing non-DAP window
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= current and not is_dap_window(win) then
      return win
    end
  end
  -- No suitable window, create a vertical split
  vim.cmd("vsplit")
  return vim.api.nvim_get_current_win()
end

local function invoke_handler(handler, ctx)
  if type(handler) == "function" then handler(ctx); return true end
  if type(handler) ~= "table" then return nil end
  local etype = ctx.item and ctx.item.type
  local h = etype and handler[etype] or handler.default
  if h then h(ctx.item, ctx); return true end
end

local function make_defaults(get_state, toggle_expand, render_buffer, show_root)
  local hide_root = not show_root

  return {
    ["<CR>"] = function(ctx) toggle_expand(ctx.bufnr) end,
    ["<Tab>"] = function(ctx) toggle_expand(ctx.bufnr) end,
    ["o"] = function(ctx) toggle_expand(ctx.bufnr) end,

    ["l"] = function(ctx)
      if ctx.item and not ctx.item.expanded then
        toggle_expand(ctx.bufnr)
      else
        vim.cmd("normal! j")
      end
    end,

    ["h"] = function(ctx)
      if not ctx.item then return end
      if ctx.item.expanded then toggle_expand(ctx.bufnr); return end
      -- Navigate to parent using _path (works regardless of viewport)
      local path = ctx.item._path
      if not path or #path < 3 then return end
      local parent_id = path[#path - 2]
      if not parent_id then return end
      local state = get_state(ctx.bufnr)
      if not state or not state.view then return end
      local win = vim.fn.bufwinid(ctx.bufnr)
      if win == -1 then return end
      local parent_path_key = state.view:_find_path_to(parent_id)
      if not parent_path_key then return end
      local pos = state.view:_compute_virtual_position(parent_path_key)
      if not pos then return end
      -- Adjust for hidden root: position shifts down by 1 when root is visible
      if hide_root then pos = pos - 1 end
      local offset = state.offset or 0
      -- If parent is within the current viewport, just move cursor
      local h = vim.api.nvim_win_get_height(win)
      local cursor_line = pos - offset
      if cursor_line >= 1 and cursor_line <= h then
        local col = state.cursor_anchors and state.cursor_anchors[pos - 1] or 0
        vim.api.nvim_win_set_cursor(win, { cursor_line, col })
      else
        -- Parent is outside viewport, scroll to put it near the top
        local new_offset = math.max(0, pos - 1)
        if state.view.scroll then state.view:scroll(new_offset) end
        state.offset = new_offset
        render_buffer(ctx.bufnr)
        pcall(vim.api.nvim_win_set_cursor, win, { pos - new_offset, 0 })
      end
    end,

    -- TODO: implement expand_all/collapse_all on View
    -- ["zo"] = function(ctx) local s = get_state(ctx.bufnr); if s then s.view:expand_all(3) end end,
    -- ["zc"] = function(ctx) local s = get_state(ctx.bufnr); if s then s.view:collapse_all() end end,
    ["q"] = function(ctx) vim.api.nvim_buf_delete(ctx.bufnr, { force = true }) end,
    ["R"] = function(ctx) render_buffer(ctx.bufnr) end,

    ["gd"] = function(ctx)
      if ctx.entity then
        local win = find_source_window()
        vim.api.nvim_set_current_win(win)
        ctx.debugger:action("goto_source", ctx.entity)
      end
    end,

    ["gf"] = function(ctx)
      if ctx.entity then
        local win = find_source_window()
        vim.api.nvim_set_current_win(win)
        ctx.debugger:action("goto_source", ctx.entity)
      end
    end,

    ["<Space>"] = function(ctx)
      if ctx.entity then ctx.debugger:action("focus", ctx.entity) end
    end,

    ["e"] = {
      Variable = function(_, ctx)
        if not ctx.entity then return end
        vim.cmd("edit " .. vim.fn.fnameescape("dap://var/" .. ctx.entity.uri:get()))
      end,
    },

    ["i"] = {
      Stdio = function() vim.cmd("DapReplLine") end,
    },

    -- Thread control (via action registry)
    ["c"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.debugger:action("continue", ctx.entity) end
      end,
    },

    ["p"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.debugger:action("pause", ctx.entity) end
      end,
    },

    ["n"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.debugger:action("step_over", ctx.entity) end
      end,
    },

    ["s"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.debugger:action("step_in", ctx.entity) end
      end,
    },

    ["S"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.debugger:action("step_out", ctx.entity) end
      end,
    },

    -- Step and go to source (switch to source window first so jump_stop will jump there)
    ["gn"] = {
      Thread = function(_, ctx)
        if ctx.entity then
          local win = find_source_window()
          vim.api.nvim_set_current_win(win)
          ctx.debugger:action("step_over", ctx.entity)
        end
      end,
    },

    ["gs"] = {
      Thread = function(_, ctx)
        if ctx.entity then
          local win = find_source_window()
          vim.api.nvim_set_current_win(win)
          ctx.debugger:action("step_in", ctx.entity)
        end
      end,
    },

    ["gS"] = {
      Thread = function(_, ctx)
        if ctx.entity then
          local win = find_source_window()
          vim.api.nvim_set_current_win(win)
          ctx.debugger:action("step_out", ctx.entity)
        end
      end,
    },

    -- Session and Config lifecycle (via action registry)
    ["X"] = function(ctx)
      if ctx.entity then ctx.debugger:action("terminate", ctx.entity) end
    end,

    ["D"] = {
      Session = function(_, ctx)
        if ctx.entity then ctx.debugger:action("disconnect", ctx.entity) end
      end,
    },

    -- Breakpoint management
    ["t"] = function(ctx)
      if ctx.entity then ctx.debugger:action("toggle", ctx.entity) end
    end,

    ["dd"] = function(ctx)
      if ctx.entity then ctx.debugger:action("remove", ctx.entity) end
    end,

    -- Clear override (revert to global default)
    ["x"] = function(ctx)
      if ctx.entity then ctx.debugger:action("clear_override", ctx.entity) end
    end,

    ["C"] = function(ctx)
      if ctx.entity then ctx.debugger:action("edit_condition", ctx.entity) end
    end,

    ["H"] = function(ctx)
      if ctx.entity then ctx.debugger:action("edit_hit_condition", ctx.entity) end
    end,

    ["L"] = function(ctx)
      if ctx.entity then ctx.debugger:action("edit_log_message", ctx.entity) end
    end,

    -- Variable actions
    ["y"] = function(ctx)
      if ctx.entity then ctx.debugger:action("yank_value", ctx.entity) end
    end,

    ["Y"] = function(ctx)
      if ctx.entity then ctx.debugger:action("yank_name", ctx.entity) end
    end,

    -- Frame actions
    ["E"] = {
      Frame = function(_, ctx)
        if ctx.entity then
          ctx.debugger.ctx:focus(ctx.entity.uri:get())
          vim.cmd("DapReplLine")
        end
      end,
    },

    -- Scope refresh and Config restart (via action registry)
    ["r"] = {
      Scope = function(_, ctx)
        if ctx.entity then ctx.debugger:action("refresh", ctx.entity) end
      end,
      Config = function(_, ctx)
        if ctx.entity and ctx.entity.restart then
          ctx.entity:restart()
        end
      end,
    },

    -- Config view mode toggle (via action registry)
    ["v"] = {
      Config = function(_, ctx)
        if ctx.entity then
          ctx.debugger:action("toggle_view_mode", ctx.entity)
          -- Refresh buffer to rebuild tree with new view mode
          vim.schedule(function()
            vim.cmd("edit")
          end)
        end
      end,
    },
  }
end

local function setup(bufnr, config, defaults, get_context)
  local opts = { buffer = bufnr, nowait = true }
  local function make_handler(key, default)
    return function()
      local ctx = get_context(bufnr)
      local user = config.keybinds[key]
      if user and invoke_handler(user, ctx) then return end
      if default then invoke_handler(default, ctx) end
    end
  end
  for key, h in pairs(defaults) do
    vim.keymap.set("n", key, make_handler(key, h), vim.tbl_extend("force", opts, { desc = "Tree: " .. key }))
  end
  for key, _ in pairs(config.keybinds) do
    if not defaults[key] then
      vim.keymap.set("n", key, make_handler(key, nil), vim.tbl_extend("force", opts, { desc = "Custom: " .. key }))
    end
  end
end

return {
  invoke_handler = invoke_handler,
  make_defaults = make_defaults,
  setup = setup,
}
