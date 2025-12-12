-- Plugin: Console buffer for session output
-- Uses tree_buffer infrastructure with Console edges (visible outputs only)
-- Root (Session) is visible; outputs appear as children.
-- Supports two orientations: newest-first (default) or chronological (oldest-first).
-- Supports regex filtering via the `matched` property on Output nodes.
--
-- URI formats:
--   dap://console/session:<id>   - console tree (evaluations + DAP output events)
--   dap://terminal/session:<id>  - terminal buffer redirect (integratedTerminal only)

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local view_buffer = require("neodap.plugins.utils.view_buffer")
local cfg = require("neodap.plugins.tree_buffer.config")
local utils = require("neodap.utils")
local edges = require("neodap.plugins.tree_buffer.edges")
local render = require("neodap.plugins.tree_buffer.render")
local keybinds = require("neodap.plugins.tree_buffer.keybinds")
local log = require("neodap.logger")
local E = require("neodap.error")

---@class neodap.ConsoleBufferConfig
---@field keybinds? table<string, function|table> Custom keybinds (same format as tree_buffer)

---@param debugger neodap.entities.Debugger
---@param config? neodap.ConsoleBufferConfig
---@return table api Plugin API
return function(debugger, config)
  config = vim.tbl_deep_extend("force", { keybinds = {} }, config or {})
  local graph = debugger._graph
  local group = vim.api.nvim_create_augroup("neodap-console-buffer", { clear = true })

  entity_buffer.init(debugger)
  cfg.setup_highlights()

  -- View state per buffer
  local buffers = {} ---@type table<number, { vb: table, session: any, items: table[], tailing: boolean, chronological: boolean, filter_pattern: string?, category_filter: table? }>

  local function get_state(bufnr)
    local buf = buffers[bufnr]
    return buf and buf.vb and buf.vb.state
  end

  local function get_prop(item, prop, default)
    return utils.get_prop(item, prop, default)
  end

  local function get_cursor_item(bufnr)
    local buf = buffers[bufnr]
    if not buf or not buf.vb then return nil end
    return view_buffer.get_cursor_item(bufnr, buf.items, buf.vb.state.offset)
  end

  local function render_console(bufnr, state)
    local buf = buffers[bufnr]
    if not buf or not state or not state.view or not vim.api.nvim_buf_is_valid(bufnr) then return end

    local items = {}
    for item in state.view:items() do
      item.expanded = item:any_expanded()
      items[#items + 1] = item
    end

    local total = state.view:visible_total()
    local icons = cfg.default.icons
    local guide_hl = cfg.default.guide_highlights
    local guide_data = render.compute_guides(items)

    if total <= 1 and #items == 0 then
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "-- No output" })
      vim.bo[bufnr].modifiable = false
      buf.items = {}
      return
    end

    view_buffer.render_lines(bufnr, state.ns_id, items, state.offset, total, state.viewport_limit,
      function(item, line_idx)
        local i = line_idx - state.offset + 1
        local gd = guide_data[i] or { is_last = true, active_guides = {} }
        local data = render.render_item(item, icons, guide_hl, gd.is_last, gd.active_guides, get_prop, graph, debugger)
        return render.process_array(data, line_idx)
      end)

    buf.items = items
  end

  local function toggle_expand(bufnr)
    local item = get_cursor_item(bufnr)
    if not item then return end
    if not item.toggle then return end
    item:toggle()
    if item:any_expanded() and item.node and item.node.fetchChildren then
      local ref = item.node.variablesReference and item.node.variablesReference:get()
      if ref and ref > 0 then pcall(function() item.node:fetchChildren() end) end
    end
  end

  local function create_context(bufnr)
    local item = get_cursor_item(bufnr)
    if item then
      item.type = get_prop(item, "type", "Unknown")
      item.expanded = item:any_expanded()
    end
    return { item = item, entity = item and item.node, bufnr = bufnr, debugger = debugger }
  end

  ---------------------------------------------------------------------------
  -- Orientation helpers (must be defined before keybind defaults)
  ---------------------------------------------------------------------------

  ---Scroll to tailing position based on sort direction
  ---@param buf table Buffer state
  ---@param state table view_buffer state
  local function scroll_to_tail(buf, state)
    if buf.chronological then
      -- Chronological (asc): tailing = bottom of output
      local total = state.view:visible_total()
      local max_offset = math.max(0, total - state.viewport_limit)
      state.offset = max_offset
      state.view:scroll(max_offset)
    else
      -- Newest-first (desc): tailing = top of output
      state.offset = 0
      state.view:scroll(0)
    end
  end

  ---Check if viewport is at the tailing position
  ---@param buf table Buffer state
  ---@param state table view_buffer state
  ---@return boolean
  local function is_at_tail(buf, state)
    if buf.chronological then
      local total = state.view:visible_total()
      local max_offset = math.max(0, total - state.viewport_limit)
      return state.offset >= max_offset
    else
      return state.offset == 0
    end
  end

  ---Create or recreate the view_buffer for a console buffer
  ---@param bufnr number
  ---@param buf table Buffer state (must have .session set)
  local function create_console_view(bufnr, buf)
    -- Clean up old view if rebuilding
    if buf.vb then buf.vb.cleanup() end

    local session = buf.session
    local session_uri = session.uri:get()
    local edge_type = buf.chronological and "ConsoleAsc" or "Console"
    local query = edges.build_query("Session", session_uri, edge_type)
    local win = vim.fn.bufwinid(bufnr)
    local limit = (win ~= -1) and vim.api.nvim_win_get_height(win) or 50
    local view = graph:view(query, { limit = limit })

    buf.vb = view_buffer.create({
      bufnr = bufnr,
      view = view,
      group = group,
      ns_id = vim.api.nvim_create_namespace("dap-console-" .. bufnr),
      render = function(state) render_console(bufnr, state) end,
      on_viewport_change = function(state)
        if buf.tailing then scroll_to_tail(buf, state) end
      end,
      on_cursor_moved = function(state)
        buf.tailing = is_at_tail(buf, state)
      end,
    })
  end

  -- show_root = true: root Session node is visible in console
  local defaults = keybinds.make_defaults(get_state, toggle_expand, function(bufnr)
    local buf = buffers[bufnr]
    if buf and buf.vb then render_console(bufnr, buf.vb.state) end
  end, true)

  -- Console-specific keybinds
  defaults["t"] = function(ctx)
    local buf = buffers[ctx.bufnr]
    if buf and buf.session then
      vim.cmd("split dap://terminal/session:" .. buf.session.sessionId:get())
    end
  end
  defaults["i"] = function() vim.cmd("DapReplLine") end

  ---------------------------------------------------------------------------
  -- Filtering
  ---------------------------------------------------------------------------

  local function apply_filters(session, buf)
    local pattern = buf.filter_pattern
    local has_pattern = pattern and pattern ~= ""
    local cat_filter = buf.category_filter

    for output in session.allOutputs:iter() do
      local pass = true
      if cat_filter then
        local cat = output.category:get() or "stdout"
        if cat_filter[cat] == false then pass = false end
      end
      if pass and has_pattern then
        local text = output.text:get() or ""
        local ok, result = pcall(vim.fn.match, text, pattern)
        pass = ok and result ~= -1
      end
      output.matched:set(pass)
    end
  end

  local function prompt_filter(bufnr)
    local buf = buffers[bufnr]
    if not buf or not buf.session then return end
    vim.ui.input({ prompt = "Filter: ", default = buf.filter_pattern or "" }, function(input)
      if input == nil then return end
      buf.filter_pattern = input ~= "" and input or nil
      apply_filters(buf.session, buf)
    end)
  end

  local function toggle_category(bufnr, category)
    local buf = buffers[bufnr]
    if not buf or not buf.session then return end
    if not buf.category_filter then
      buf.category_filter = { stdout = true, stderr = true, console = true, repl = true }
    end
    buf.category_filter[category] = not buf.category_filter[category]
    local all_on = true
    for _, v in pairs(buf.category_filter) do
      if not v then all_on = false; break end
    end
    if all_on then buf.category_filter = nil end
    apply_filters(buf.session, buf)
    local status = {}
    if buf.category_filter then
      for _, k in ipairs({ "stdout", "stderr", "console", "repl" }) do
        if buf.category_filter[k] then status[#status + 1] = k end
      end
      vim.notify("[neodap] Console: " .. table.concat(status, " + "), vim.log.levels.INFO)
    else
      vim.notify("[neodap] Console: all categories", vim.log.levels.INFO)
    end
  end

  defaults["/"] = function(ctx) prompt_filter(ctx.bufnr) end
  defaults["1"] = function(ctx) toggle_category(ctx.bufnr, "stdout") end
  defaults["2"] = function(ctx) toggle_category(ctx.bufnr, "stderr") end
  defaults["3"] = function(ctx) toggle_category(ctx.bufnr, "console") end
  defaults["4"] = function(ctx) toggle_category(ctx.bufnr, "repl") end
  defaults["G"] = function(ctx)
    local buf = buffers[ctx.bufnr]
    if not buf or not buf.vb then return end
    buf.tailing = true
    scroll_to_tail(buf, buf.vb.state)
    render_console(ctx.bufnr, buf.vb.state)
  end
  defaults["S"] = function(ctx)
    local buf = buffers[ctx.bufnr]
    if not buf or not buf.session then return end
    buf.chronological = not buf.chronological
    buf.tailing = true
    create_console_view(ctx.bufnr, buf)
    scroll_to_tail(buf, buf.vb.state)
    render_console(ctx.bufnr, buf.vb.state)
    local mode = buf.chronological and "chronological" or "newest first"
    vim.notify("[neodap] Console: " .. mode, vim.log.levels.INFO)
  end

  ---------------------------------------------------------------------------
  -- Init / cleanup
  ---------------------------------------------------------------------------

  local function init_console(bufnr, session)
    if not session then return end

    local buf = {
      session = session,
      items = {},
      tailing = true,
      chronological = false,
      filter_pattern = nil,
      category_filter = nil,
    }
    buffers[bufnr] = buf

    create_console_view(bufnr, buf)
    keybinds.setup(bufnr, config, defaults, create_context)

    local chain = session:chainName(" > ")
    pcall(vim.api.nvim_buf_set_name, bufnr, "Console: " .. chain)

    render_console(bufnr, buf.vb.state)
  end

  local function cleanup_console(bufnr)
    local buf = buffers[bufnr]
    if buf then
      if buf.vb then buf.vb.cleanup() end
      buffers[bufnr] = nil
    end
  end

  -- Register dap://console scheme
  entity_buffer.register("dap://console", "Session", "one", {
    optional = true,
    render = function(_, session) return session and "" or "-- No session" end,
    setup = function(bufnr, session)
      vim.bo[bufnr].filetype = "dap-repl"
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then init_console(bufnr, session) end
      end)
    end,
    cleanup = cleanup_console,
    on_change = function(bufnr, _, new_session)
      cleanup_console(bufnr)
      if new_session then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then init_console(bufnr, new_session) end
        end)
      end
      return true
    end,
  })

  -- Handle dap://terminal - redirect to actual terminal buffer
  entity_buffer.register("dap://terminal", "Session", "one", {
    optional = true,
    render = function(bufnr, session)
      if not session then return "-- Session not found" end
      local term_bufnr = session:findTerminalBufnr()
      if term_bufnr then
        vim.schedule(function()
          vim.api.nvim_buf_delete(bufnr, { force = true })
          vim.api.nvim_set_current_buf(term_bufnr)
        end)
        return ""
      end
      return "-- Session has no terminal (not using integratedTerminal)"
    end,
  })

  local api = {}

  function api.open(session, opts)
    require("neodap.plugins.utils.open").open("dap://console/session:" .. session.sessionId:get(), opts)
  end

  function api.open_terminal(session, opts)
    require("neodap.plugins.utils.open").open("dap://terminal/session:" .. session.sessionId:get(), opts)
  end

  function api.cleanup()
  end

  return api
end
