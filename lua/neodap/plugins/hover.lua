-- Plugin: Split-float hover for DAP + LSP
--
-- Replaces the old in-process LSP approach with a Chrome DevTools-style
-- split float: interactive tree view (top) + LSP type info (bottom).
--
-- K behavior:
--   1st press → open split float (unfocused)
--   2nd press → focus tree window for interaction
--   No debug session → fall through to vim.lsp.buf.hover()
--
-- The tree panel uses dap://tree/<var_uri> for expandable runtime values.
-- The info panel shows LSP hover (vtsls type info etc.) as rendered markdown.

local expression_utils = require("neodap.plugins.utils.expression")
local a = require("neodap.async")
local log = require("neodap.logger")
local E = require("neodap.error")

---@class HoverConfig
---@field auto_attach? boolean Automatically attach to buffers (default: true)

local default_config = {
  auto_attach = true,
}

-- Split float state (module-level singleton since only one hover at a time)
local state = {
  tree_win = nil,   -- tree float window
  tree_buf = nil,   -- tree float buffer
  info_win = nil,   -- LSP info float window
  info_buf = nil,   -- LSP info buffer
  source_win = nil, -- the window K was pressed in
  source_buf = nil, -- the buffer K was pressed in
  expression = nil, -- the hovered expression
  autocmd_id = nil, -- CursorMoved autocmd for auto-close
  group = nil,      -- augroup for hover lifecycle
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function close_hover()
  -- Remove autocmd
  if state.autocmd_id then
    pcall(vim.api.nvim_del_autocmd, state.autocmd_id)
    state.autocmd_id = nil
  end

  -- Close windows (order matters — info is relative to tree)
  if is_valid_win(state.info_win) then
    pcall(vim.api.nvim_win_close, state.info_win, true)
  end
  if is_valid_win(state.tree_win) then
    pcall(vim.api.nvim_win_close, state.tree_win, true)
  end

  -- Delete info buf (ephemeral), keep tree buf (entity_buffer manages it)
  if state.info_buf and vim.api.nvim_buf_is_valid(state.info_buf) then
    pcall(vim.api.nvim_buf_delete, state.info_buf, { force = true })
  end

  state.tree_win = nil
  state.tree_buf = nil
  state.info_win = nil
  state.info_buf = nil
  state.source_win = nil
  state.source_buf = nil
  state.expression = nil
end

local function is_hover_open()
  return is_valid_win(state.tree_win)
end

local function is_hover_focused()
  if not is_hover_open() then return false end
  local cur = vim.api.nvim_get_current_win()
  return cur == state.tree_win or cur == state.info_win
end

--- Collect LSP hover markdown from non-neodap clients
---@param bufnr number
---@param row number 0-indexed
---@param col number 0-indexed
---@param callback fun(markdown: string?)
local function get_lsp_hover(bufnr, row, col, callback)
  local params = vim.lsp.util.make_position_params(0, "utf-16")
  -- Override position to be explicit (make_position_params uses cursor)
  params.position = { line = row, character = col }
  params.textDocument = { uri = vim.uri_from_bufnr(bufnr) }

  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local results = {}
  local pending = 0

  for _, client in ipairs(clients) do
    -- Skip neodap-hover (old client, if somehow still around) 
    if client.name ~= "neodap-hover" and client:supports_method("textDocument/hover") then
      pending = pending + 1
      client:request("textDocument/hover", params, function(err, result)
        if not err and result and result.contents then
          local md
          if type(result.contents) == "string" then
            md = result.contents
          elseif result.contents.value then
            md = result.contents.value
          elseif result.contents.language then
            md = "```" .. result.contents.language .. "\n" .. result.contents.value .. "\n```"
          end
          if md and md ~= "" then
            table.insert(results, md)
          end
        end
        pending = pending - 1
        if pending == 0 then
          callback(#results > 0 and table.concat(results, "\n---\n") or nil)
        end
      end, bufnr)
    end
  end

  -- No LSP clients with hover support
  if pending == 0 then
    callback(nil)
  end
end

--- Calculate float dimensions relative to cursor
---@param tree_height number
---@param info_height number
---@return table config { width, col, row }
local function calc_float_position(tree_height, info_height)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor_pos[1]
  local win_pos = vim.api.nvim_win_get_position(0)
  local win_top = vim.fn.line("w0")

  -- Screen position of cursor
  local screen_row = win_pos[1] + (cursor_row - win_top)
  local screen_col = win_pos[2] + cursor_pos[2]

  local editor_w = vim.o.columns
  local editor_h = vim.o.lines - vim.o.cmdheight - 1

  -- Width: reasonable default
  local width = math.min(60, math.floor(editor_w * 0.5))
  width = math.max(width, 30)

  -- Total float height (tree + border separator + info)
  local total_h = tree_height + info_height + 2 -- +2 for separator border

  -- Place below cursor if space, above otherwise
  local row
  local space_below = editor_h - screen_row - 1
  local space_above = screen_row
  if space_below >= total_h + 2 then
    row = screen_row + 1
  elseif space_above >= total_h + 2 then
    row = screen_row - total_h - 2
  else
    -- Not enough room either way — prefer below, clamp
    row = screen_row + 1
  end
  row = math.max(0, row)

  -- Horizontal: try to align with cursor, clamp to editor
  local col = math.max(0, math.min(screen_col, editor_w - width - 2))

  return { width = width, col = col, row = row }
end

--- Render LSP markdown into the info buffer
---@param bufnr number
---@param markdown string
local function render_info_buffer(bufnr, markdown)
  local lines = vim.split(markdown, "\n")
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "markdown"
end

--- Count rendered lines in the info markdown (for sizing)
---@param markdown string?
---@return number
local function info_line_count(markdown)
  if not markdown then return 0 end
  local n = 1
  for _ in markdown:gmatch("\n") do n = n + 1 end
  return n
end

-------------------------------------------------------------------------------
-- Open split float
-------------------------------------------------------------------------------

--- Open the split-float hover for an expression
---@param debugger table
---@param expression string
---@param bufnr number Source buffer
---@param row number 0-indexed
---@param col number 0-indexed
local function open_hover(debugger, expression, bufnr, row, col)
  -- Close existing hover first
  close_hover()

  state.source_win = vim.api.nvim_get_current_win()
  state.source_buf = bufnr
  state.expression = expression

  -- Step 1: Create variable entity (async) and get LSP hover in parallel
  local var_entity = nil
  local var_uri = nil
  local lsp_markdown = nil
  local tasks_done = 0
  local total_tasks = 2

  local function on_task_done()
    tasks_done = tasks_done + 1
    if tasks_done < total_tasks then return end

    -- Both tasks complete — open the floats on main thread
    vim.schedule(function()
      if not var_uri then
        -- Variable creation failed — just show LSP hover
        if lsp_markdown then
          -- Fall through to standard hover
          vim.lsp.buf.hover()
        end
        return
      end

      -- Calculate sizes
      local tree_height = 8  -- initial height, will auto-resize
      local info_lines = info_line_count(lsp_markdown)
      local info_height = lsp_markdown and math.min(math.max(info_lines, 1), 10) or 0

      local pos = calc_float_position(tree_height, info_height)

      -- Border: tree top (no bottom border)
      local tree_border = { "╭", "─", "╮", "│", "", "", "", "│" }

      -- Create tree buffer + window
      state.tree_buf = vim.api.nvim_create_buf(false, true)
      state.tree_win = vim.api.nvim_open_win(state.tree_buf, false, {
        relative = "editor",
        row = pos.row,
        col = pos.col,
        width = pos.width,
        height = tree_height,
        style = "minimal",
        border = info_height > 0 and tree_border or "rounded",
        title = " " .. expression .. " ",
        title_pos = "center",
        focusable = true,
        zindex = 50,
      })

      if not is_valid_win(state.tree_win) then
        close_hover()
        return
      end

      vim.wo[state.tree_win].cursorline = true
      vim.wo[state.tree_win].wrap = false
      vim.wo[state.tree_win].number = false
      vim.wo[state.tree_win].relativenumber = false
      vim.wo[state.tree_win].signcolumn = "no"
      vim.wo[state.tree_win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"

      -- Load tree content: :edit dap://tree/<var_uri>
      local prev_win = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(state.tree_win)
      local tree_uri = "dap://tree/" .. var_uri
      vim.cmd("edit " .. vim.fn.fnameescape(tree_uri))
      -- Track the actual buffer (BufReadCmd may create a new one)
      state.tree_buf = vim.api.nvim_win_get_buf(state.tree_win)
      vim.api.nvim_set_current_win(prev_win)

      -- Add q keymap to tree buffer to close hover
      E.keymap("n", "q", function()
        close_hover()
      end, { buffer = state.tree_buf, nowait = true, desc = "Close hover" })

      -- Add gE keymap to tree buffer to open expression editor
      E.keymap("n", "gE", function()
        close_hover()
        vim.cmd("edit dap://eval/@frame?expression=" .. vim.uri_encode(expression) .. "&closeonsubmit")
      end, { buffer = state.tree_buf, nowait = true, desc = "Edit expression" })

      -- Info panel (bottom) — only if we have LSP markdown
      if info_height > 0 and lsp_markdown then
        local info_border = { "├", "─", "┤", "│", "╯", "─", "╰", "│" }

        state.info_buf = vim.api.nvim_create_buf(false, true)
        render_info_buffer(state.info_buf, lsp_markdown)

        state.info_win = vim.api.nvim_open_win(state.info_buf, false, {
          relative = "win",
          win = state.tree_win,
          row = tree_height,
          col = -1,
          width = pos.width,
          height = info_height,
          style = "minimal",
          border = info_border,
          focusable = false,
          zindex = 50,
        })

        if is_valid_win(state.info_win) then
          vim.wo[state.info_win].wrap = true
          vim.wo[state.info_win].number = false
          vim.wo[state.info_win].relativenumber = false
          vim.wo[state.info_win].signcolumn = "no"
          vim.wo[state.info_win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
          vim.wo[state.info_win].conceallevel = 2
        end
      end

      -- Auto-resize tree when content changes (expand/collapse)
      vim.api.nvim_buf_attach(state.tree_buf, false, {
        on_lines = function(_, buf)
          if not is_valid_win(state.tree_win) then return true end -- detach
          -- Schedule to run after the render completes
          vim.schedule(function()
            if not is_valid_win(state.tree_win) then return end
            if not vim.api.nvim_buf_is_valid(buf) then return end

            -- Count non-empty lines (view_buffer pads with empty placeholders)
            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
            local content_lines = 0
            for _, line in ipairs(lines) do
              if line ~= "" then
                content_lines = content_lines + 1
              end
            end
            -- Clamp: min 1, max ~half editor
            local editor_h = vim.o.lines - vim.o.cmdheight - 1
            local max_h = math.floor(editor_h * 0.5)
            local new_h = math.min(math.max(content_lines, 1), max_h)

            local current_h = vim.api.nvim_win_get_height(state.tree_win)
            if new_h ~= current_h then
              pcall(vim.api.nvim_win_set_height, state.tree_win, new_h)

              -- Reposition info window
              if is_valid_win(state.info_win) then
                pcall(vim.api.nvim_win_set_config, state.info_win, {
                  relative = "win",
                  win = state.tree_win,
                  row = new_h,
                  col = -1,
                })
              end
            end
          end)
        end,
      })

      -- Auto-close on CursorMoved in the source buffer
      local hover_group = vim.api.nvim_create_augroup("neodap-hover-lifecycle", { clear = true })
      state.group = hover_group

      state.autocmd_id = vim.api.nvim_create_autocmd("CursorMoved", {
        group = hover_group,
        buffer = state.source_buf,
        once = true,
        callback = function()
          state.autocmd_id = nil
          close_hover()
        end,
      })

      -- Also close if source window is closed
      vim.api.nvim_create_autocmd("WinClosed", {
        group = hover_group,
        callback = function(ev)
          local closed = tonumber(ev.match)
          if closed == state.source_win then
            close_hover()
          end
          -- Also handle tree/info windows being closed externally
          if closed == state.tree_win or closed == state.info_win then
            close_hover()
          end
        end,
      })
    end)
  end

  -- Task 1: Create variable entity
  a.run(function()
    local frame = debugger.ctx:evaluationFrame()
    if not frame then return end

    var_entity = frame:variable(expression)
    if var_entity then
      var_uri = var_entity.uri:get()
      -- Pre-fetch children for immediate tree rendering
      local ref = var_entity.variablesReference:get()
      if ref and ref > 0 then
        var_entity:fetchChildren()
      end
    end
  end, function(err)
    if err and err ~= "cancelled" then
      log:trace("hover: variable creation failed", { error = tostring(err) })
    end
    on_task_done()
  end)

  -- Task 2: Get LSP hover
  get_lsp_hover(bufnr, row, col, function(md)
    lsp_markdown = md
    on_task_done()
  end)
end

-------------------------------------------------------------------------------
-- Plugin entry point
-------------------------------------------------------------------------------

---@param debugger neodap.entities.Debugger
---@param config? HoverConfig
return function(debugger_instance, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local debugger = debugger_instance
  local group = vim.api.nvim_create_augroup("neodap-hover", { clear = true })

  -- Override K to use split-float hover when debugging
  local function setup_k_override(bufnr)
    E.keymap("n", "K", function()
      -- If hover is already open and focused, do nothing extra
      -- If hover is open but not focused, focus the tree window
      if is_hover_open() then
        if not is_hover_focused() then
          if is_valid_win(state.tree_win) then
            vim.api.nvim_set_current_win(state.tree_win)
          end
        end
        return
      end

      -- Check if we have a debug session with a stopped frame
      local frame = debugger.ctx:evaluationFrame()
      if not frame then
        -- No debug session — fall through to LSP hover
        vim.lsp.buf.hover()
        return
      end

      -- Get expression at cursor
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row, col = cursor[1] - 1, cursor[2]
      local expression = expression_utils.get_expression_at_position(bufnr, row, col)
      if not expression or expression == "" then
        vim.lsp.buf.hover()
        return
      end

      -- Open split-float hover
      open_hover(debugger, expression, bufnr, row, col)
    end, { buffer = bufnr, desc = "DAP hover / LSP hover" })
  end

  if config.auto_attach then
    -- Override K on BufEnter for normal file buffers
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      callback = function(ev)
        if vim.bo[ev.buf].buftype == "" then
          -- Schedule to run after other plugins (e.g. programming.lua LspAttach)
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(ev.buf) then
              setup_k_override(ev.buf)
            end
          end)
        end
      end,
    })

    -- Also handle LspAttach (programming.lua sets K there, we need to override)
    vim.api.nvim_create_autocmd("LspAttach", {
      group = group,
      callback = function(ev)
        -- Schedule with extra defer to run AFTER programming.lua's LspAttach
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(ev.buf) and vim.bo[ev.buf].buftype == "" then
            setup_k_override(ev.buf)
          end
        end, 10)
      end,
    })

    -- Set up current buffer immediately
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.bo[bufnr].buftype == "" then
      setup_k_override(bufnr)
    end
  end

  return {
    close = close_hover,
    is_open = is_hover_open,
  }
end
