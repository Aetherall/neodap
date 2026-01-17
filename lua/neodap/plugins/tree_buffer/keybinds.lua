-- Keybind handlers for tree buffer

-- DAP buffer filetypes that should not be used for source files
local dap_filetypes = {
  ["dap-tree"] = true,
  ["dap-repl"] = true,
  ["dap-var"] = true,
  ["dap-input"] = true,
}

---Check if a window contains a DAP buffer
---@param win number Window ID
---@return boolean
local function is_dap_window(win)
  local bufnr = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[bufnr].filetype
  return dap_filetypes[ft] or false
end

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
      local state = get_state(ctx.bufnr)
      if not state then return end
      local win = vim.fn.bufwinid(ctx.bufnr)
      if win == -1 then return end
      local cursor = vim.api.nvim_win_get_cursor(win)[1]
      local offset = state.offset or 0
      local items = {}
      for item in state.view:items() do
        -- Skip root when hidden (matches render_tree and get_cursor_item)
        if not (hide_root and (item.depth or 0) == 0) then
          local adjusted_depth = hide_root and (item.depth or 0) - 1 or item.depth
          item.depth = adjusted_depth
          table.insert(items, item)
        end
      end
      local idx = cursor - offset
      for i = idx - 1, 1, -1 do
        if items[i].depth < ctx.item.depth then
          local line = offset + i
          local col = state.cursor_anchors and state.cursor_anchors[line - 1] or 0
          vim.api.nvim_win_set_cursor(win, { line, col })
          return
        end
      end
      if ctx.item.depth > 0 and state.view.scroll_by then state.view:scroll_by(-10) end
    end,

    -- TODO: implement expand_all/collapse_all on View
    -- ["zo"] = function(ctx) local s = get_state(ctx.bufnr); if s then s.view:expand_all(3) end end,
    -- ["zc"] = function(ctx) local s = get_state(ctx.bufnr); if s then s.view:collapse_all() end end,
    ["q"] = function(ctx) vim.api.nvim_buf_delete(ctx.bufnr, { force = true }) end,
    ["R"] = function(ctx) render_buffer(ctx.bufnr) end,

    ["gd"] = {
      Frame = function(_, ctx)
        if not ctx.entity then return end
        local src = ctx.entity.source:get()
        if src then
          local win = find_source_window()
          vim.api.nvim_set_current_win(win)
          src:open({ line = ctx.entity.line:get() or 1 })
        end
      end,
      Breakpoint = function(_, ctx)
        if not ctx.entity then return end
        local src = ctx.entity.source:get()
        if src then
          local win = find_source_window()
          vim.api.nvim_set_current_win(win)
          src:open({ line = ctx.entity.line:get() or 1 })
        end
      end,
    },

    ["<Space>"] = {
      Frame = function(_, ctx) if ctx.entity then ctx.debugger.ctx:focus(ctx.entity.uri:get()) end end,
      Session = function(_, ctx) if ctx.entity then ctx.debugger.ctx:focus(ctx.entity.uri:get()) end end,
    },

    ["e"] = {
      Variable = function(_, ctx)
        if ctx.entity then vim.cmd("edit dap-var:" .. ctx.entity.uri:get()) end
      end,
    },

    ["i"] = {
      Stdio = function() vim.cmd("DapReplLine") end,
    },

    -- Thread control
    ["c"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.entity:continue() end
      end,
    },

    ["p"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.entity:pause() end
      end,
    },

    ["n"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.entity:stepOver() end
      end,
    },

    ["s"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.entity:stepIn() end
      end,
    },

    ["S"] = {
      Thread = function(_, ctx)
        if ctx.entity then ctx.entity:stepOut() end
      end,
    },

    -- Step and go to source (switch to source window first so jump_stop will jump there)
    ["gn"] = {
      Thread = function(_, ctx)
        if ctx.entity then
          local win = find_source_window()
          vim.api.nvim_set_current_win(win)
          ctx.entity:stepOver()
        end
      end,
    },

    ["gs"] = {
      Thread = function(_, ctx)
        if ctx.entity then
          local win = find_source_window()
          vim.api.nvim_set_current_win(win)
          ctx.entity:stepIn()
        end
      end,
    },

    ["gS"] = {
      Thread = function(_, ctx)
        if ctx.entity then
          local win = find_source_window()
          vim.api.nvim_set_current_win(win)
          ctx.entity:stepOut()
        end
      end,
    },

    -- Session control
    ["X"] = {
      Session = function(_, ctx)
        if ctx.entity then ctx.entity:terminate() end
      end,
    },

    -- Breakpoint management
    ["t"] = {
      Breakpoint = function(_, ctx)
        if ctx.entity then
          ctx.entity:toggle()
          ctx.entity:sync()
        end
      end,
    },

    ["dd"] = {
      Breakpoint = function(_, ctx)
        if ctx.entity then ctx.entity:remove() end
      end,
    },

    ["C"] = {
      Breakpoint = function(_, ctx)
        if not ctx.entity then return end
        vim.ui.input({ prompt = "Condition: ", default = ctx.entity.condition:get() or "" }, function(input)
          if input then
            ctx.entity:update({ condition = input ~= "" and input or nil })
            ctx.entity:sync()
          end
        end)
      end,
    },

    ["H"] = {
      Breakpoint = function(_, ctx)
        if not ctx.entity then return end
        vim.ui.input({ prompt = "Hit condition: ", default = ctx.entity.hitCondition:get() or "" }, function(input)
          if input then
            ctx.entity:update({ hitCondition = input ~= "" and input or nil })
            ctx.entity:sync()
          end
        end)
      end,
    },

    ["L"] = {
      Breakpoint = function(_, ctx)
        if not ctx.entity then return end
        vim.ui.input({ prompt = "Log message: ", default = ctx.entity.logMessage:get() or "" }, function(input)
          if input then
            ctx.entity:update({ logMessage = input ~= "" and input or nil })
            ctx.entity:sync()
          end
        end)
      end,
    },

    -- Variable actions
    ["y"] = {
      Variable = function(_, ctx)
        if ctx.entity then
          local value = ctx.entity.value:get()
          if value then
            vim.fn.setreg('"', value)
            vim.notify("Yanked: " .. (value:sub(1, 50)) .. (value:len() > 50 and "..." or ""))
          end
        end
      end,
    },

    ["Y"] = {
      Variable = function(_, ctx)
        if ctx.entity then
          local name = ctx.entity.name:get()
          if name then
            vim.fn.setreg('"', name)
            vim.notify("Yanked: " .. name)
          end
        end
      end,
    },

    -- Frame actions
    ["E"] = {
      Frame = function(_, ctx)
        if ctx.entity then
          ctx.debugger.ctx:focus(ctx.entity.uri:get())
          vim.cmd("DapReplLine")
        end
      end,
    },

    -- Scope actions
    ["r"] = {
      Scope = function(_, ctx)
        if ctx.entity then ctx.entity:fetchVariables() end
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
