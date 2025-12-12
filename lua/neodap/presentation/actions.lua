-- Default action registrations
--
-- Populates the action registry with standard action recipes
-- for all built-in entity types. These consolidate duplicated
-- multi-step operations from keybinds.lua, telescope.lua, and *_cmd.lua.

local navigate = require("neodap.plugins.utils.navigate")
local normalize = require("neodap.utils").normalize
local log = require("neodap.logger")

local M = {}

-- Shared helpers to reduce duplication across actions

local function sync_breakpoints(binding)
  local sb = binding.sourceBinding:get()
  if sb then sb:syncBreakpoints() end
end

local function sync_exception_filters(binding)
  local session = binding.session and binding.session:get()
  if session then session:syncExceptionFilters() end
end

local function goto_entity_source(entity)
  local src = entity.source:get()
  if not src then return end
  src:open({ line = entity.line:get() or 1, column = entity.column:get() })
end

---@param debugger table
function M.register(debugger)
  local ra = debugger.register_action

  -- ======================================================================
  -- toggle
  -- ======================================================================

  ra(debugger, "toggle", "Breakpoint", function(bp)
    bp:toggle()
    bp:sync()
  end)

  ra(debugger, "toggle", "BreakpointBinding", function(binding)
    binding:toggle()
    sync_breakpoints(binding)
  end)

  ra(debugger, "toggle", "ExceptionFilterBinding", function(binding)
    binding:toggle()
    sync_exception_filters(binding)
  end)

  ra(debugger, "toggle", "ExceptionFilter", function(ef)
    ef:toggle()
    ef:syncAllSessions()
  end)

  -- ======================================================================
  -- enable / disable
  -- ======================================================================

  ra(debugger, "enable", "Breakpoint", function(bp)
    if not bp:isEnabled() then bp:toggle() end
    bp:sync()
  end)

  ra(debugger, "disable", "Breakpoint", function(bp)
    if bp:isEnabled() then bp:toggle() end
    bp:sync()
  end)

  ra(debugger, "enable", "ExceptionFilterBinding", function(binding)
    if not binding:getEffectiveEnabled() then binding:toggle() end
    sync_exception_filters(binding)
  end)

  ra(debugger, "disable", "ExceptionFilterBinding", function(binding)
    if binding:getEffectiveEnabled() then binding:toggle() end
    sync_exception_filters(binding)
  end)

  -- ======================================================================
  -- remove
  -- ======================================================================

  ra(debugger, "remove", "Breakpoint", function(bp)
    local source = bp.source:get()
    bp:remove()
    if source then source:syncBreakpoints() end
  end)

  -- ======================================================================
  -- focus
  -- ======================================================================

  ra(debugger, "focus", "Frame", function(frame)
    debugger.ctx:focus(frame.uri:get())
  end)

  ra(debugger, "focus", "Session", function(session)
    debugger.ctx:focus(session.uri:get())
  end)

  ra(debugger, "focus", "Thread", function(thread)
    debugger.ctx:focus(thread.uri:get())
  end)

  -- ======================================================================
  -- goto_source (open source location in a suitable window)
  -- ======================================================================

  ra(debugger, "goto_source", "Frame", goto_entity_source)
  ra(debugger, "goto_source", "Breakpoint", goto_entity_source)

  -- ======================================================================
  -- Thread lifecycle
  -- ======================================================================

  ra(debugger, "continue", "Thread", function(thread) thread:continue() end)
  ra(debugger, "pause", "Thread", function(thread) thread:pause() end)
  ra(debugger, "step_over", "Thread", function(thread) thread:stepOver() end)
  ra(debugger, "step_in", "Thread", function(thread) thread:stepIn() end)
  ra(debugger, "step_out", "Thread", function(thread) thread:stepOut() end)

  -- ======================================================================
  -- Session / Config lifecycle
  -- ======================================================================

  ra(debugger, "terminate", "Session", function(session) session:terminate() end)
  ra(debugger, "terminate", "Config", function(config) config:terminate() end)
  ra(debugger, "disconnect", "Session", function(session) session:disconnect() end)

  -- ======================================================================
  -- Scope refresh
  -- ======================================================================

  ra(debugger, "refresh", "Scope", function(scope) scope:fetchVariables() end)

  -- ======================================================================
  -- Config view mode
  -- ======================================================================

  ra(debugger, "toggle_view_mode", "Config", function(cfg)
    local new_mode = cfg:toggleViewMode()
    vim.notify("Config view: " .. new_mode, vim.log.levels.INFO)
  end)

  -- ======================================================================
  -- focus_and_jump
  -- ======================================================================

  ra(debugger, "focus_and_jump", "Frame", function(frame, ctx)
    debugger.ctx:focus(frame.uri:get())
    local opts = ctx and ctx.opts or nil
    navigate.goto_frame(frame, opts)
  end)

  ra(debugger, "focus_and_jump", "Session", function(session, ctx)
    debugger.ctx:focus(session.uri:get())
    -- Find the first stopped frame in this session
    local frame = debugger:query(
      session.uri:get() .. "/threads(state=stopped)[0]/stack/frames[0]")
    if not frame then
      frame = debugger:query(
        session.uri:get() .. "/threads[0]/stack/frames[0]")
    end
    if frame then
      local opts = ctx and ctx.opts or nil
      navigate.goto_frame(frame, opts)
    end
  end)

  -- ======================================================================
  -- edit_condition
  -- ======================================================================

  ra(debugger, "edit_condition", "Breakpoint", function(bp)
    vim.ui.input({ prompt = "Condition: ", default = bp.condition:get() or "" }, function(input)
      if input == nil then return end
      bp:update({ condition = input ~= "" and input or nil })
      bp:sync()
    end)
  end)

  ra(debugger, "edit_condition", "BreakpointBinding", function(binding)
    local current = binding:getEffectiveCondition() or ""
    vim.ui.input({ prompt = "Condition (override): ", default = current }, function(input)
      if input == nil then return end
      binding:update({ condition = input ~= "" and input or vim.NIL })
      sync_breakpoints(binding)
    end)
  end)

  ra(debugger, "edit_condition", "ExceptionFilterBinding", function(binding)
    if not binding:canHaveCondition() then
      log:warn("This filter does not support conditions")
      return
    end
    local current = normalize(binding.condition:get())
    vim.ui.input({ prompt = "Exception condition: ", default = current or "" }, function(input)
      if input == nil then return end
      binding:update({ condition = input ~= "" and input or vim.NIL })
      sync_exception_filters(binding)
    end)
  end)

  -- ======================================================================
  -- edit_hit_condition
  -- ======================================================================

  ra(debugger, "edit_hit_condition", "Breakpoint", function(bp)
    vim.ui.input({ prompt = "Hit condition: ", default = bp.hitCondition:get() or "" }, function(input)
      if input == nil then return end
      bp:update({ hitCondition = input ~= "" and input or nil })
      bp:sync()
    end)
  end)

  ra(debugger, "edit_hit_condition", "BreakpointBinding", function(binding)
    local current = binding:getEffectiveHitCondition() or ""
    vim.ui.input({ prompt = "Hit condition (override): ", default = current }, function(input)
      if input == nil then return end
      binding:update({ hitCondition = input ~= "" and input or vim.NIL })
      sync_breakpoints(binding)
    end)
  end)

  -- ======================================================================
  -- edit_log_message
  -- ======================================================================

  ra(debugger, "edit_log_message", "Breakpoint", function(bp)
    vim.ui.input({ prompt = "Log message: ", default = bp.logMessage:get() or "" }, function(input)
      if input == nil then return end
      bp:update({ logMessage = input ~= "" and input or nil })
      bp:sync()
    end)
  end)

  ra(debugger, "edit_log_message", "BreakpointBinding", function(binding)
    local current = binding:getEffectiveLogMessage() or ""
    vim.ui.input({ prompt = "Log message (override): ", default = current }, function(input)
      if input == nil then return end
      binding:update({ logMessage = input ~= "" and input or vim.NIL })
      sync_breakpoints(binding)
    end)
  end)

  -- ======================================================================
  -- clear_override
  -- ======================================================================

  ra(debugger, "clear_override", "BreakpointBinding", function(binding)
    if not binding:hasOverride() then return end
    binding:clearOverride()
    sync_breakpoints(binding)
  end)

  ra(debugger, "clear_override", "ExceptionFilterBinding", function(binding)
    if not binding:hasOverride() then return end
    binding:clearOverride()
    sync_exception_filters(binding)
  end)

  -- ======================================================================
  -- yank_value / yank_name
  -- ======================================================================

  ra(debugger, "yank_value", "Variable", function(var)
    local value = var.value:get()
    if value then
      vim.fn.setreg('"', value)
      log:info("Yanked value", { value = value:sub(1, 50) })
    end
  end)

  ra(debugger, "yank_name", "Variable", function(var)
    local name = var.name:get()
    if name then
      vim.fn.setreg('"', name)
      log:info("Yanked name", { name = name })
    end
  end)
end

return M
