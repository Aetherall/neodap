-- Debugger entity methods for neograph-native
local Ctx = require("neodap.ctx")

---@param Debugger neodap.entities.Debugger
return function(Debugger)
  -- Load sub-modules
  require("neodap.entities.debugger.source")(Debugger)
  require("neodap.entities.debugger.breakpoint")(Debugger)
  require("neodap.entities.debugger.session")(Debugger)

  --------------------------------------------------------------------------------
  -- Context API (debugger.ctx)
  --------------------------------------------------------------------------------

  ---Initialize the ctx property on a debugger instance
  ---@param debugger table
  function Debugger.initCtx(debugger)
    debugger.ctx = Ctx.new(debugger)
  end

end
