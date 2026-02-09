-- Default action registrations
--
-- Populates the action registry with standard action recipes
-- for all built-in entity types. These consolidate duplicated
-- multi-step operations from keybinds.lua, telescope.lua, and *_cmd.lua.

local navigate = require("neodap.plugins.utils.navigate")
local log = require("neodap.logger")

local M = {}

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
    local sb = binding.sourceBinding:get()
    if sb then sb:syncBreakpoints() end
  end)

  ra(debugger, "toggle", "ExceptionFilterBinding", function(binding)
    binding:toggle()
    local session = binding.session and binding.session:get()
    if session then session:syncExceptionFilters() end
  end)

  ra(debugger, "toggle", "ExceptionFilter", function(ef)
    ef:toggle()
    for binding in ef.bindings:iter() do
      local session = binding.session and binding.session:get()
      if session then session:syncExceptionFilters() end
    end
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
    local session = binding.session and binding.session:get()
    if session then session:syncExceptionFilters() end
  end)

  ra(debugger, "disable", "ExceptionFilterBinding", function(binding)
    if binding:getEffectiveEnabled() then binding:toggle() end
    local session = binding.session and binding.session:get()
    if session then session:syncExceptionFilters() end
  end)

  -- ======================================================================
  -- remove
  -- ======================================================================

  ra(debugger, "remove", "Breakpoint", function(bp)
    bp:remove()
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
      local sb = binding.sourceBinding:get()
      if sb then sb:syncBreakpoints() end
    end)
  end)

  ra(debugger, "edit_condition", "ExceptionFilterBinding", function(binding)
    if not binding:canHaveCondition() then
      log:warn("This filter does not support conditions")
      return
    end
    local current = binding.condition:get()
    if current == vim.NIL then current = nil end
    vim.ui.input({ prompt = "Exception condition: ", default = current or "" }, function(input)
      if input == nil then return end
      binding:update({ condition = input ~= "" and input or vim.NIL })
      local session = binding.session and binding.session:get()
      if session then session:syncExceptionFilters() end
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
      local sb = binding.sourceBinding:get()
      if sb then sb:syncBreakpoints() end
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
      local sb = binding.sourceBinding:get()
      if sb then sb:syncBreakpoints() end
    end)
  end)

  -- ======================================================================
  -- clear_override
  -- ======================================================================

  ra(debugger, "clear_override", "BreakpointBinding", function(binding)
    if not binding:hasOverride() then return end
    binding:clearOverride()
    local sb = binding.sourceBinding:get()
    if sb then sb:syncBreakpoints() end
  end)

  ra(debugger, "clear_override", "ExceptionFilterBinding", function(binding)
    if not binding:hasOverride() then return end
    binding:clearOverride()
    local session = binding.session and binding.session:get()
    if session then session:syncExceptionFilters() end
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
