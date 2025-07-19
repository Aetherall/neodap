local Class = require("neodap.tools.class")
local VariableCore = require("neodap.plugins.VariableCore")
local nio = require("nio")

---@class NeodapNeotreeVariableSource
local NeodapNeotreeVariableSource = Class()

-- Neo-tree source interface
NeodapNeotreeVariableSource.name = "neodap-variable-tree"
NeodapNeotreeVariableSource.display_name = "🐛 Variables"

function NeodapNeotreeVariableSource.plugin(api)
  local instance = NeodapNeotreeVariableSource:new({ api = api })
  instance:init()
  return instance
end

function NeodapNeotreeVariableSource:init()
  self.current_frame = nil
  self.variableCore = self.api:getPluginInstance(VariableCore)
  
  -- Set up the module-based Neo-tree source
  local source_module = require("neodap-variable-tree")
  source_module.set_plugin_instance(self)
  
  -- Hook into DAP events
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function()
        local stack = thread:stack()
        if stack then
          self.current_frame = stack:top()
          if ok and manager then pcall(manager.refresh, self.name) end
        end
      end)
      thread:onContinued(function()
        self.current_frame = nil
        if ok and manager then pcall(manager.refresh, self.name) end
      end)
    end)
  end)
end

return NeodapNeotreeVariableSource