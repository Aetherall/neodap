-- Plugin: Show breakpoints with inline virtual text at column position
-- Icons show breakpoint lifecycle: unverified → verified → adjusted → hit
-- All non-disabled icons use blue (DiagnosticInfo), hit uses yellow/orange (DiagnosticWarn)

---@class BreakpointSignsConfig
---@field icons? BreakpointSignsIcons
---@field colors? BreakpointSignsColors
---@field priority? number Extmark priority (default: 20)
---@field namespace? string Namespace name (default: "dap_breakpoints")

---@class BreakpointSignsIcons
---@field unbound? string Icon for unverified breakpoints (default: "●" solid blue circle)
---@field bound? string Icon for verified breakpoints at same location (default: "◉" fisheye)
---@field adjusted? string Icon for verified breakpoints at different location (default: "◐" half-filled)
---@field hit? string Icon for breakpoints where execution stopped (default: "◆" diamond)
---@field disabled? string Icon for disabled breakpoints (default: "○" hollow circle)

---@class BreakpointSignsColors
---@field unbound? string Highlight group for unverified (default: "DiagnosticInfo")
---@field bound? string Highlight group for verified (default: "DiagnosticInfo")
---@field adjusted? string Highlight group for adjusted (default: "DiagnosticInfo")
---@field hit? string Highlight group for hit (default: "DiagnosticWarn")
---@field disabled? string Highlight group for disabled (default: "Comment")

local default_config = {
  icons = {
    unbound = "●",   -- Solid blue circle - unverified
    bound = "◉",     -- Fisheye - verified at requested location
    adjusted = "◐",  -- Half-filled - verified but debugger adjusted position
    hit = "◆",       -- Diamond - execution stopped here
    disabled = "○",  -- Hollow circle - disabled (like commented-out code)
  },
  colors = {
    unbound = "DiagnosticInfo",   -- Blue
    bound = "DiagnosticInfo",     -- Blue
    adjusted = "DiagnosticInfo",  -- Blue (position different, still verified)
    hit = "DiagnosticWarn",       -- Yellow/orange
    disabled = "Comment",         -- Gray
  },
  priority = 20,
  namespace = "dap_breakpoints",
}

---Get buffer for a file path
---@param path string
---@return number? bufnr
local function get_buffer_for_path(path)
  -- Check if file is already loaded in a buffer
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buf_path = vim.api.nvim_buf_get_name(bufnr)
      if buf_path == path then
        return bufnr
      end
    end
  end
  return nil
end

---Setup breakpoint signs plugin
---@param debugger Debugger
---@param config? BreakpointSignsConfig
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local ns = vim.api.nvim_create_namespace(config.namespace)

  -- Define highlight groups if they don't exist
  local function setup_highlights()
    -- Create custom highlight groups that link to defaults
    vim.api.nvim_set_hl(0, "DapBreakpointUnbound", { link = config.colors.unbound, default = true })
    vim.api.nvim_set_hl(0, "DapBreakpointBound", { link = config.colors.bound, default = true })
    vim.api.nvim_set_hl(0, "DapBreakpointAdjusted", { link = config.colors.adjusted, default = true })
    vim.api.nvim_set_hl(0, "DapBreakpointHit", { link = config.colors.hit, default = true })
    vim.api.nvim_set_hl(0, "DapBreakpointDisabled", { link = config.colors.disabled, default = true })
  end

  setup_highlights()

  -- Track extmarks per breakpoint
  -- sign_id: for the sign in the sign column
  -- column_id: for inline highlight at column position (optional)
  local extmarks = {} -- breakpoint.id -> { bufnr, sign_id, column_id? }

  ---Determine the display state for a breakpoint
  ---@param breakpoint Breakpoint
  ---@return string state, number? adjusted_line, number? adjusted_column
  local function get_display_state(breakpoint)
    local state = breakpoint.state:get()

    -- Check if any binding has an adjusted line or column
    local adjusted_line = nil
    local adjusted_column = nil
    if state == "bound" or state == "hit" then
      for binding in breakpoint.bindings:iter() do
        local actual_line = binding.actualLine:get()
        local actual_col = binding.actualColumn:get()
        if actual_line and actual_line ~= breakpoint.line then
          adjusted_line = actual_line
        end
        if actual_col and actual_col ~= breakpoint.column then
          adjusted_column = actual_col
        end
        if adjusted_line or adjusted_column then
          break
        end
      end
    end

    -- If line or column was adjusted, show adjusted state (unless hit)
    if (adjusted_line or adjusted_column) and state ~= "hit" then
      return "adjusted", adjusted_line, adjusted_column
    end

    return state, adjusted_line, adjusted_column
  end

  ---Get icon and highlight for a state
  ---@param state string
  ---@param enabled boolean
  ---@return string icon, string hl_group
  local function get_icon_and_hl(state, enabled)
    if not enabled then
      return config.icons.disabled, "DapBreakpointDisabled"
    end

    local icons = config.icons
    local hl_map = {
      unbound = "DapBreakpointUnbound",
      bound = "DapBreakpointBound",
      adjusted = "DapBreakpointAdjusted",
      hit = "DapBreakpointHit",
    }

    return icons[state] or icons.unbound, hl_map[state] or "DapBreakpointUnbound"
  end

  ---Update or create extmark for a breakpoint
  ---@param breakpoint Breakpoint
  local function update_sign(breakpoint)
    local path = breakpoint.source.path
    if not path then return end

    local bufnr = get_buffer_for_path(path)
    if not bufnr then return end

    -- Get display state
    local state, adjusted_line, adjusted_column = get_display_state(breakpoint)
    local enabled = breakpoint.enabled and breakpoint.enabled:get() or true
    local icon, hl_group = get_icon_and_hl(state, enabled)

    -- Use adjusted line/column if available, otherwise original
    local display_line = adjusted_line or breakpoint.line
    local display_column = adjusted_column or breakpoint.column or 1

    -- Remove old extmark if it exists
    local old = extmarks[breakpoint.id]
    if old then
      pcall(vim.api.nvim_buf_del_extmark, old.bufnr, ns, old.extmark_id)
    end

    -- Create new extmark (line is 0-indexed for extmarks)
    local line_idx = display_line - 1
    if line_idx < 0 then line_idx = 0 end

    -- Ensure line exists in buffer
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if line_idx >= line_count then
      line_idx = line_count - 1
    end

    -- Column is 1-indexed in DAP, 0-indexed for extmarks
    local col_idx = display_column - 1
    if col_idx < 0 then col_idx = 0 end

    -- Get the line content to validate column
    local lines = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)
    local line_content = lines[1] or ""

    -- Clamp column to line length
    if col_idx > #line_content then
      col_idx = #line_content
    end

    -- Create virtual text at the column position
    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, col_idx, {
      virt_text = { { icon, hl_group } },
      virt_text_pos = "inline",
      priority = config.priority,
    })

    extmarks[breakpoint.id] = {
      bufnr = bufnr,
      extmark_id = extmark_id,
    }
  end

  ---Remove sign for a breakpoint
  ---@param breakpoint Breakpoint
  local function remove_sign(breakpoint)
    local old = extmarks[breakpoint.id]
    if old then
      pcall(vim.api.nvim_buf_del_extmark, old.bufnr, ns, old.extmark_id)
      extmarks[breakpoint.id] = nil
    end
  end

  -- Watch for breakpoints
  debugger:onBreakpoint(function(breakpoint)
    -- Initial sign
    vim.schedule(function()
      update_sign(breakpoint)
    end)

    -- Watch state changes
    breakpoint.state:watch(function()
      vim.schedule(function()
        update_sign(breakpoint)
      end)
    end)

    -- Watch for enabled changes (if exists)
    if breakpoint.enabled then
      breakpoint.enabled:watch(function()
        vim.schedule(function()
          update_sign(breakpoint)
        end)
      end)
    end

    -- Watch bindings for actualLine and actualColumn changes
    breakpoint:onBinding(function(binding)
      binding.actualLine:watch(function()
        vim.schedule(function()
          update_sign(breakpoint)
        end)
      end)
      binding.actualColumn:watch(function()
        vim.schedule(function()
          update_sign(breakpoint)
        end)
      end)
    end)

    -- Remove sign when breakpoint is disposed
    breakpoint:on_dispose(function()
      vim.schedule(function()
        remove_sign(breakpoint)
      end)
    end)
  end)

  -- Also update signs when buffers are loaded (for breakpoints set before file was opened)
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = vim.api.nvim_create_augroup("DapBreakpointSigns", { clear = true }),
    callback = function(ev)
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path == "" then return end

      -- Update signs for all breakpoints in this file using indexed View
      local view = debugger:view("breakpoint"):where("by_source_path", path)
      for bp in view:iter() do
        vim.schedule(function()
          update_sign(bp)
        end)
      end
      view:dispose()
    end,
  })

  -- Return cleanup function
  return function()
    -- Remove all extmarks
    for _, mark in pairs(extmarks) do
      pcall(vim.api.nvim_buf_del_extmark, mark.bufnr, ns, mark.extmark_id)
    end
    extmarks = {}

    -- Remove autocmd group
    pcall(vim.api.nvim_del_augroup_by_name, "DapBreakpointSigns")
  end
end
