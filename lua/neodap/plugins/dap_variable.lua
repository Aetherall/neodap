-- Plugin: DapVariable command for editing variables with picker
-- Usage: :DapVariable [uri_pattern]
-- Without args: picks from @frame/scope:*/variable:* (current frame's variables)
-- With args: resolves the given URI pattern

local neostate = require("neostate")

---Format a variable for display in picker
---@param var Variable
---@return string
local function format_variable(var)
  local value = var.value:get() or ""
  -- Truncate long values
  if #value > 40 then
    value = value:sub(1, 37) .. "..."
  end
  local type_str = var.type:get()
  if type_str then
    return string.format("%s: %s = %s", var.name, type_str, value)
  end
  return string.format("%s = %s", var.name, value)
end

---@param debugger Debugger
return function(debugger)
  local Picker = require("neodap.plugins.dap_uri_picker")(debugger)

  ---Fetch and show variables for a scope
  ---@param scope Scope
  ---@param callback fun(var: Variable?)
  local function pick_variable_from_scope(scope, callback)
    neostate.void(function()
      local variables = scope:variables()
      if not variables then
        callback(nil)
        return
      end

      local items = {}
      for var in variables:iter() do
        items[#items + 1] = var
      end

      if #items == 0 then
        vim.notify("No variables in scope: " .. scope.name, vim.log.levels.WARN)
        callback(nil)
        return
      end

      if #items == 1 then
        callback(items[1])
        return
      end

      -- Show picker
      vim.ui.select(items, {
        prompt = "Select variable (" .. scope.name .. "):",
        format_item = format_variable,
      }, function(selected)
        callback(selected)
      end)
    end)()
  end

  ---Pick scope then variable from current frame
  ---@param callback fun(var: Variable?)
  local function pick_from_frame(callback)
    -- Get current frame from context
    local frame = debugger:resolve_contextual_one("@frame", "frame"):get()
    if not frame then
      vim.notify("No frame in context", vim.log.levels.WARN)
      callback(nil)
      return
    end

    neostate.void(function()
      local scopes = frame:scopes()
      if not scopes then
        vim.notify("Failed to fetch scopes", vim.log.levels.ERROR)
        callback(nil)
        return
      end

      local scope_items = {}
      for scope in scopes:iter() do
        scope_items[#scope_items + 1] = scope
      end

      if #scope_items == 0 then
        vim.notify("No scopes available", vim.log.levels.WARN)
        callback(nil)
        return
      end

      -- If only one scope, use it directly
      if #scope_items == 1 then
        pick_variable_from_scope(scope_items[1], callback)
        return
      end

      -- Pick scope first
      vim.ui.select(scope_items, {
        prompt = "Select scope:",
        format_item = function(scope)
          return scope.name
        end,
      }, function(selected_scope)
        if not selected_scope then
          callback(nil)
          return
        end
        pick_variable_from_scope(selected_scope, callback)
      end)
    end)()
  end

  vim.api.nvim_create_user_command("DapVariable", function(opts)
    local uri_pattern = opts.args ~= "" and opts.args or nil

    local function open_variable(var)
      if not var then return end
      if not var.uri then
        vim.notify("Variable has no URI", vim.log.levels.ERROR)
        return
      end
      vim.cmd("edit " .. var.uri)
    end

    if uri_pattern then
      -- Resolve given pattern
      Picker:resolve(uri_pattern, open_variable)
    else
      -- Pick from current frame
      pick_from_frame(open_variable)
    end
  end, {
    nargs = "?",
    desc = "Edit a debug variable (with picker)",
    complete = function(arglead)
      -- Provide some common patterns
      local completions = {
        "@frame/scope:Locals/variable:",
        "@frame/scope:Globals/variable:",
        "@frame/scope:*/variable:",
      }
      if arglead == "" then
        return completions
      end
      return vim.tbl_filter(function(c)
        return c:find(arglead, 1, true) == 1
      end, completions)
    end,
  })

  -- Cleanup
  debugger:on_dispose(function()
    pcall(vim.api.nvim_del_user_command, "DapVariable")
  end)

  return function()
    pcall(vim.api.nvim_del_user_command, "DapVariable")
  end
end
