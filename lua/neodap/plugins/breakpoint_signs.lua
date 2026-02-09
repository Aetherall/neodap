-- Plugin: Show breakpoints with inline virtual text
-- Subscribes to breakpoint rollups (enabled, hitBinding, verifiedBinding) for reactive updates

local Location = require("neodap.location")
local navigate = require("neodap.plugins.utils.navigate")
local get_buffer_for_path = navigate.get_buffer_for_path

local default_icons = {
  unbound = "●",
  bound = "◉",
  adjusted = "◐",
  hit = "◆",
  disabled = "○",
}

local default_colors = {
  unbound = "DiagnosticInfo",
  bound = "DiagnosticInfo",
  adjusted = "DiagnosticInfo",
  hit = "DiagnosticWarn",
  disabled = "Comment",
}

---@param debugger neodap.entities.Debugger
---@param config? table
return function(debugger, config)
  config = config or {}
  local icons = vim.tbl_extend("force", default_icons, config.icons or {})
  local colors = vim.tbl_extend("force", default_colors, config.colors or {})
  local priority = config.priority or 20
  local ns = vim.api.nvim_create_namespace(config.namespace or "neodap_breakpoint_signs")

  -- Setup highlight groups
  vim.api.nvim_set_hl(0, "DapBreakpointUnbound", { link = colors.unbound, default = true })
  vim.api.nvim_set_hl(0, "DapBreakpointBound", { link = colors.bound, default = true })
  vim.api.nvim_set_hl(0, "DapBreakpointAdjusted", { link = colors.adjusted, default = true })
  vim.api.nvim_set_hl(0, "DapBreakpointHit", { link = colors.hit, default = true })
  vim.api.nvim_set_hl(0, "DapBreakpointDisabled", { link = colors.disabled, default = true })

  local hl_groups = {
    unbound = "DapBreakpointUnbound",
    bound = "DapBreakpointBound",
    adjusted = "DapBreakpointAdjusted",
    hit = "DapBreakpointHit",
    disabled = "DapBreakpointDisabled",
  }

  ---Place extmark for a mark
  local function placeExtmark(bufnr, mark)
    if not mark then return nil end

    local icon = icons[mark.state]
    local hl = hl_groups[mark.state]

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local line_idx = math.max(0, math.min(mark.line - 1, line_count - 1))

    local lines = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)
    local line_text = lines[1] or ""

    -- Place at first non-whitespace character so the sign is visible
    -- (placing at column 0 hides it in indentation)
    local col_idx = line_text:find("%S")
    if col_idx then
      col_idx = col_idx - 1 -- convert to 0-based
    else
      col_idx = #line_text -- empty/whitespace-only line: place at end
    end

    return vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, col_idx, {
      virt_text = { { icon, hl } },
      virt_text_pos = "inline",
      priority = priority,
    })
  end

  -- Track which breakpoints have subscriptions (to avoid duplicates on buffer load)
  local subscribed = {}

  ---Subscribe a breakpoint to rollups for a specific buffer
  ---@param bp any Breakpoint entity
  ---@param bufnr number Buffer number
  local function subscribe_bp_mark(bp, bufnr)
    local bp_id = bp:id()
    if subscribed[bp_id] then return end
    subscribed[bp_id] = true

    local current_extmark_id = nil

    local function update()
      -- Remove old extmark
      if current_extmark_id then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, current_extmark_id)
        current_extmark_id = nil
      end
      -- Place new one based on current state
      local mark = bp:getMark()
      if mark then
        current_extmark_id = placeExtmark(bufnr, mark)
      end
    end

    -- Initial placement
    update()

    -- Subscribe to enabled
    bp.enabled:use(function() update() end)

    -- Subscribe to hitBinding rollup (nested :use() auto-cleaned on change)
    bp.hitBinding:use(function(binding)
      update()
      if binding then
        binding.actualLine:use(function() update() end)
        binding.actualColumn:use(function() update() end)
      end
    end)

    -- Subscribe to verifiedBinding rollup (nested :use() auto-cleaned on change)
    bp.verifiedBinding:use(function(binding)
      update()
      if binding then
        binding.actualLine:use(function() update() end)
        binding.actualColumn:use(function() update() end)
      end
    end)

    -- Return cleanup function (called when bp is deleted)
    return function()
      -- Subscriptions are auto-cleaned by scope, just remove extmark
      if current_extmark_id then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, current_extmark_id)
      end
    end
  end

  -- Subscribe to breakpoints (auto-scoped via debugger:use())
  debugger.breakpoints:each(function(bp)
    local mark = bp:getMark()
    local cleanup_fn = nil
    if mark and mark.path then
      local bufnr = get_buffer_for_path(mark.path)
      if bufnr then
        cleanup_fn = subscribe_bp_mark(bp, bufnr)
      end
    end

    -- Cleanup tracking when bp removed
    return function()
      subscribed[bp:id()] = nil
      if cleanup_fn then cleanup_fn() end
    end
  end)

  -- Handle buffer loads - subscribe breakpoints when their file is opened
  local augroup = vim.api.nvim_create_augroup("NeodapBreakpointSigns", { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    callback = function(ev)
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path == "" then return end

      for bp in debugger:breakpointsAt(Location.new(path)) do
        subscribe_bp_mark(bp, ev.buf)
      end
    end,
  })

  return {}
end
