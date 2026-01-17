-- Plugin: DapException command for managing exception breakpoints

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  local api = {}

  ---Get focused session or first session
  ---@return neodap.entities.Session?
  local function get_session()
    -- focusedSession() is a method returning a signal, firstSession is a rollup (also a signal)
    return debugger.ctx.session:get() or debugger.firstSession:get()
  end

  ---Toggle exception filter by ID
  ---@param filter_id string Filter ID (e.g., "uncaught", "raised")
  ---@return boolean success
  function api.toggle(filter_id)
    local session = get_session()
    if not session then return false end

    for ef in session.exceptionFilters:iter() do
      if ef.filterId:get() == filter_id then
        ef:toggle()
        session:syncExceptionFilters()
        return true
      end
    end
    return false
  end

  ---Enable exception filter by ID
  ---@param filter_id string Filter ID
  ---@param condition? string Optional condition
  ---@return boolean success
  function api.enable(filter_id, condition)
    local session = get_session()
    if not session then return false end

    for ef in session.exceptionFilters:iter() do
      if ef.filterId:get() == filter_id then
        ef:update({ enabled = true, condition = condition })
        session:syncExceptionFilters()
        return true
      end
    end
    return false
  end

  ---Disable exception filter by ID
  ---@param filter_id string Filter ID
  ---@return boolean success
  function api.disable(filter_id)
    local session = get_session()
    if not session then return false end

    for ef in session.exceptionFilters:iter() do
      if ef.filterId:get() == filter_id then
        ef:update({ enabled = false })
        session:syncExceptionFilters()
        return true
      end
    end
    return false
  end

  ---Set condition on exception filter
  ---@param filter_id string Filter ID
  ---@param condition string Condition expression
  ---@return boolean success
  function api.set_condition(filter_id, condition)
    local session = get_session()
    if not session then return false end

    for ef in session.exceptionFilters:iter() do
      if ef.filterId:get() == filter_id then
        ef:update({ condition = condition })
        session:syncExceptionFilters()
        return true
      end
    end
    return false
  end

  ---List all exception filters for current session
  ---@return table[] filters Array of { id, label, enabled, condition }
  function api.list()
    local session = get_session()
    if not session then return {} end

    local result = {}
    for ef in session.exceptionFilters:iter() do
      table.insert(result, {
        id = ef.filterId:get(),
        label = ef.label:get(),
        description = ef.description:get(),
        enabled = ef:isEnabled(),
        condition = ef.condition:get(),
        supportsCondition = ef.supportsCondition:get(),
      })
    end
    return result
  end

  vim.api.nvim_create_user_command("DapException", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local subcommand = args[1]

    if not subcommand then
      -- List all filters
      local filters = api.list()
      if #filters == 0 then
        vim.notify("No exception filters available", vim.log.levels.INFO)
        return
      end

      local lines = { "Exception Filters:" }
      for _, f in ipairs(filters) do
        local status = f.enabled and "[x]" or "[ ]"
        local cond = f.condition and (" if " .. f.condition) or ""
        table.insert(lines, string.format("  %s %s: %s%s", status, f.id, f.label, cond))
      end
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
      return
    end

    if subcommand == "toggle" then
      local filter_id = args[2]
      if not filter_id then
        vim.notify("DapException: toggle requires filter ID", vim.log.levels.ERROR)
        return
      end
      if not api.toggle(filter_id) then
        vim.notify("DapException: filter not found: " .. filter_id, vim.log.levels.ERROR)
      end

    elseif subcommand == "enable" then
      local filter_id = args[2]
      if not filter_id then
        vim.notify("DapException: enable requires filter ID", vim.log.levels.ERROR)
        return
      end
      local condition = args[3] and table.concat(vim.list_slice(args, 3), " ") or nil
      if not api.enable(filter_id, condition) then
        vim.notify("DapException: filter not found: " .. filter_id, vim.log.levels.ERROR)
      end

    elseif subcommand == "disable" then
      local filter_id = args[2]
      if not filter_id then
        vim.notify("DapException: disable requires filter ID", vim.log.levels.ERROR)
        return
      end
      if not api.disable(filter_id) then
        vim.notify("DapException: filter not found: " .. filter_id, vim.log.levels.ERROR)
      end

    elseif subcommand == "condition" then
      local filter_id = args[2]
      local condition = args[3] and table.concat(vim.list_slice(args, 3), " ") or nil
      if not filter_id or not condition then
        vim.notify("DapException: condition requires filter ID and expression", vim.log.levels.ERROR)
        return
      end
      if not api.set_condition(filter_id, condition) then
        vim.notify("DapException: filter not found: " .. filter_id, vim.log.levels.ERROR)
      end

    else
      vim.notify("DapException: unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    desc = "Manage exception breakpoints",
    complete = function(arglead, cmdline)
      local args = vim.split(cmdline, "%s+", { trimempty = true })
      if #args <= 2 then
        local cmds = { "toggle", "enable", "disable", "condition" }
        return vim.tbl_filter(function(cmd)
          return cmd:match("^" .. vim.pesc(arglead))
        end, cmds)
      elseif #args == 3 then
        -- Complete filter IDs
        local filters = api.list()
        local ids = vim.tbl_map(function(f) return f.id end, filters)
        return vim.tbl_filter(function(id)
          return id:match("^" .. vim.pesc(arglead))
        end, ids)
      end
      return {}
    end,
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapException")
  end

  return api
end
