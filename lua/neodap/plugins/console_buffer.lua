-- Plugin: Console buffer for session output
-- Uses tree_buffer infrastructure with Console edges (visible outputs only)
-- Root (Session) is visible; outputs appear as children sorted newest-first.
-- Supports regex filtering via the `matched` property on Output nodes.
--
-- URI formats:
--   dap://console/session:<id>   - console tree (evaluations + DAP output events)
--   dap://terminal/session:<id>  - terminal buffer redirect (integratedTerminal only)

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local cfg = require("neodap.plugins.tree_buffer.config")
local edges = require("neodap.plugins.tree_buffer.edges")
local render = require("neodap.plugins.tree_buffer.render")
local keybinds = require("neodap.plugins.tree_buffer.keybinds")
local log = require("neodap.logger")

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
  local view_state = {}

  local function get_state(bufnr)
    return view_state[bufnr]
  end

  local function get_prop(item, prop, default)
    if item[prop] ~= nil then return item[prop] end
    local node = item.node
    if not node then return default end
    if prop == "type" then return node._type or default end
    local val = node[prop]
    if val == nil then return default end
    if type(val) == "table" and type(val.get) == "function" then
      return val:get() or default
    end
    return val
  end

  local function render_console(bufnr)
    local state = view_state[bufnr]
    if not state or not state.view or not vim.api.nvim_buf_is_valid(bufnr) then return end

    local view, offset = state.view, state.offset or 0

    -- Collect items from view (already windowed by offset+limit)
    -- Root (Session) is visible — no depth filtering
    local items = {}
    for item in view:items() do
      item.expanded = item:any_expanded()
      table.insert(items, item)
    end

    local total = view:visible_total()
    local limit = state.viewport_limit or 50
    local lines_count = math.max(1, total >= limit and total or (offset + #items))

    -- Create placeholder lines for the full buffer height
    vim.bo[bufnr].modifiable = true
    local placeholders = {}
    for _ = 1, lines_count do
      table.insert(placeholders, "")
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, placeholders)

    local icons = cfg.default.icons
    local guide_hl = cfg.default.guide_highlights
    local guide_data = render.compute_guides(items)
    local rendered, highlights = {}, {}

    for i, item in ipairs(items) do
      local line_idx = offset + i - 1
      local gd = guide_data[i] or { is_last = true, active_guides = {} }
      local data = render.render_item(item, icons, guide_hl, gd.is_last, gd.active_guides, get_prop, graph, debugger)
      local text, hls = render.process_array(data, line_idx)
      rendered[line_idx] = text
      for _, hl in ipairs(hls) do table.insert(highlights, hl) end
    end

    if lines_count <= 1 and #items == 0 then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "-- No output" })
    else
      for line_idx, text in pairs(rendered) do
        vim.api.nvim_buf_set_lines(bufnr, line_idx, line_idx + 1, false, { text })
      end
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

    state.items = items
  end

  local function get_cursor_item(bufnr)
    local state = view_state[bufnr]
    if not state or not state.items then return nil end
    local win = vim.fn.bufwinid(bufnr)
    if win == -1 then return nil end
    local cursor = vim.api.nvim_win_get_cursor(win)[1] - 1
    local idx = cursor - (state.offset or 0) + 1
    return (idx >= 1 and idx <= #state.items) and state.items[idx] or nil
  end

  local function toggle_expand(bufnr)
    local item = get_cursor_item(bufnr)
    if not item then
      log:info("toggle_expand: no item at cursor")
      return
    end
    if not item.toggle then
      log:info("toggle_expand: item has no toggle method", {
        type = item.node and item.node:type() or "?",
        uri = item.node and item.node.uri and item.node.uri:get() or "?",
      })
      return
    end
    log:info("toggle_expand: toggling", {
      type = item.node and item.node:type() or "?",
      expanded_before = item:any_expanded(),
    })
    item:toggle()
    local expanded_after = item:any_expanded()
    local has_node = item.node ~= nil
    local has_fetch = item.node and item.node.fetchChildren ~= nil
    log:info("toggle_expand: after toggle", {
      expanded_after = expanded_after,
      has_node = has_node,
      has_fetchChildren = has_fetch,
    })
    -- Fetch children if expanding
    if expanded_after and has_node and has_fetch then
      local ref = item.node.variablesReference and item.node.variablesReference:get()
      log:info("toggle_expand: calling fetchChildren", {
        type = item.node:type(),
        ref = ref,
      })
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

  -- show_root = true: root Session node is visible in console
  local defaults = keybinds.make_defaults(get_state, toggle_expand, render_console, true)

  -- Add terminal keybind for console buffer (opens terminal in a split)
  defaults["t"] = function(ctx)
    local state = view_state[ctx.bufnr]
    if state and state.session then
      local session_id = state.session.sessionId:get()
      vim.cmd("split dap://terminal/session:" .. session_id)
    end
  end

  -- Override i to always open REPL line in console (default only works on Stdio nodes)
  defaults["i"] = function() vim.cmd("DapReplLine") end

  ---------------------------------------------------------------------------
  -- Regex filtering: toggle matched property on Output nodes
  ---------------------------------------------------------------------------

  --- Apply a regex pattern to all Output nodes linked to a session.
  --- Sets matched=true for nodes whose text matches, matched=false otherwise.
  --- When pattern is nil or empty, resets all to matched=true.
  ---@param session any Session entity
  ---@param pattern string|nil Lua pattern to match against output text
  local function apply_filter(session, pattern)
    local has_pattern = pattern and pattern ~= ""
    -- Iterate all Output nodes linked to this session via allOutputs
    for output in session.allOutputs:iter() do
      if has_pattern then
        local text = output.text:get() or ""
        local ok, result = pcall(vim.fn.match, text, pattern)
        output.matched:set((ok and result ~= -1) and true or false)
      else
        output.matched:set(true)
      end
    end
  end

  --- Prompt for a filter pattern and apply it
  local function prompt_filter(bufnr)
    local state = view_state[bufnr]
    if not state or not state.session then return end

    local current = state.filter_pattern or ""
    vim.ui.input({ prompt = "Filter: ", default = current }, function(input)
      if input == nil then return end -- cancelled
      state.filter_pattern = input ~= "" and input or nil
      apply_filter(state.session, state.filter_pattern)
    end)
  end

  defaults["/"] = function(ctx) prompt_filter(ctx.bufnr) end

  ---------------------------------------------------------------------------
  -- Viewport management
  ---------------------------------------------------------------------------

  local function update_viewport(bufnr)
    local state = view_state[bufnr]
    if not state then return end
    local win = vim.fn.bufwinid(bufnr)
    if win == -1 then return end
    local cursor = vim.api.nvim_win_get_cursor(win)[1] - 1
    local h = vim.api.nvim_win_get_height(win)
    local off = state.offset or 0
    local top = vim.fn.line("w0", win) - 1
    if cursor < off or cursor >= off + h or top ~= off then
      local new_offset = top ~= off and top or math.max(0, cursor - math.floor(h / 2))
      state.offset = new_offset
      state.view:scroll(new_offset)

      -- With descending sort, new items appear at offset 0 (top).
      -- Re-enable tailing when cursor is at or near the top.
      state.tailing = (new_offset == 0)

      render_console(bufnr)
    end
  end

  local function init_console(bufnr, session)
    if not session then return end

    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      vim.wo[win].wrap = false
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = "no"
      vim.wo[win].cursorline = true
    end

    local ns_id = vim.api.nvim_create_namespace("dap-console-" .. bufnr)
    local subs = {}
    local limit = (win ~= -1) and vim.api.nvim_win_get_height(win) or 50

    -- Create view using Console edges (sorted newest-first, filtered to visible+matched)
    local session_uri = session.uri:get()
    local query = edges.build_query("Session", session_uri, "Console")
    local view = graph:view(query, { limit = limit })

    view_state[bufnr] = {
      session = session,
      view = view,
      ns_id = ns_id,
      subscriptions = subs,
      items = {},
      viewport_limit = limit,
      offset = 0,
      tailing = true, -- Start in tail mode (new output appears at top with desc sort)
      filter_pattern = nil,
    }

    -- Debounced render
    -- With descending sort, new items appear at offset 0 (top of buffer).
    -- Tailing keeps offset=0 so the latest output is always visible.
    local render_timer = nil
    local function schedule_render()
      if render_timer then return end
      render_timer = vim.defer_fn(function()
        render_timer = nil
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local state = view_state[bufnr]
        if not state then return end

        -- When tailing, keep viewport at top (offset=0) so newest items are visible
        if state.tailing then
          state.offset = 0
          state.view:scroll(0)
        end

        render_console(bufnr)
      end, 16)
    end

    table.insert(subs, view:on("enter", schedule_render))
    table.insert(subs, view:on("leave", schedule_render))
    table.insert(subs, view:on("change", schedule_render))

    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = bufnr,
      group = group,
      callback = function()
        update_viewport(bufnr)
      end,
    })

    vim.api.nvim_create_autocmd("WinResized", {
      buffer = bufnr,
      group = group,
      callback = function()
        local state = view_state[bufnr]
        if not state then return end
        local w = vim.fn.bufwinid(bufnr)
        if w == -1 then return end
        local h = vim.api.nvim_win_get_height(w)
        if h ~= state.viewport_limit then
          state.viewport_limit = h
          render_console(bufnr)
        end
      end,
    })

    keybinds.setup(bufnr, config, defaults, create_context)

    -- Set buffer name to show session chain in detour popup title
    local chain = session:chainName(" > ")
    pcall(vim.api.nvim_buf_set_name, bufnr, "Console: " .. chain)

    render_console(bufnr)
  end

  local function cleanup_console(bufnr)
    local state = view_state[bufnr]
    if state then
      if state.view and state.view.destroy then pcall(state.view.destroy, state.view) end
      for _, unsub in ipairs(state.subscriptions or {}) do pcall(unsub) end
      view_state[bufnr] = nil
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
    -- Reinitialize when focused session changes (for contextual @session URLs)
    on_change = function(bufnr, old_session, new_session, is_dirty)
      -- Clean up old view and subscriptions
      cleanup_console(bufnr)
      -- Initialize with new session
      if new_session then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then init_console(bufnr, new_session) end
        end)
      end
      return true -- Signal that we handled the update
    end,
  })

  -- Handle dap://terminal - redirect to actual terminal buffer
  entity_buffer.register("dap://terminal", "Session", "one", {
    optional = true,
    render = function(bufnr, session)
      if not session then return "-- Session not found" end
      -- Find terminal buffer (check parent sessions too)
      local current = session
      while current do
        local term_bufnr = current.terminalBufnr and current.terminalBufnr:get()
        if term_bufnr and vim.api.nvim_buf_is_valid(term_bufnr) then
          vim.schedule(function()
            vim.api.nvim_buf_delete(bufnr, { force = true })
            vim.api.nvim_set_current_buf(term_bufnr)
          end)
          return ""
        end
        current = current.parent and current.parent:get()
      end
      return "-- Session has no terminal (not using integratedTerminal)"
    end,
  })

  local api = {}

  function api.open(session, opts)
    opts = opts or {}
    local uri = "dap://console/session:" .. session.sessionId:get()
    local cmd = ({ horizontal = "split", vertical = "vsplit", tab = "tabedit" })[opts.split] or "edit"
    vim.cmd(cmd .. " " .. vim.fn.fnameescape(uri))
  end

  function api.open_terminal(session, opts)
    opts = opts or {}
    local uri = "dap://terminal/session:" .. session.sessionId:get()
    local cmd = ({ horizontal = "split", vertical = "vsplit", tab = "tabedit" })[opts.split] or "edit"
    vim.cmd(cmd .. " " .. vim.fn.fnameescape(uri))
  end

  vim.api.nvim_create_user_command("DapConsole", function()
    local session = debugger.ctx.session:get()
    if not session then vim.notify("No focused session", vim.log.levels.WARN); return end
    api.open(session)
  end, { desc = "Open console buffer for focused debug session" })

  vim.api.nvim_create_user_command("DapTerminal", function()
    local session = debugger.ctx.session:get()
    if not session then vim.notify("No focused session", vim.log.levels.WARN); return end
    api.open_terminal(session)
  end, { desc = "Open terminal buffer for focused debug session" })

  return api
end
