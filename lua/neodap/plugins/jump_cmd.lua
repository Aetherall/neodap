---jump_cmd plugin for neodap
---Provides :DapJump command to navigate to frame locations
---
---Usage:
---  :DapJump                  - Jump to currently focused frame
---  :DapJump @frame+1         - Jump to caller frame
---  :DapJump @thread/stacks[0]/frames - Pick frame to jump to
---  :DapJump frame:abc:123    - Jump to frame by URI
---
---Window picker integration:
---  require("neodap.plugins.jump_cmd")(debugger, {
---    select_jump_window = require("window-picker").pick_window,
---    strategy = "ask_on_winfixbuf",
---  })

local url_completion = require("neodap.plugins.utils.url_completion")
local uri_picker = require("neodap.plugins.uri_picker")

---@class neodap.plugins.DapJumpConfig
---@field select_jump_window? fun(): number? Function to select a window (e.g., nvim-window-picker)
---@field strategy? "always_ask"|"ask_on_winfixbuf"|"silent"|"error" Window selection strategy (default: "error")

---@param debugger neodap.entities.Debugger
---@param config? neodap.plugins.DapJumpConfig
---@return table api Plugin API
local function dap_jump(debugger, config)
  config = config or {}
  local strategy = config.strategy or "error"

  local picker = uri_picker(debugger)
  local api = {}

  ---Select a window for jumping, returns nil if cancelled or not possible
  ---@return number? win_id
  local function select_window()
    if not config.select_jump_window then
      return nil
    end

    -- Keep asking until user picks a non-winfixbuf window or cancels
    while true do
      local win = config.select_jump_window()
      if not win then
        return nil -- User cancelled
      end
      if not vim.wo[win].winfixbuf then
        return win
      end
      -- Selected window also has winfixbuf, ask again
    end
  end

  ---Jump to a frame's source location
  ---@param frame any Frame entity
  ---@return boolean success
  local function jump_to_frame(frame)
    if not frame then
      return false
    end

    local loc = frame:location()
    if not loc then
      vim.notify("Frame has no source location", vim.log.levels.WARN)
      return false
    end

    local path = loc.path
    local line = loc.line or 1
    local column = loc.column or 0

    -- Handle window selection based on strategy
    local win = vim.api.nvim_get_current_win()
    local current_is_fixed = vim.wo[win].winfixbuf

    if strategy == "always_ask" then
      local target = select_window()
      if not target then
        return false -- User cancelled or no select_jump_window configured
      end
      vim.api.nvim_set_current_win(target)
    elseif current_is_fixed then
      if strategy == "ask_on_winfixbuf" then
        local target = select_window()
        if not target then
          return false -- User cancelled or no select_jump_window configured
        end
        vim.api.nvim_set_current_win(target)
      elseif strategy == "silent" then
        return false
      else -- "error"
        vim.notify("DapJump: Current window has winfixbuf set", vim.log.levels.ERROR)
        return false
      end
    end

    -- For virtual sources (dap://), store pending position for source_buffer to use after loading
    local is_virtual = path:match("^dap://")
    if is_virtual then
      -- Store position before opening (buffer doesn't exist yet)
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      -- Set pending position for source_buffer to apply after content loads
      vim.b.dap_pending_cursor = { line = line, col = math.max(0, column - 1) }
      return true
    end

    -- Open file and jump to location
    vim.cmd("edit " .. vim.fn.fnameescape(path))

    -- Clamp line and column to buffer bounds
    local line_count = vim.api.nvim_buf_line_count(0)
    local safe_line = math.max(1, math.min(line, line_count))
    local line_text = vim.api.nvim_buf_get_lines(0, safe_line - 1, safe_line, false)[1] or ""
    local safe_col = math.max(0, math.min(column - 1, #line_text))
    vim.api.nvim_win_set_cursor(0, { safe_line, safe_col })

    -- Center the view
    vim.cmd("normal! zz")

    return true
  end

  ---Jump to a frame by URL or URI (shows picker if multiple results)
  ---@param target string URL path like "@frame" or URI like "frame:abc:123"
  ---@param callback? fun(success: boolean) Optional callback for async picker
  function api.jump(target, callback)
    if not target or target == "" then
      vim.notify("Usage: DapJump <url|uri>", vim.log.levels.ERROR)
      if callback then callback(false) end
      return
    end

    picker:resolve(target, function(frame)
      if not frame then
        vim.notify("Could not resolve: " .. target, vim.log.levels.ERROR)
        if callback then callback(false) end
        return
      end

      -- Verify it's a frame by checking entity type
      if frame:type() ~= "Frame" then
        vim.notify("Target is not a frame: " .. target, vim.log.levels.ERROR)
        if callback then callback(false) end
        return
      end

      local success = jump_to_frame(frame)
      if callback then callback(success) end
    end)
  end

  ---Jump to currently focused frame
  ---@return boolean success
  function api.jump_to_current()
    return api.jump("@frame")
  end

  -- Create user command
  vim.api.nvim_create_user_command("DapJump", function(opts)
    local target = opts.args
    if target == "" then
      target = "@frame"
    end
    api.jump(target)
  end, {
    nargs = "?",
    desc = "Jump to frame location",
    complete = function(arglead, cmdline)
      -- Special frame navigation patterns
      local specials = { "@frame", "@frame+1", "@frame-1" }

      -- Get schema-based completions
      local partial = cmdline:match("DapJump%s+(.*)$") or ""
      local schema_completions = url_completion.complete(debugger, partial)

      -- Combine and filter
      local all = vim.list_extend(vim.deepcopy(specials), schema_completions)
      return vim.tbl_filter(function(c)
        return c:match("^" .. vim.pesc(arglead))
      end, all)
    end,
  })

  ---Cleanup function
  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapJump")
  end

  return api
end

return dap_jump
