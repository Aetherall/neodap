-- Plugin: Tree exploration buffer using entity_buffer framework
--
-- This is a reimplementation of tree_buffer.lua that uses entity_buffer
-- for URI handling and reactive root resolution.
--
-- URI format:
--   dap://tree/@debugger              - Tree rooted at debugger (follows focus)
--   dap://tree/@session               - Tree rooted at focused session (reactive)
--   dap://tree/@thread                - Tree rooted at focused thread (reactive)
--   dap://tree/@frame                 - Tree rooted at focused frame (reactive)
--   dap://tree/session:abc            - Tree rooted at specific session (static)
--   dap://tree/breakpoints:group      - Tree rooted at breakpoints group
--
-- Benefits over tree_buffer.lua:
-- - Reactive root resolution: dap://tree/@session updates when focus changes
-- - Shared URI parsing and buffer setup with other entity buffers
-- - Consistent URI format (dap://scheme/url)

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local cfg = require("neodap.plugins.tree_buffer.config")
local edges = require("neodap.plugins.tree_buffer.edges")
local render = require("neodap.plugins.tree_buffer.render")
local keybinds = require("neodap.plugins.tree_buffer.keybinds")

---@param debugger neodap.entities.Debugger
---@param config? table
return function(debugger, config)
  config = vim.tbl_deep_extend("force", cfg.default, config or {})
  local graph = debugger._graph
  local group = vim.api.nvim_create_augroup("neodap-tree-buffer", { clear = true })

  -- View state per buffer (separate from entity_buffer's state)
  local view_state = {}

  entity_buffer.init(debugger)
  cfg.setup_highlights()

  local function get_state(bufnr)
    return view_state[bufnr]
  end

  local function get_prop(item, prop, default)
    if item[prop] ~= nil then
      return item[prop]
    end
    local node = item.node or graph:get(item.id)
    if not node then
      return default
    end
    if prop == "type" then
      return node._type or default
    end
    local val = node[prop]
    if val == nil then
      return default
    end
    if type(val) == "table" and type(val.get) == "function" then
      local signal_val = val:get()
      return signal_val ~= nil and signal_val or default
    end
    return val
  end

  local function render_tree(bufnr)
    local state = view_state[bufnr]
    if not state or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    -- Use the cursor item ID saved by CursorMoved (before view changed)
    local cursor_item_id = state.cursor_item_id
    local win = vim.fn.bufwinid(bufnr)

    local view, offset = state.view, state.offset or 0
    local items = {}
    local hide_root = not config.show_root
    for item in view:items() do
      -- Hide root node by default (unless show_root is true)
      if hide_root and (item.depth or 0) == 0 then
        -- Skip root, adjust depth of children
      else
        if hide_root then
          item.depth = (item.depth or 0) - 1
        end
        table.insert(items, item)
      end
    end

    local total = view:visible_total()
    local limit = state.viewport_limit or 50
    local lines = math.max(1, total >= limit and total or (offset + #items))

    vim.bo[bufnr].modifiable = true
    local placeholders = {}
    for _ = 1, lines do
      table.insert(placeholders, "")
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, placeholders)

    local guide_data = render.compute_guides(items)
    local rendered, highlights, anchors = {}, {}, {}
    local cursor_item_line = nil

    for i, item in ipairs(items) do
      local line_idx = offset + i - 1
      local gd = guide_data[i] or { is_last = true, active_guides = {} }
      item.expanded = item:any_expanded()
      local data = render.render_item(item, config.icons, config.guide_highlights, gd.is_last, gd.active_guides, get_prop, graph)
      local text, hls, cursor_col = render.process_array(data, line_idx)
      rendered[line_idx] = text
      for _, hl in ipairs(hls) do
        table.insert(highlights, hl)
      end
      if cursor_col then
        anchors[line_idx] = cursor_col
      end
      -- Track where the previously-focused item ended up
      if cursor_item_id and item.id == cursor_item_id then
        cursor_item_line = line_idx
      end
    end

    state.cursor_anchors = anchors
    for line_idx, text in pairs(rendered) do
      vim.api.nvim_buf_set_lines(bufnr, line_idx, line_idx + 1, false, { text })
    end
    vim.bo[bufnr].modifiable = false

    vim.api.nvim_buf_clear_namespace(bufnr, state.ns_id, offset, offset + #items)
    for _, hl in ipairs(highlights) do
      pcall(vim.api.nvim_buf_set_extmark, bufnr, state.ns_id, hl.line, hl.col_start, {
        end_col = hl.col_end ~= -1 and hl.col_end or nil,
        hl_group = hl.group,
        hl_eol = hl.col_end == -1,
      })
    end

    -- Restore cursor to the same item after re-render
    if cursor_item_line and win ~= -1 then
      local anchor = anchors[cursor_item_line] or 0
      pcall(vim.api.nvim_win_set_cursor, win, { cursor_item_line + 1, anchor })
    end
  end

  local function get_cursor_item(bufnr)
    local state = view_state[bufnr]
    if not state then
      return nil
    end
    local win = vim.fn.bufwinid(bufnr)
    if win == -1 then
      return nil
    end
    local cursor = vim.api.nvim_win_get_cursor(win)[1] - 1
    local items = {}
    local hide_root = not config.show_root
    for item in state.view:items() do
      -- Apply same root-hiding logic as render_tree
      if hide_root and (item.depth or 0) == 0 then
        -- Skip root
      else
        -- Adjust depth when root is hidden (matches render_tree)
        if hide_root then
          item.depth = (item.depth or 0) - 1
        end
        table.insert(items, item)
      end
    end
    local idx = cursor - (state.offset or 0) + 1
    return (idx >= 1 and idx <= #items) and items[idx] or nil
  end

  local function create_context(bufnr)
    local item = get_cursor_item(bufnr)
    if item then
      item.type = get_prop(item, "type", "Unknown")
      item.expanded = item:any_expanded()
    end
    -- Use item.node directly (the entity reference from the view)
    local entity = item and item.node
    return { item = item, entity = entity, bufnr = bufnr, debugger = debugger }
  end

  --- Call on_expand callbacks for all edges of an entity type
  ---@param entity any The entity being expanded
  ---@param entity_type string The entity type name
  local function call_on_expand(entity, entity_type)
    local edge_defs = edges.by_type[entity_type]
    if not edge_defs or not entity then
      return
    end
    -- Check for on_expand in each edge definition
    for _, edge_def in pairs(edge_defs) do
      if type(edge_def) == "table" and edge_def.on_expand then
        edge_def.on_expand(entity)
      end
    end
  end

  local function toggle_expand(bufnr)
    local state = view_state[bufnr]
    if not state then
      return
    end
    local item = get_cursor_item(bufnr)
    if not item then
      local item_count = 0
      for _ in state.view:items() do
        item_count = item_count + 1
      end
      if item_count > 0 then
        local win = vim.fn.bufwinid(bufnr)
        if win ~= -1 then
          vim.api.nvim_win_set_cursor(win, { (state.offset or 0) + item_count, 0 })
        end
      end
      return
    end
    local entity = graph:get(item.id)
    local item_type = get_prop(item, "type", "Unknown")
    local function do_expand()
      item:toggle()
      render_tree(bufnr)
    end
    call_on_expand(entity, item_type)
    do_expand()
  end

  local function update_viewport(bufnr)
    local state = view_state[bufnr]
    if not state then
      return
    end
    local win = vim.fn.bufwinid(bufnr)
    if win == -1 then
      return
    end
    local cursor = vim.api.nvim_win_get_cursor(win)[1] - 1
    local h = vim.api.nvim_win_get_height(win)
    local off = state.offset or 0
    local top = vim.fn.line("w0", win) - 1
    if cursor < off or cursor >= off + h or top ~= off then
      local new_offset = top ~= off and top or math.max(0, cursor - math.floor(h / 2))
      state.offset = new_offset
      state.view:scroll(new_offset)
      render_tree(bufnr)
    end
  end

  local defaults = keybinds.make_defaults(get_state, toggle_expand, render_tree, config.show_root)

  ---Clean up view state for a buffer
  ---@param bufnr number
  local function cleanup_view(bufnr)
    local state = view_state[bufnr]
    if state then
      for _, unsub in ipairs(state.subscriptions or {}) do
        pcall(unsub)
      end
      if state.view then
        pcall(function()
          state.view:off()
        end)
      end
      view_state[bufnr] = nil
    end
  end

  ---Initialize tree view for an entity
  ---@param bufnr number
  ---@param entity any Root entity
  ---@param win_height? number Window height for viewport limit
  local function init_tree(bufnr, entity, win_height)
    if not entity then
      return
    end

    local root_type = entity:type()
    local root_uri = entity.uri:get()

    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      vim.wo[win].wrap = false
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = "no"
      vim.wo[win].foldcolumn = "0"
      vim.wo[win].cursorline = true
    end

    vim.api.nvim_create_autocmd("BufWinEnter", {
      buffer = bufnr,
      group = group,
      callback = function()
        local w = vim.fn.bufwinid(bufnr)
        if w ~= -1 then
          vim.wo[w].wrap = false
          vim.wo[w].number = false
          vim.wo[w].relativenumber = false
          vim.wo[w].signcolumn = "no"
          vim.wo[w].foldcolumn = "0"
          vim.wo[w].cursorline = true
        end
      end,
    })

    local ns_id = vim.api.nvim_create_namespace("dap-tree-" .. bufnr)
    local limit = win_height or 50

    -- Auto-fetch data for root entity using edge-based on_expand callbacks
    call_on_expand(entity, root_type)

    local view = graph:view(edges.build_query(root_type, root_uri), { limit = limit })

    local subs = {}
    view_state[bufnr] = {
      view = view,
      ns_id = ns_id,
      subscriptions = subs,
      viewport_limit = limit,
      offset = 0,
      root_id = entity:id(),
    }

    local function on_change()
      if vim.api.nvim_buf_is_valid(bufnr) then
        render_tree(bufnr)
      end
    end
    table.insert(subs, view:on("enter", on_change))
    table.insert(subs, view:on("leave", on_change))
    table.insert(subs, view:on("change", on_change))

    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = bufnr,
      group = group,
      callback = function()
        update_viewport(bufnr)

        -- Update focused_uri for tree preview integration
        local item = get_cursor_item(bufnr)
        local state = view_state[bufnr]
        if item then
          local entity = graph:get(item.id)
          if entity and entity.uri then
            vim.b[bufnr].focused_uri = entity.uri:get()
          end
          -- Save cursor item ID for restoration after re-render
          if state then
            state.cursor_item_id = item.id
          end
        else
          vim.b[bufnr].focused_uri = nil
          if state then
            state.cursor_item_id = nil
          end
        end

        if state and state.cursor_anchors then
          local w = vim.fn.bufwinid(bufnr)
          if w ~= -1 then
            local c = vim.api.nvim_win_get_cursor(w)
            local anchor = state.cursor_anchors[c[1] - 1]
            if anchor and c[2] ~= anchor then
              vim.api.nvim_win_set_cursor(w, { c[1], anchor })
            end
          end
        end
      end,
    })

    vim.api.nvim_create_autocmd("WinResized", {
      buffer = bufnr,
      group = group,
      callback = function()
        local state = view_state[bufnr]
        if not state then
          return
        end
        local w = vim.fn.bufwinid(bufnr)
        if w == -1 then
          return
        end
        local h = vim.api.nvim_win_get_height(w)
        if h ~= state.viewport_limit then
          state.viewport_limit = h
          if state.view.set_limit then
            state.view:set_limit(h)
          end
          render_tree(bufnr)
        end
      end,
    })

    keybinds.setup(bufnr, config, defaults, create_context)
    render_tree(bufnr)
  end

  -- Register dap://tree scheme with entity_buffer
  entity_buffer.register("dap://tree", nil, "one", {
    optional = true, -- Allow nil entity (e.g., @session when no session focused)

    -- Initial render - placeholder, actual rendering done by view subscriptions
    render = function(bufnr, entity)
      if not entity then
        return "-- No entity (waiting for focus)"
      end
      -- Return empty - init_tree will render via view subscriptions
      return ""
    end,

    -- Setup tree view
    setup = function(bufnr, entity, options)
      -- Set filetype for tree buffer
      vim.bo[bufnr].filetype = "dap-tree"

      -- Defer to get window height
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        local win = vim.fn.bufwinid(bufnr)
        local height = win ~= -1 and vim.api.nvim_win_get_height(win) or nil
        init_tree(bufnr, entity, height)
      end)
    end,

    -- Cleanup view on buffer close
    cleanup = function(bufnr)
      cleanup_view(bufnr)
    end,

    -- Handle root entity changes (reactive resolution)
    on_change = function(bufnr, old_entity, new_entity, is_dirty)
      local state = view_state[bufnr]

      -- Check if root actually changed
      local old_id = old_entity and old_entity:id()
      local new_id = new_entity and new_entity:id()

      if old_id ~= new_id then
        -- Root entity changed, recreate view
        if state then
          cleanup_view(bufnr)
        end

        if new_entity then
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
              local win = vim.fn.bufwinid(bufnr)
              local height = win ~= -1 and vim.api.nvim_win_get_height(win) or nil
              init_tree(bufnr, new_entity, height)
            end
          end)
        end
      end

      return true -- Let entity_buffer update its state
    end,
  })

  return {
    cleanup = function()
      for bufnr, _ in pairs(view_state) do
        cleanup_view(bufnr)
      end
      view_state = {}
      pcall(vim.api.nvim_del_augroup_by_name, "neodap-tree-buffer")
    end,
  }
end
