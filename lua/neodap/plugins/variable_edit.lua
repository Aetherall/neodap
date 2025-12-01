---Variable edit buffer plugin
---Enables `:edit dap:@frame/scope:Locals/var:myVar` to edit variables
---
---Buffer states (orthogonal flags):
---  - dirty: User has unsaved edits
---  - detached: Context changed, URI now resolves elsewhere
---  - expired: Original resource cannot be written (frame popped)
---  - diverged: Resource value changed externally since edit started

local uri_module = require("neodap.sdk.uri")
local neostate = require("neostate")

local M = {}

---@class VariableEditConfig
---@field notify_on_save? boolean Show "Variable updated" notification (default: true)
---@field notify_on_error? boolean Show error notifications (default: true)
---@field warning_style? "virtual_text"|"notify"|"both"|"none" How to display state warnings (default: "virtual_text")
---@field on_diverged? fun(bufnr: number, state: BufferState) Called when buffer becomes diverged
---@field on_expired? fun(bufnr: number, state: BufferState) Called when buffer becomes expired
---@field on_detached? fun(bufnr: number, state: BufferState) Called when buffer becomes detached
---@field on_save? fun(bufnr: number, variable: Variable, new_value: string) Called after successful save

---@type VariableEditConfig
local default_config = {
  notify_on_save = true,
  notify_on_error = true,
  warning_style = "virtual_text",
}

-- Namespace for virtual text warnings
local ns_id = vim.api.nvim_create_namespace("neodap-variable-edit")

---@class BufferState
---@field uri string Original URI pattern (may be contextual)
---@field concrete_uri string Resolved concrete URI at open time
---@field origin_value string Value when editing started
---@field variable Variable? Reference to the variable entity
---@field context Disposable Per-buffer disposable context
---@field dirty boolean User has unsaved edits
---@field detached boolean Context now points elsewhere
---@field expired boolean Original resource gone
---@field diverged boolean Value changed externally

---@type table<number, BufferState>
local active_buffers = {}

---Build warning message from state flags
---@param state BufferState
---@return string?
local function build_warning_message(state)
  local parts = {}

  if state.expired then
    table.insert(parts, "Resource expired (frame popped). Cannot save.")
  end

  if state.detached and not state.expired then
    table.insert(parts, "Context changed.")
  end

  if state.diverged and not state.expired then
    table.insert(parts, "Value changed externally.")
  end

  if #parts == 0 then
    return nil
  end

  -- Add available actions
  local actions = {}
  if not state.expired then
    table.insert(actions, ":w saves")
  end
  table.insert(actions, ":e! reloads")
  table.insert(actions, ":bd closes")

  return table.concat(parts, " ") .. " [" .. table.concat(actions, ", ") .. "]"
end

---Update warning display for a buffer
---@param bufnr number
---@param cfg VariableEditConfig
local function update_warnings(bufnr, cfg)
  local state = active_buffers[bufnr]
  if not state then return end

  -- Clear existing virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local message = build_warning_message(state)

  -- Display warning based on style
  if message and cfg.warning_style ~= "none" then
    if cfg.warning_style == "virtual_text" or cfg.warning_style == "both" then
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, 0, {
        virt_text = { { message, "WarningMsg" } },
        virt_text_pos = "eol",
      })
    end
    if cfg.warning_style == "notify" or cfg.warning_style == "both" then
      vim.notify(message, vim.log.levels.WARN)
    end
  end

  -- Update buffer-local variables for statusline integration
  vim.b[bufnr].dap_var_dirty = state.dirty
  vim.b[bufnr].dap_var_detached = state.detached
  vim.b[bufnr].dap_var_expired = state.expired
  vim.b[bufnr].dap_var_diverged = state.diverged
end

---Resolve a variable from a URI
---@param debugger Debugger
---@param pattern string URI pattern (may be contextual)
---@return Variable? variable
---@return string? concrete_uri The resolved concrete URI
local function resolve_variable(debugger, pattern)
  local ctx = debugger:context(vim.api.nvim_get_current_buf())

  -- Check if contextual
  if uri_module.is_contextual(pattern) then
    local frame_uri = ctx.frame_uri:get()
    if not frame_uri then
      return nil, nil
    end

    local context_entity = debugger:resolve_one(frame_uri)
    if not context_entity then
      return nil, nil
    end

    local context_map = uri_module.build_context_map(context_entity)
    local concrete_uri = uri_module.expand_contextual(pattern, context_map)
    if not concrete_uri then
      return nil, nil
    end

    -- Look up variable by URI
    local variable = debugger.variables:get_one("by_uri", concrete_uri)
    return variable, concrete_uri
  else
    -- Direct concrete URI
    local variable = debugger.variables:get_one("by_uri", pattern)
    return variable, pattern
  end
end

---Populate buffer with variable value
---@param bufnr number
---@param variable Variable?
local function populate_buffer(bufnr, variable)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.bo[bufnr].modifiable = true

  if not variable then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "-- Variable not found" })
    vim.bo[bufnr].modifiable = false
    return
  end

  local value = variable.value:get() or ""
  local lines = vim.split(value, "\n")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modified = false
end

---Setup reactive subscriptions for a buffer
---@param bufnr number
---@param debugger Debugger
---@param state BufferState
---@param cfg VariableEditConfig
local function setup_subscriptions(bufnr, debugger, state, cfg)
  -- Use default context for the edit buffer (inherits from global)
  local ctx = debugger:context()
  local is_contextual = uri_module.is_contextual(state.uri)

  -- Watch variable value changes
  if state.variable then
    state.variable.value:watch(function(new_value)
      if not vim.api.nvim_buf_is_valid(bufnr) then return end

      vim.schedule(function()
        if state.dirty then
          -- Check if value actually diverged
          if new_value ~= state.origin_value then
            state.diverged = true
            update_warnings(bufnr, cfg)
            if cfg.on_diverged then
              cfg.on_diverged(bufnr, state)
            end
          end
        else
          -- Auto-update buffer when clean
          populate_buffer(bufnr, state.variable)
          state.origin_value = new_value or ""
          update_warnings(bufnr, cfg)
        end
      end)
    end)

    -- Watch variable expiration
    state.variable._is_current:watch(function(is_current)
      if not vim.api.nvim_buf_is_valid(bufnr) then return end

      vim.schedule(function()
        if not is_current then
          state.expired = true
          update_warnings(bufnr, cfg)
          if cfg.on_expired then
            cfg.on_expired(bufnr, state)
          end
        end
      end)
    end)
  end

  -- Watch context changes (only for contextual URIs)
  if is_contextual then
    ctx.frame_uri:watch(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end

      vim.schedule(function()
        -- Re-resolve the contextual URI
        local new_variable, new_concrete_uri = resolve_variable(debugger, state.uri)

        if new_concrete_uri ~= state.concrete_uri then
          -- Context now points elsewhere
          if state.dirty then
            state.detached = true
            update_warnings(bufnr, cfg)
            if cfg.on_detached then
              cfg.on_detached(bufnr, state)
            end
          else
            -- Auto-update to new context
            state.variable = new_variable
            state.concrete_uri = new_concrete_uri or ""
            state.origin_value = new_variable and new_variable.value:get() or ""
            state.detached = false
            state.diverged = false
            -- Update buffer variable for other plugins (e.g., variable_completion)
            vim.b[bufnr].dap_var_concrete_uri = new_concrete_uri
            populate_buffer(bufnr, new_variable)
            update_warnings(bufnr, cfg)
          end
        end
      end)
    end)
  end
end

---Setup the variable edit plugin
---@param debugger Debugger
---@param config? VariableEditConfig
function M.setup(debugger, config)
  local cfg = vim.tbl_deep_extend("force", default_config, config or {})

  local group = vim.api.nvim_create_augroup("neodap-variable-edit", { clear = true })

  -- BufReadCmd for variable URIs
  -- Matches patterns like: dap:session:.../var:... or dap:@frame/scope:.../var:...
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = { "dap:*/var:*", "dap:@*/var:*", "dap:*/variable:*", "dap:@*/variable:*" },
    group = group,
    callback = function(opts)
      local bufnr = opts.buf
      local pattern = opts.file

      -- Setup buffer options
      vim.bo[bufnr].buftype = "acwrite"  -- Allows :w to trigger BufWriteCmd
      vim.bo[bufnr].bufhidden = "hide"
      vim.bo[bufnr].swapfile = false

      -- Resolve variable
      local variable, concrete_uri = resolve_variable(debugger, pattern)

      if not variable then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
          "-- Error: Variable not found",
          "-- URI: " .. pattern,
        })
        vim.bo[bufnr].modifiable = false
        return
      end

      -- Create buffer state
      local ctx = neostate.Disposable({}, nil, "VarEdit:" .. bufnr)
      ctx:set_parent(debugger)

      ---@type BufferState
      local state = {
        uri = pattern,
        concrete_uri = concrete_uri or "",
        origin_value = variable.value:get() or "",
        variable = variable,
        context = ctx,
        dirty = false,
        detached = false,
        expired = false,
        diverged = false,
      }

      active_buffers[bufnr] = state

      -- Store metadata in buffer variables
      vim.b[bufnr].dap_var_uri = pattern
      vim.b[bufnr].dap_var_concrete_uri = concrete_uri

      -- Populate buffer
      populate_buffer(bufnr, variable)

      -- Setup reactive subscriptions within the context
      ctx:run(function()
        setup_subscriptions(bufnr, debugger, state, cfg)
      end)

      -- Track dirty state via TextChanged and BufModifiedSet
      -- BufModifiedSet catches programmatic edits via nvim_buf_set_lines
      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufModifiedSet" }, {
        buffer = bufnr,
        group = group,
        callback = function()
          -- Only track if buffer is actually modified
          if not vim.bo[bufnr].modified then return end
          if state.dirty then return end
          state.dirty = true
          update_warnings(bufnr, cfg)
          -- Store origin value on first edit
          if state.origin_value == "" and state.variable then
            state.origin_value = state.variable.value:get() or ""
          end
        end,
      })
    end,
  })

  -- BufWriteCmd for saving variable changes
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    pattern = { "dap:*/var:*", "dap:@*/var:*", "dap:*/variable:*", "dap:@*/variable:*" },
    group = group,
    callback = function(opts)
      local bufnr = opts.buf
      local state = active_buffers[bufnr]

      if not state then
        if cfg.notify_on_error then
          vim.notify("Variable buffer state not found", vim.log.levels.ERROR)
        end
        return
      end

      -- Check if expired
      if state.expired then
        if cfg.notify_on_error then
          vim.notify("Cannot save: resource expired (frame popped)", vim.log.levels.ERROR)
        end
        return
      end

      -- Get the variable to write to (original, not current context)
      local variable = state.variable
      if not variable then
        if cfg.notify_on_error then
          vim.notify("Variable not found", vim.log.levels.ERROR)
        end
        return
      end

      -- Get buffer content
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local new_value = table.concat(lines, "\n")

      -- Call set_value async (requires coroutine context)
      local write_complete = false
      local write_error = nil
      local write_result_value = nil

      neostate.void(function()
        local err, result_value, _ = variable:set_value(new_value)
        write_error = err
        write_result_value = result_value
        write_complete = true
      end)()

      -- Wait for write to complete (with timeout)
      vim.wait(5000, function() return write_complete end, 100)

      if write_error then
        if cfg.notify_on_error then
          vim.notify("Failed to set variable: " .. tostring(write_error), vim.log.levels.ERROR)
        end
        return
      end

      -- Success - clear all flags
      state.dirty = false
      state.detached = false
      state.diverged = false
      state.origin_value = write_result_value or new_value

      -- Update buffer with actual value returned by debugger
      if write_result_value then
        local result_lines = vim.split(write_result_value, "\n")
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result_lines)
      end

      vim.bo[bufnr].modified = false
      update_warnings(bufnr, cfg)

      -- Notify and call callback
      if cfg.notify_on_save then
        vim.notify("Variable updated", vim.log.levels.INFO)
      end
      if cfg.on_save then
        cfg.on_save(bufnr, variable, write_result_value or new_value)
      end
    end,
  })

  -- Cleanup on buffer wipeout
  vim.api.nvim_create_autocmd("BufWipeout", {
    pattern = { "dap:*/var:*", "dap:@*/var:*", "dap:*/variable:*", "dap:@*/variable:*" },
    group = group,
    callback = function(opts)
      local bufnr = opts.buf
      local state = active_buffers[bufnr]
      if state then
        state.context:dispose()
        active_buffers[bufnr] = nil
      end
    end,
  })

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    for bufnr, state in pairs(active_buffers) do
      if state.context then
        state.context:dispose()
      end
    end
    active_buffers = {}
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end)

  -- Return cleanup function
  return function()
    for bufnr, state in pairs(active_buffers) do
      if state.context then
        state.context:dispose()
      end
    end
    active_buffers = {}
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
end

return M
