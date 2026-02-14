-- Plugin: DapException command for managing exception breakpoints
-- Supports both session-specific bindings and global default toggles
local log = require("neodap.logger")

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

  ---Find global filter by ID
  ---@param filter_id string
  ---@return neodap.entities.ExceptionFilter?
  local function find_global_filter(filter_id)
    for ef in debugger.exceptionFilters:filter({
      filters = {{ field = "filterId", op = "eq", value = filter_id }}
    }):iter() do
      return ef
    end
    return nil
  end

  ---Find binding by filter ID, apply mutation, sync.
  ---@param filter_id string
  ---@param mutate fun(binding: neodap.entities.ExceptionFilterBinding)
  ---@return boolean success
  local function with_binding(filter_id, mutate)
    local session = get_session()
    if not session then return false end
    local binding = session:findExceptionFilterBinding(filter_id)
    if not binding then return false end
    mutate(binding)
    session:syncExceptionFilters()
    return true
  end

  function api.toggle(filter_id)
    return with_binding(filter_id, function(b) b:toggle() end)
  end

  function api.toggle_global(filter_id)
    local ef = find_global_filter(filter_id)
    if not ef then return false end
    ef:toggle()
    ef:syncAllSessions()
    return true
  end

  function api.enable(filter_id, condition)
    return with_binding(filter_id, function(b) b:update({ enabled = true, condition = condition }) end)
  end

  function api.disable(filter_id)
    return with_binding(filter_id, function(b) b:update({ enabled = false }) end)
  end

  function api.clear(filter_id)
    return with_binding(filter_id, function(b) b:clearOverride() end)
  end

  function api.set_condition(filter_id, condition)
    return with_binding(filter_id, function(b) b:update({ condition = condition }) end)
  end

  ---List all exception filters for current session
  ---@return table[] filters Array of { id, label, enabled, hasOverride, condition }
  function api.list()
    local session = get_session()
    if not session then return {} end

    local result = {}
    for binding in session.exceptionFilterBindings:iter() do
      local ef = binding.exceptionFilter:get()
      if ef then
        table.insert(result, {
          id = ef.filterId:get(),
          label = ef.label:get(),
          description = ef.description:get(),
          enabled = binding:getEffectiveEnabled(),
          hasOverride = binding:hasOverride(),
          condition = binding.condition:get(),
          supportsCondition = ef.supportsCondition:get(),
          globalDefault = ef.defaultEnabled:get() or false,
        })
      end
    end
    return result
  end

  vim.api.nvim_create_user_command("DapException", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local subcommand = args[1]
    local is_bang = opts.bang

    if not subcommand then
      -- List all filters
      local session = get_session()
      if not session then
        log:info("No exception filters available")
        return
      end

      local lines = { "Exception Filters:" }
      local count = 0
      for binding in session.exceptionFilterBindings:iter() do
        local ef = binding.exceptionFilter:get()
        if ef then
          count = count + 1
          local id = debugger:render_text(ef, { "filter_id" })
          local display = debugger:render_text(binding, { "icon", { "title", prefix = " " }, { "condition", prefix = " if " } })
          table.insert(lines, string.format("  %s %s", id, display))
        end
      end

      if count == 0 then
        log:info("No exception filters available")
        return
      end

      log:info("Exception filters", { filters = table.concat(lines, "\n") })
      return
    end

    if subcommand == "toggle" then
      local filter_id = args[2]
      if not filter_id then
        log:error("DapException: toggle requires filter ID")
        return
      end
      local success
      if is_bang then
        -- toggle! toggles global default
        success = api.toggle_global(filter_id)
      else
        -- toggle affects session binding
        success = api.toggle(filter_id)
      end
      if not success then
        log:error("DapException: filter not found", { filter_id = filter_id })
      end

    elseif subcommand == "enable" then
      local filter_id = args[2]
      if not filter_id then
        log:error("DapException: enable requires filter ID")
        return
      end
      local condition = args[3] and table.concat(vim.list_slice(args, 3), " ") or nil
      if not api.enable(filter_id, condition) then
        log:error("DapException: filter not found", { filter_id = filter_id })
      end

    elseif subcommand == "disable" then
      local filter_id = args[2]
      if not filter_id then
        log:error("DapException: disable requires filter ID")
        return
      end
      if not api.disable(filter_id) then
        log:error("DapException: filter not found", { filter_id = filter_id })
      end

    elseif subcommand == "clear" then
      local filter_id = args[2]
      if not filter_id then
        log:error("DapException: clear requires filter ID")
        return
      end
      if not api.clear(filter_id) then
        log:error("DapException: filter not found", { filter_id = filter_id })
      end

    elseif subcommand == "condition" then
      local filter_id = args[2]
      local condition = args[3] and table.concat(vim.list_slice(args, 3), " ") or nil
      if not filter_id or not condition then
        log:error("DapException: condition requires filter ID and expression")
        return
      end
      if not api.set_condition(filter_id, condition) then
        log:error("DapException: filter not found", { filter_id = filter_id })
      end

    else
      log:error("DapException: unknown subcommand", { subcommand = subcommand })
    end
  end, {
    nargs = "*",
    bang = true,
    desc = "Manage exception breakpoints (use ! for global toggle)",
    complete = function(arglead, cmdline)
      local args = vim.split(cmdline, "%s+", { trimempty = true })
      if #args <= 2 then
        local cmds = { "toggle", "enable", "disable", "clear", "condition" }
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
