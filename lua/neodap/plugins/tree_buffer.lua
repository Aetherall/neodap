-- Plugin: Tree exploration buffer using entity_buffer framework
--
-- URI format:
--   dap://tree/@debugger              - Tree rooted at debugger (follows focus)
--   dap://tree/@session               - Tree rooted at focused session (reactive)
--   dap://tree/@thread                - Tree rooted at focused thread (reactive)
--   dap://tree/@frame                 - Tree rooted at focused frame (reactive)
--   dap://tree/session:abc            - Tree rooted at specific session (static)
--   dap://tree/breakpoints:group      - Tree rooted at breakpoints group

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local view_buffer = require("neodap.plugins.utils.view_buffer")
local cfg = require("neodap.plugins.tree_buffer.config")
local themes = require("neodap.themes")
local icon_sets = require("neodap.icons")
local utils = require("neodap.utils")
local edges = require("neodap.plugins.tree_buffer.edges")
local render = require("neodap.plugins.tree_buffer.render")
local keybinds = require("neodap.plugins.tree_buffer.keybinds")

---@param debugger neodap.entities.Debugger
---@param config? table
return function(debugger, config)
  -- Four-way merge: defaults → theme → icon_set → user config
  local user_config = config or {}
  local theme = themes.resolve(user_config.theme)
  local icon_set = icon_sets.resolve(user_config.icon_set)
  config = vim.tbl_deep_extend("force", cfg.default, theme, icon_set, user_config)
  local graph = debugger._graph
  local group = vim.api.nvim_create_augroup("neodap-tree-buffer", { clear = true })

  entity_buffer.init(debugger)
  cfg.setup_highlights(config.highlights)

  -- Apply user component overrides (after default registration by entity_buffer.init)
  if config.components and next(config.components) then
    for name, by_type in pairs(config.components) do
      for entity_type, fn in pairs(by_type) do
        debugger:register_component(name, entity_type, fn)
      end
    end
  end

  -- State per buffer
  local buffers = {} ---@type table<number, { vb: table, items: table[], edge_type: string?, cursor_item_path: string?, cursor_anchors: table? }>

  local function get_state(bufnr)
    local buf = buffers[bufnr]
    return buf and buf.vb and buf.vb.state
  end

  local function get_prop(item, prop, default)
    return utils.get_prop(item, prop, default, graph)
  end

  --- Call on_expand callbacks for all edges of an entity type.
  ---@param entity any The graph entity
  ---@param entity_type string The entity type name
  ---@param context? "enter"|"expand"|"init" Why on_expand is being called
  local function call_on_expand(entity, entity_type, context)
    local edge_defs = edges.by_type[entity_type]
    if not edge_defs or not entity then return end
    for edge_name, edge_def in pairs(edge_defs) do
      if type(edge_def) == "table" and edge_def.on_expand then
        edge_def.on_expand(entity, context)
      end
    end
  end

  local function collect_items(view)
    local items = {}
    local hide_root = not config.show_root
    for item in view:items() do
      if hide_root and (item.depth or 0) == 0 then
        -- skip root
      else
        if hide_root then item.depth = (item.depth or 0) - 1 end
        items[#items + 1] = item
      end
    end
    return items
  end

  local function get_cursor_item(bufnr)
    local buf = buffers[bufnr]
    if not buf or not buf.vb then return nil end
    -- Re-collect from view (items may have changed since last render)
    local items = collect_items(buf.vb.state.view)
    return view_buffer.get_cursor_item(bufnr, items, buf.vb.state.offset)
  end

  local function render_tree(bufnr, state)
    local buf = buffers[bufnr]
    if not buf or not state or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local cursor_item_path = buf.cursor_item_path
    local win = vim.fn.bufwinid(bufnr)
    local items = collect_items(state.view)
    local total = state.view:visible_total()
    local guide_data = render.compute_guides(items)
    local anchors = {}
    local cursor_item_line = nil

    view_buffer.render_lines(bufnr, state.ns_id, items, state.offset, total, state.viewport_limit,
      function(item, line_idx)
        local i = line_idx - state.offset + 1
        local gd = guide_data[i] or { is_last = true, active_guides = {} }
        item.expanded = item:any_expanded_with_children()
        local data = render.render_item(item, config.icons, config.guide_highlights, gd.is_last, gd.active_guides, get_prop, graph, debugger, config.layouts, config.icon_highlights, config.var_type_icons)
        local text, hls, cursor_col, right_virt = render.process_array(data, line_idx)
        if cursor_col then anchors[line_idx] = cursor_col end
        if cursor_item_path and item._path and table.concat(item._path, ":") == cursor_item_path then
          cursor_item_line = line_idx
        end
        return text, hls, cursor_col, right_virt
      end)

    buf.items = items
    buf.cursor_anchors = anchors

    -- Restore cursor to same item after re-render
    if cursor_item_line and win ~= -1 then
      local anchor = anchors[cursor_item_line] or 0
      pcall(vim.api.nvim_win_set_cursor, win, { cursor_item_line + 1, anchor })
    end
  end

  local function create_context(bufnr)
    local item = get_cursor_item(bufnr)
    if item then
      item.type = get_prop(item, "type", "Unknown")
      item.expanded = item:any_expanded()
    end
    local entity = item and (item.node or graph:get(item.id))
    return { item = item, entity = entity, bufnr = bufnr, debugger = debugger }
  end

  local function toggle_expand(bufnr)
    local buf = buffers[bufnr]
    if not buf or not buf.vb then return end
    local item = get_cursor_item(bufnr)
    if not item then
      -- If no item at cursor, move cursor to last visible item
      local items = collect_items(buf.vb.state.view)
      if #items > 0 then
        local win = vim.fn.bufwinid(bufnr)
        if win ~= -1 then
          vim.api.nvim_win_set_cursor(win, { (buf.vb.state.offset or 0) + #items, 0 })
        end
      end
      return
    end
    local entity = graph:get(item.id)
    call_on_expand(entity, get_prop(item, "type", "Unknown"), "expand")
    item:toggle()
    render_tree(bufnr, buf.vb.state)
  end

  local defaults = keybinds.make_defaults(get_state, toggle_expand, function(bufnr)
    local buf = buffers[bufnr]
    if buf and buf.vb then render_tree(bufnr, buf.vb.state) end
  end, config.show_root, create_context)

  ---------------------------------------------------------------------------
  -- Init / cleanup
  ---------------------------------------------------------------------------

  local function cleanup_view(bufnr)
    local buf = buffers[bufnr]
    if buf then
      if buf.vb then buf.vb.cleanup() end
      buffers[bufnr] = nil
    end
  end

  local function init_tree(bufnr, entity, win_height, edge_type)
    if not entity then return end

    local root_type = entity:type()
    local root_uri = entity.uri:get()

    call_on_expand(entity, root_type, "init")

    local show_terminated = rawget(debugger, "_show_terminated") or false
    local view = graph:view(edges.build_query(root_type, root_uri, edge_type, entity, {
      show_terminated = show_terminated,
    }), {
      limit = win_height or 50,
    })

    local buf = { items = {}, edge_type = edge_type }
    buffers[bufnr] = buf

    buf.vb = view_buffer.create({
      bufnr = bufnr,
      view = view,
      group = group,
      ns_id = vim.api.nvim_create_namespace("dap-tree-" .. bufnr),
      render = function(state) render_tree(bufnr, state) end,
      on_enter = function(ent)
        if ent and ent._type then call_on_expand(ent, ent._type, "enter") end
      end,
      on_cursor_moved = function(state)
        local item = get_cursor_item(bufnr)
        if item then
          local ent = graph:get(item.id)
          if ent and ent.uri then
            vim.b[bufnr].focused_uri = ent.uri:get()
          end
          buf.cursor_item_path = item._path and table.concat(item._path, ":") or nil
        else
          vim.b[bufnr].focused_uri = nil
          buf.cursor_item_path = nil
        end
        -- Snap cursor to anchor column
        if buf.cursor_anchors then
          local w = vim.fn.bufwinid(bufnr)
          if w ~= -1 then
            local c = vim.api.nvim_win_get_cursor(w)
            local anchor = buf.cursor_anchors[c[1] - 1]
            if anchor and c[2] ~= anchor then
              vim.api.nvim_win_set_cursor(w, { c[1], anchor })
            end
          end
        end
      end,
    })

    render_tree(bufnr, buf.vb.state)
  end

  -- Register dap://tree scheme
  entity_buffer.register("dap://tree", nil, "one", {
    optional = true,
    render = function(_, entity)
      return entity and "" or "-- No entity (waiting for focus)"
    end,
    setup = function(bufnr, entity, options)
      vim.bo[bufnr].filetype = "dap-tree"
      keybinds.setup(bufnr, config, defaults, create_context)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local win = vim.fn.bufwinid(bufnr)
        init_tree(bufnr, entity, win ~= -1 and vim.api.nvim_win_get_height(win) or nil, options and options.edge)
      end)
    end,
    cleanup = cleanup_view,
    on_change = function(bufnr, old_entity, new_entity)
      local old_id = old_entity and old_entity:id()
      local new_id = new_entity and new_entity:id()
      if old_id ~= new_id then
        local buf = buffers[bufnr]
        local edge_type = buf and buf.edge_type
        cleanup_view(bufnr)
        if new_entity then
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
              local win = vim.fn.bufwinid(bufnr)
              init_tree(bufnr, new_entity, win ~= -1 and vim.api.nvim_win_get_height(win) or nil, edge_type)
            else
            end
          end)
        end
      end
      return true
    end,
  })

  return {
    cleanup = function()
      for bufnr in pairs(buffers) do cleanup_view(bufnr) end
      buffers = {}
      pcall(vim.api.nvim_del_augroup_by_name, "neodap-tree-buffer")
    end,
  }
end
