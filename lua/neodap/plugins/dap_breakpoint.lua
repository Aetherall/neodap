-- Plugin: DapBreakpoint command for managing breakpoints with column-aware targeting
-- Uses breakpointLocations DAP request to snap to nearest valid breakpoint position

---@class DapBreakpointConfig
---@field select_breakpoint? fun(breakpoints: Breakpoint[]): Breakpoint? Function to select from multiple breakpoints
---@field adjust? fun(debugger: Debugger, source: table, line: number, column: number): number, number Function to adjust cursor position to valid breakpoint location

---Default adjust function: query breakpointLocations for closest location, fallback to column 1
---@param debugger Debugger
---@param source table
---@param line number (1-indexed)
---@param column number (1-indexed)
---@return number line, number column (1-indexed)
local function default_adjust(debugger, source, line, column)
  -- Query breakpointLocations from any active session
  -- API uses 0-indexed positions, returns 0-indexed results
  local err, locations = debugger:breakpointLocations(source, { line - 1, column - 1 })

  if err or not locations or #locations == 0 then
    -- No session or no valid locations on this line - fallback to column 1
    return line, 1
  end

  -- Find closest location to cursor
  local closest_loc = nil
  local closest_dist = math.huge

  for _, loc in ipairs(locations) do
    -- loc.pos is {line, col} 0-indexed
    local loc_line = loc.pos[1] + 1  -- Convert to 1-indexed
    local loc_col = loc.pos[2] + 1

    -- Only consider locations on the same line
    if loc_line == line then
      local dist = math.abs(loc_col - column)
      if dist < closest_dist then
        closest_dist = dist
        closest_loc = loc
      end
    end
  end

  if closest_loc then
    return closest_loc.pos[1] + 1, closest_loc.pos[2] + 1
  end

  -- No locations on this exact line, fallback to column 1
  return line, 1
end

---@param debugger Debugger
---@param config? DapBreakpointConfig
---@return function cleanup
return function(debugger, config)
  config = config or {}
  local adjust = config.adjust or default_adjust

  ---Parse target string to get source, line, and column
  ---@param target? string
  ---@return { source: table, line: number, column: number, skip_adjust?: boolean }?, Breakpoint?
  local function resolve_target(target)
    local bufnr = vim.api.nvim_get_current_buf()
    local buf_path = vim.api.nvim_buf_get_name(bufnr)

    if not target or target == "" then
      -- Current cursor position (col is 0-indexed in Neovim, convert to 1-indexed)
      local pos = vim.api.nvim_win_get_cursor(0)
      return { source = { path = buf_path }, line = pos[1], column = pos[2] + 1 }
    end

    -- Check if it's a breakpoint URI
    if target:match("^dap:breakpoint:") then
      local bp = debugger.breakpoints:get_one("by_uri", target)
      return nil, bp
    end

    -- Check for line:col format (explicit = skip adjustment)
    local line, col = target:match("^(%d+):(%d+)$")
    if line then
      return { source = { path = buf_path }, line = tonumber(line), column = tonumber(col), skip_adjust = true }
    end

    -- Just line number (use column 1, skip adjustment)
    line = target:match("^(%d+)$")
    if line then
      return { source = { path = buf_path }, line = tonumber(line), column = 1, skip_adjust = true }
    end

    return nil, nil
  end

  ---Find breakpoint at exact location (column-aware)
  ---@param source table
  ---@param line number
  ---@param column number
  ---@return Breakpoint?
  local function find_breakpoint_exact(source, line, column)
    local location_key = source.path .. ":" .. line .. ":" .. column
    return debugger.breakpoints:get_one("by_location", location_key)
  end

  ---Find breakpoint by actual binding location (where debugger placed it)
  ---@param source table
  ---@param line number
  ---@param column number
  ---@return Breakpoint?
  local function find_breakpoint_by_binding(source, line, column)
    for bp in debugger.breakpoints:iter() do
      if bp.source.path == source.path then
        for binding in bp.bindings:iter() do
          local actual_line = binding.actualLine:get() or bp.line
          local actual_col = binding.actualColumn:get() or bp.column or 1
          if actual_line == line and actual_col == column then
            return bp
          end
        end
      end
    end
    return nil
  end

  ---Find breakpoint at location (check both breakpoint position and binding actual position)
  ---@param source table
  ---@param line number
  ---@param column number
  ---@return Breakpoint?
  local function find_breakpoint_at_location(source, line, column)
    -- First check breakpoint's own position
    local bp = find_breakpoint_exact(source, line, column)
    if bp then return bp end

    -- Then check if any binding has this as its actual location
    return find_breakpoint_by_binding(source, line, column)
  end

  ---Get or create breakpoint at location
  ---@param source table
  ---@param line number
  ---@param column number
  ---@return Breakpoint
  local function get_or_create_breakpoint(source, line, column)
    local existing = find_breakpoint_at_location(source, line, column)
    if existing then return existing end
    return debugger:add_breakpoint(source, line, { column = column })
  end

  ---Perform toggle at a location
  ---@param location { source: table, line: number, column: number, skip_adjust?: boolean }
  local function do_toggle(location)
    local line, column = location.line, location.column

    -- Adjust location unless skipped (explicit line:col format)
    if not location.skip_adjust then
      line, column = adjust(debugger, location.source, line, column)
    end

    -- Check for existing breakpoint at adjusted location
    local existing = find_breakpoint_at_location(location.source, line, column)
    if existing then
      debugger:remove_breakpoint(existing)
    else
      debugger:add_breakpoint(location.source, line, { column = column })
    end
  end

  vim.api.nvim_create_user_command("DapBreakpoint", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local subcommand = args[1]

    -- No args = toggle at cursor
    if not subcommand or subcommand:match("^%d") then
      -- First arg is a number (line target), treat as toggle
      local target = subcommand
      local location, bp = resolve_target(target)

      if bp then
        debugger:remove_breakpoint(bp)
        return
      end

      if not location then
        vim.notify("DapBreakpoint: Invalid target", vim.log.levels.ERROR)
        return
      end

      do_toggle(location)
      return
    end

    -- Handle subcommands
    if subcommand == "toggle" then
      local target = args[2]
      local location, bp = resolve_target(target)

      if bp then
        debugger:remove_breakpoint(bp)
        return
      end

      if not location then
        vim.notify("DapBreakpoint: Invalid target", vim.log.levels.ERROR)
        return
      end

      do_toggle(location)

    elseif subcommand == "condition" then
      -- Check if second arg is a line number
      local target, value_start
      if args[2] and args[2]:match("^%d+:?%d*$") then
        target = args[2]
        value_start = 3
      else
        target = nil
        value_start = 2
      end

      local value = table.concat(vim.list_slice(args, value_start), " ")
      if value == "" then
        vim.notify("DapBreakpoint: condition requires an expression", vim.log.levels.ERROR)
        return
      end

      local location, bp = resolve_target(target)
      if bp then
        bp.condition:set(value)
      elseif location then
        local line, column = location.line, location.column
        if not location.skip_adjust then
          line, column = adjust(debugger, location.source, line, column)
        end
        local breakpoint = get_or_create_breakpoint(location.source, line, column)
        breakpoint.condition:set(value)
      else
        vim.notify("DapBreakpoint: Invalid target", vim.log.levels.ERROR)
      end

    elseif subcommand == "log" then
      -- Check if second arg is a line number
      local target, value_start
      if args[2] and args[2]:match("^%d+:?%d*$") then
        target = args[2]
        value_start = 3
      else
        target = nil
        value_start = 2
      end

      local value = table.concat(vim.list_slice(args, value_start), " ")
      if value == "" then
        vim.notify("DapBreakpoint: log requires a message", vim.log.levels.ERROR)
        return
      end

      local location, bp = resolve_target(target)
      if bp then
        bp.logMessage:set(value)
      elseif location then
        local line, column = location.line, location.column
        if not location.skip_adjust then
          line, column = adjust(debugger, location.source, line, column)
        end
        local breakpoint = get_or_create_breakpoint(location.source, line, column)
        breakpoint.logMessage:set(value)
      else
        vim.notify("DapBreakpoint: Invalid target", vim.log.levels.ERROR)
      end

    elseif subcommand == "enable" then
      local target = args[2]
      local location, bp = resolve_target(target)

      if bp then
        bp:enable()
      elseif location then
        local line, column = location.line, location.column
        if not location.skip_adjust then
          line, column = adjust(debugger, location.source, line, column)
        end
        local existing = find_breakpoint_at_location(location.source, line, column)
        if existing then
          existing:enable()
        else
          vim.notify("DapBreakpoint: No breakpoint at this location", vim.log.levels.ERROR)
        end
      else
        vim.notify("DapBreakpoint: Invalid target", vim.log.levels.ERROR)
      end

    elseif subcommand == "disable" then
      local target = args[2]
      local location, bp = resolve_target(target)

      if bp then
        bp:disable()
      elseif location then
        local line, column = location.line, location.column
        if not location.skip_adjust then
          line, column = adjust(debugger, location.source, line, column)
        end
        local existing = find_breakpoint_at_location(location.source, line, column)
        if existing then
          existing:disable()
        else
          vim.notify("DapBreakpoint: No breakpoint at this location", vim.log.levels.ERROR)
        end
      else
        vim.notify("DapBreakpoint: Invalid target", vim.log.levels.ERROR)
      end

    else
      vim.notify("DapBreakpoint: Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    desc = "Manage DAP breakpoints",
    complete = function(arglead, cmdline, cursorpos)
      local args = vim.split(cmdline, "%s+", { trimempty = true })
      if #args <= 2 then
        return vim.tbl_filter(function(cmd)
          return cmd:match("^" .. vim.pesc(arglead))
        end, { "toggle", "condition", "log", "enable", "disable" })
      end
      return {}
    end,
  })

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    pcall(vim.api.nvim_del_user_command, "DapBreakpoint")
  end)

  -- Return manual cleanup function
  return function()
    pcall(vim.api.nvim_del_user_command, "DapBreakpoint")
  end
end
