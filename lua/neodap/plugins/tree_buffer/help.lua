-- Help float for the tree buffer
--
-- Toggles a floating window showing available keymaps.
-- Content is context-sensitive: always shows navigation keymaps,
-- plus entity-specific keymaps based on the type under the cursor.
-- Reactively updates when the cursor moves to a different entity type.

local M = {}

---------------------------------------------------------------------------
-- Help entry metadata (single source of truth)
---------------------------------------------------------------------------

--- Each entry: { key, desc, types }
--- types = nil means global (navigation), types = { "Thread", ... } means context-specific
--- @type { key: string, desc: string, types: string[]|nil }[]
local HELP_ENTRIES = {
  -- Navigation (global)
  { key = "<CR>",    desc = "Toggle expand/collapse" },
  { key = "l",       desc = "Expand or move down" },
  { key = "h",       desc = "Collapse or go to parent" },
  { key = "<Space>", desc = "Focus entity" },
  { key = "gd",      desc = "Go to source" },
  { key = "q",       desc = "Close tree" },
  { key = "R",       desc = "Refresh" },
  { key = "T",       desc = "Toggle terminated" },
  { key = "?",       desc = "Toggle help" },

  -- Thread
  { key = "c",  desc = "Continue",           types = { "Thread" } },
  { key = "p",  desc = "Pause",              types = { "Thread" } },
  { key = "n",  desc = "Step over",          types = { "Thread" } },
  { key = "s",  desc = "Step into",          types = { "Thread" } },
  { key = "S",  desc = "Step out",           types = { "Thread" } },
  { key = "gn", desc = "Step over -> source", types = { "Thread" } },
  { key = "gs", desc = "Step into -> source", types = { "Thread" } },
  { key = "gS", desc = "Step out -> source",  types = { "Thread" } },

  -- Session
  { key = "D", desc = "Disconnect", types = { "Session" } },

  -- Session + Config: terminate
  { key = "X", desc = "Terminate", types = { "Session", "Config" } },

  -- Config
  { key = "r", desc = "Restart",          types = { "Config" } },
  { key = "v", desc = "Toggle view mode", types = { "Config" } },

  -- Scope
  { key = "r", desc = "Refresh variables", types = { "Scope" } },

  -- Variable
  { key = "e", desc = "Edit value", types = { "Variable" } },
  { key = "y", desc = "Yank value", types = { "Variable" } },
  { key = "Y", desc = "Yank name",  types = { "Variable" } },

  -- Frame
  { key = "E", desc = "Evaluate in REPL", types = { "Frame" } },

  -- Stdio
  { key = "i", desc = "REPL input", types = { "Stdio" } },

  -- Breakpoint + BreakpointBinding
  { key = "t",  desc = "Toggle enabled",     types = { "Breakpoint", "BreakpointBinding", "ExceptionFilter", "ExceptionFilterBinding" } },
  { key = "dd", desc = "Remove",             types = { "Breakpoint" } },
  { key = "C",  desc = "Edit condition",     types = { "Breakpoint", "BreakpointBinding", "ExceptionFilter", "ExceptionFilterBinding" } },
  { key = "H",  desc = "Edit hit condition", types = { "Breakpoint", "BreakpointBinding" } },
  { key = "L",  desc = "Edit log message",   types = { "Breakpoint", "BreakpointBinding" } },
  { key = "x",  desc = "Clear override",     types = { "BreakpointBinding", "ExceptionFilter", "ExceptionFilterBinding" } },
}

---------------------------------------------------------------------------
-- Lookup helpers
---------------------------------------------------------------------------

-- Pre-build a desc lookup: key -> desc (first match wins, for global keys)
-- For context-sensitive keys there may be multiple entries with the same key
-- but different types. get_desc returns the first one found.
local desc_by_key = {}
for _, entry in ipairs(HELP_ENTRIES) do
  if not desc_by_key[entry.key] then
    desc_by_key[entry.key] = entry.desc
  end
end

--- Get the human-readable description for a key
---@param key string
---@return string|nil
function M.get_desc(key)
  return desc_by_key[key]
end

--- Get the types list for a key (nil = global)
---@param key string
---@return string[]|nil
function M.get_types(key)
  for _, entry in ipairs(HELP_ENTRIES) do
    if entry.key == key then
      return entry.types
    end
  end
  return nil
end

--- Get the raw HELP_ENTRIES table (for testing)
---@return table[]
function M.entries()
  return HELP_ENTRIES
end

---------------------------------------------------------------------------
-- Content building
---------------------------------------------------------------------------

-- Compute display width of a key string (accounts for angle-bracket keys)
local function key_display_width(key)
  return vim.fn.strdisplaywidth(key)
end

--- Build help content for a given entity type
---@param entity_type string|nil The entity type under cursor (nil = no entity)
---@return { lines: string[], highlights: table[] }
function M.build_content(entity_type)
  local lines = {}
  local highlights = {} -- { line (0-indexed), col_start, col_end, group }

  -- Collect global entries and entity-specific entries
  local global_entries = {}
  local type_entries = {}

  for _, entry in ipairs(HELP_ENTRIES) do
    if not entry.types then
      global_entries[#global_entries + 1] = entry
    elseif entity_type then
      for _, t in ipairs(entry.types) do
        if t == entity_type then
          type_entries[#type_entries + 1] = entry
          break
        end
      end
    end
  end

  -- Find max key width across all entries we'll show
  local max_key_w = 0
  for _, entry in ipairs(global_entries) do
    local w = key_display_width(entry.key)
    if w > max_key_w then max_key_w = w end
  end
  for _, entry in ipairs(type_entries) do
    local w = key_display_width(entry.key)
    if w > max_key_w then max_key_w = w end
  end

  local function add_section(title, entries)
    -- Section header
    local line_idx = #lines
    lines[#lines + 1] = " " .. title
    highlights[#highlights + 1] = { line_idx, 1, 1 + #title, "DapHelpSection" }

    -- Entries
    for _, entry in ipairs(entries) do
      line_idx = #lines
      local pad = string.rep(" ", max_key_w - key_display_width(entry.key))
      local line = "  " .. entry.key .. pad .. "  " .. entry.desc
      lines[#lines + 1] = line
      -- Highlight the key portion
      highlights[#highlights + 1] = { line_idx, 2, 2 + #entry.key, "DapHelpKey" }
    end
  end

  -- Navigation section (always shown)
  add_section("Navigation", global_entries)

  -- Entity-specific section
  if entity_type and #type_entries > 0 then
    -- Separator
    lines[#lines + 1] = ""
    add_section(entity_type, type_entries)
  end

  return { lines = lines, highlights = highlights }
end

---------------------------------------------------------------------------
-- Float management (singleton)
---------------------------------------------------------------------------

local state = {
  bufnr = nil,       -- help buffer
  winid = nil,       -- help window
  tree_bufnr = nil,  -- associated tree buffer
  entity_type = nil, -- last rendered entity type
  augroup = nil,     -- autocmd group id
}

local function setup_help_highlights()
  local function set(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end
  set("DapHelpKey", { link = "Special" })
  set("DapHelpSection", { link = "Title" })
  set("DapHelpSeparator", { link = "Comment" })
end

local function render_float(entity_type)
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
  if not state.winid or not vim.api.nvim_win_is_valid(state.winid) then return end

  local content = M.build_content(entity_type)
  state.entity_type = entity_type

  -- Set buffer content
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, content.lines)

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("dap-help")
  vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
  for _, hl in ipairs(content.highlights) do
    vim.api.nvim_buf_add_highlight(state.bufnr, ns, hl[4], hl[1], hl[2], hl[3])
  end

  -- Resize window to fit content
  local max_width = 0
  for _, line in ipairs(content.lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_width then max_width = w end
  end
  vim.api.nvim_win_set_height(state.winid, #content.lines)
  vim.api.nvim_win_set_width(state.winid, max_width + 2) -- +2 for padding
end

--- Close the help float
function M.close()
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end
  state.bufnr = nil
  state.winid = nil
  state.tree_bufnr = nil
  state.entity_type = nil
end

--- Update help content when entity type changes
---@param entity_type string|nil
function M.update(entity_type)
  if entity_type == state.entity_type then return end
  render_float(entity_type)
end

--- Toggle the help float for a tree buffer
---@param tree_bufnr number The tree buffer number
---@param get_entity_type fun(): string|nil Callback to get current entity type under cursor
function M.toggle(tree_bufnr, get_entity_type)
  -- If already open for this buffer, close it
  if state.tree_bufnr == tree_bufnr and state.winid and vim.api.nvim_win_is_valid(state.winid) then
    M.close()
    return
  end

  -- Close any existing float first
  M.close()

  setup_help_highlights()

  local entity_type = get_entity_type()

  -- Create help buffer
  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].bufhidden = "wipe"
  vim.bo[help_buf].buftype = "nofile"

  -- Find tree window for anchoring
  local tree_win = vim.fn.bufwinid(tree_bufnr)
  if tree_win == -1 then
    vim.api.nvim_buf_delete(help_buf, { force = true })
    return
  end

  -- Build initial content to determine size
  local content = M.build_content(entity_type)
  local max_width = 0
  for _, line in ipairs(content.lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_width then max_width = w end
  end

  -- Open float anchored to tree window top-right
  local win_width = vim.api.nvim_win_get_width(tree_win)
  local help_win = vim.api.nvim_open_win(help_buf, false, {
    relative = "win",
    win = tree_win,
    anchor = "NE",
    row = 0,
    col = win_width,
    width = max_width + 2,
    height = #content.lines,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 50,
  })

  -- Set window options
  vim.wo[help_win].winblend = 0
  vim.wo[help_win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"

  state.bufnr = help_buf
  state.winid = help_win
  state.tree_bufnr = tree_bufnr
  state.entity_type = nil -- force initial render

  -- Render initial content
  render_float(entity_type)

  -- Set up autocmds
  state.augroup = vim.api.nvim_create_augroup("neodap-help-float", { clear = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.augroup,
    buffer = tree_bufnr,
    callback = function()
      if not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
        M.close()
        return
      end
      local new_type = get_entity_type()
      M.update(new_type)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = state.augroup,
    buffer = tree_bufnr,
    callback = function()
      M.close()
    end,
  })
end

--- Get the current state (for testing)
---@return table
function M.get_state()
  return {
    bufnr = state.bufnr,
    winid = state.winid,
    tree_bufnr = state.tree_bufnr,
    entity_type = state.entity_type,
  }
end

return M
