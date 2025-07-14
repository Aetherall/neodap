local Class = require("neodap.tools.class")
local nio = require("nio")


---@class CallsProps
---@field sequence number
---@field listeners { [number]?: fun(message: dap.AnyIncomingMessage) }
---@field send fun(message: dap.AnyOutgoingMessage)


---@class Calls: CallsProps
---@field attach fun(self: Calls, args: dap.AttachRequestArguments): { wait: fun(): nil }
---@field breakpointLocations fun(self: Calls, args: dap.BreakpointLocationsArguments): { wait: fun(): dap.BreakpointLocationsResponseBody }
---@field completions fun(self: Calls, args: dap.CompletionsArguments): { wait: fun(): dap.CompletionsResponseBody }
---@field configurationDone fun(self: Calls, args: dap.ConfigurationDoneArguments): { wait: fun(): nil }
---@field continue fun(self: Calls, args: dap.ContinueArguments): { wait: fun(): dap.ContinueResponseBody }
---@field dataBreakpointInfo fun(self: Calls, args: dap.DataBreakpointInfoArguments): { wait: fun(): dap.DataBreakpointInfoResponseBody }
---@field disassemble fun(self: Calls, args: dap.DisassembleArguments): { wait: fun(): dap.DisassembleResponseBody }
---@field disconnect fun(self: Calls, args: dap.DisconnectArguments): { wait: fun(): nil }
---@field evaluate fun(self: Calls, args: dap.EvaluateArguments): { wait: fun(): dap.EvaluateResponseBody }
---@field exceptionInfo fun(self: Calls, args: dap.ExceptionInfoArguments): { wait: fun(): dap.ExceptionInfoResponseBody }
---@field goto fun(self: Calls, args: dap.GotoArguments): { wait: fun(): nil }
---@field gotoTargets fun(self: Calls, args: dap.GotoTargetsArguments): { wait: fun(): dap.GotoTargetsResponseBody }
---@field initialize fun(self: Calls, args: dap.InitializeRequestArguments): { wait: fun(): dap.Capabilities }
---@field launch fun(self: Calls, args: dap.LaunchRequestArguments): { wait: fun(): nil }
---@field loadedSources fun(self: Calls, args: dap.LoadedSourcesArguments): { wait: fun(): dap.LoadedSourcesResponseBody }
---@field locations fun(self: Calls, args: dap.LocationsArguments): { wait: fun(): dap.LocationsResponseBody }
---@field modules fun(self: Calls, args: dap.ModulesArguments): { wait: fun(): dap.ModulesResponseBody }
---@field next fun(self: Calls, args: dap.NextArguments): { wait: fun(): nil }
---@field pause fun(self: Calls, args: dap.PauseArguments): { wait: fun(): nil }
---@field readMemory fun(self: Calls, args: dap.ReadMemoryArguments): { wait: fun(): dap.ReadMemoryResponseBody }
---@field restart fun(self: Calls, args: dap.RestartArguments): { wait: fun(): nil }
---@field restartFrame fun(self: Calls, args: dap.RestartFrameArguments): { wait: fun(): nil }
---@field reverseContinue fun(self: Calls, args: dap.ReverseContinueArguments): { wait: fun(): nil }
---@field scopes fun(self: Calls, args: dap.ScopesArguments): { wait: fun(): dap.ScopesResponseBody }
---@field setBreakpoints fun(self: Calls, args: dap.SetBreakpointsArguments): { wait: fun(): dap.SetBreakpointsResponseBody }
---@field setDataBreakpoints fun(self: Calls, args: dap.SetDataBreakpointsArguments): { wait: fun(): dap.SetDataBreakpointsResponseBody }
---@field setExceptionBreakpoints fun(self: Calls, args: dap.SetExceptionBreakpointsArguments): { wait: fun(): dap.SetExceptionBreakpointsResponseBody }
---@field setExpression fun(self: Calls, args: dap.SetExpressionArguments): { wait: fun(): dap.SetExpressionResponseBody }
---@field setFunctionBreakpoints fun(self: Calls, args: dap.SetFunctionBreakpointsArguments): { wait: fun(): dap.SetFunctionBreakpointsResponseBody }
---@field setInstructionBreakpoints fun(self: Calls, args: dap.SetInstructionBreakpointsArguments): { wait: fun(): dap.SetInstructionBreakpointsResponseBody }
---@field setVariable fun(self: Calls, args: dap.SetVariableArguments): { wait: fun(): dap.SetVariableResponseBody }
---@field source fun(self: Calls, args: dap.SourceArguments): { wait: fun(): dap.SourceResponseBody }
---@field stackTrace fun(self: Calls, args: dap.StackTraceArguments): { wait: fun(): dap.StackTraceResponseBody }
---@field stepBack fun(self: Calls, args: dap.StepBackArguments): { wait: fun(): nil }
---@field stepIn fun(self: Calls, args: dap.StepInArguments): { wait: fun(): nil }
---@field stepInTargets fun(self: Calls, args: dap.StepInTargetsArguments): { wait: fun(): dap.StepInTargetsResponseBody }
---@field stepOut fun(self: Calls, args: dap.StepOutArguments): { wait: fun(): nil }
---@field terminate fun(self: Calls, args: dap.TerminateArguments): { wait: fun(): nil }
---@field terminateThreads fun(self: Calls, args: dap.TerminateThreadsArguments): { wait: fun(): nil }
---@field threads fun(self: Calls): { wait: fun(): dap.ThreadsResponseBody }
---@field variables fun(self: Calls, args: dap.VariablesArguments): { wait: fun(): dap.VariablesResponseBody }
---@field writeMemory fun(self: Calls, args: dap.WriteMemoryArguments): { wait: fun(): dap.WriteMemoryResponseBody }
---@field new Constructor<CallsProps>
local Calls = Class()


---@return Calls
function Calls.create()
  local instance = Calls:new({
    sequence = 0,
    listeners = {},
    send = function(message)
      error("Session is not bound yet.")
    end
  })

  return instance
end

---@param sender fun(message: dap.AnyOutgoingMessage)
function Calls:bind(sender)
  self.send = sender
end

---@param message dap.AnyResponse
function Calls:receive(message)
  local request_seq = message.request_seq;

  local waiter = self.listeners[request_seq]
  if waiter then
    waiter(message)
    self.listeners[request_seq] = nil
  end
end

-- -@alias Call<C, P, R> fun(self: Calls, command: C, params?: P): { wait: fun(): R }
-- -@alias AnyCall Call<'attach', dap.AttachRequestArguments, nil> | Call<'breakpointLocations', dap.BreakpointLocationsArguments, dap.BreakpointLocationsResponseBody> | Call<'completions', dap.CompletionsArguments, dap.CompletionsResponseBody> | Call<'configurationDone', {}, nil> | Call<'continue', dap.ContinueArguments, dap.ContinueResponseBody> | Call<'dataBreakpointInfo', dap.DataBreakpointInfoArguments, dap.DataBreakpointInfoResponseBody> | Call<'disassemble', dap.DisassembleArguments, dap.DisassembleResponseBody> | Call<'disconnect', dap.DisconnectArguments, nil> | Call<'evaluate', dap.EvaluateArguments, dap.EvaluateResponseBody> | Call<'exceptionInfo', dap.ExceptionInfoArguments, dap.ExceptionInfoResponseBody> | Call<'goto', dap.GotoArguments, nil> | Call<'gotoTargets', dap.GotoTargetsArguments, dap.GotoTargetsResponseBody> | Call<'initialize', dap.InitializeRequestArguments, dap.Capabilities> | Call<'launch', dap.LaunchRequestArguments, nil> | Call<'loadedSources', dap.LoadedSourcesArguments, dap.LoadedSourcesResponseBody> | Call<'locations', dap.LocationsArguments, dap.LocationsResponseBody> | Call<'modules',dap.ModulesArguments, dap.ModulesResponseBody> | Call<'next', dap.NextArguments, nil> | Call<'pause', dap.PauseArguments, nil> | Call<'readMemory', dap.ReadMemoryArguments, dap.ReadMemoryResponseBody> | Call<'restart', dap.RestartArguments, nil> | Call<'restartFrame', dap.RestartFrameArguments, nil> | Call<'reverseContinue', dap.ReverseContinueArguments, nil> | Call<'scopes', dap.ScopesArguments, dap.ScopesResponseBody> | Call<'setBreakpoints', dap.SetBreakpointsArguments, dap.SetBreakpointsResponseBody> | Call<'setDataBreakpoints', dap.SetDataBreakpointsArguments, dap.SetDataBreakpointsResponseBody> | Call<'setExceptionBreakpoints', dap.SetExceptionBreakpointsArguments, dap.SetExceptionBreakpointsResponseBody> | Call<'setExpression', dap.SetExpressionArguments, dap.SetExpressionResponseBody> | Call<'setFunctionBreakpoints', dap.SetFunctionBreakpointsArguments, dap.SetFunctionBreakpointsResponseBody> | Call<'setInstructionBreakpoints', dap.SetInstructionBreakpointsArguments, dap.SetInstructionBreakpointsResponseBody> | Call<'setVariable', dap.SetVariableArguments, dap.SetVariableResponseBody> | Call<'source', dap.SourceArguments, dap.SourceResponseBody> | Call<'stackTrace',dap.StackTraceArguments, dap.StackTraceResponseBody> | Call<'stepBack',dap.StepBackArguments, nil> | Call<'stepIn',dap.StepInArguments,nil> | Call<'stepInTargets',dap.StepInTargetsArguments,dap.StepInTargetsResponseBody> | Call<'stepOut',dap.StepOutArguments,nil> | Call<'terminateThreads',dap.TerminateThreadsArguments,nil>

---@overload fun(self: Calls, command: 'attach', args: dap.AttachRequestArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'breakpointLocations', args: dap.BreakpointLocationsArguments): { wait: fun(): dap.BreakpointLocationsResponseBody }
---@overload fun(self: Calls, command: 'completions', args: dap.CompletionsArguments): { wait: fun(): dap.CompletionsResponseBody }
---@overload fun(self: Calls, command: 'configurationDone', args: {}): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'continue', args: dap.ContinueArguments): { wait: fun(): dap.ContinueResponseBody }
---@overload fun(self: Calls, command: 'dataBreakpointInfo', args: dap.DataBreakpointInfoArguments): { wait: fun(): dap.DataBreakpointInfoResponseBody }
---@overload fun(self: Calls, command: 'disassemble', args: dap.DisassembleArguments): { wait: fun(): dap.DisassembleResponseBody }
---@overload fun(self: Calls, command: 'disconnect', args: dap.DisconnectArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'evaluate', args: dap.EvaluateArguments): { wait: fun(): dap.EvaluateResponseBody }
---@overload fun(self: Calls, command: 'exceptionInfo', args: dap.ExceptionInfoArguments): { wait: fun(): dap.ExceptionInfoResponseBody }
---@overload fun(self: Calls, command: 'goto', args: dap.GotoArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'gotoTargets', args: dap.GotoTargetsArguments): { wait: fun(): dap.GotoTargetsResponseBody }
---@overload fun(self: Calls, command: 'initialize', args: dap.InitializeRequestArguments): { wait: fun(): dap.Capabilities }
---@overload fun(self: Calls, command: 'launch', args: dap.LaunchRequestArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'loadedSources', args: dap.LoadedSourcesArguments): { wait: fun(): dap.LoadedSourcesResponseBody }
---@overload fun(self: Calls, command: 'locations', args: dap.LocationsArguments): { wait: fun(): dap.LocationsResponseBody }
---@overload fun(self: Calls, command: 'modules', args:dap.ModulesArguments): { wait: fun(): dap.ModulesResponseBody }
---@overload fun(self: Calls, command: 'next', args: dap.NextArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'pause', args: dap.PauseArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'readMemory', args: dap.ReadMemoryArguments): { wait: fun(): dap.ReadMemoryResponseBody }
---@overload fun(self: Calls, command: 'restart', args: dap.RestartArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'restartFrame', args: dap.RestartFrameArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'reverseContinue', args: dap.ReverseContinueArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'scopes', args: dap.ScopesArguments): { wait: fun(): dap.ScopesResponseBody }
---@overload fun(self: Calls, command: 'setBreakpoints', args: dap.SetBreakpointsArguments): { wait: fun(): dap.SetBreakpointsResponseBody }
---@overload fun(self: Calls, command: 'setDataBreakpoints', args: dap.SetDataBreakpointsArguments): { wait: fun(): dap.SetDataBreakpointsResponseBody }
---@overload fun(self: Calls, command: 'setExceptionBreakpoints', args: dap.SetExceptionBreakpointsArguments): { wait: fun(): dap.SetExceptionBreakpointsResponseBody }
---@overload fun(self: Calls, command: 'setExpression', args: dap.SetExpressionArguments): { wait: fun(): dap.SetExpressionResponseBody }
---@overload fun(self: Calls, command: 'setFunctionBreakpoints', args: dap.SetFunctionBreakpointsArguments): { wait: fun(): dap.SetFunctionBreakpointsResponseBody }
---@overload fun(self: Calls, command: 'setInstructionBreakpoints', args: dap.SetInstructionBreakpointsArguments): { wait: fun(): dap.SetInstructionBreakpointsResponseBody }
---@overload fun(self: Calls, command: 'setVariable', args: dap.SetVariableArguments): { wait: fun(): dap.SetVariableResponseBody }
---@overload fun(self: Calls, command: 'source', args: dap.SourceArguments): { wait: fun(): dap.SourceResponseBody }
---@overload fun(self: Calls, command: 'stackTrace', args:dap.StackTraceArguments): { wait: fun(): dap.StackTraceResponseBody }
---@overload fun(self: Calls, command: 'stepBack', args:dap.StepBackArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'stepIn', args:dap.StepInArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'stepInTargets', args:dap.StepInTargetsArguments): { wait: fun(): dap.StepInTargetsResponseBody }
---@overload fun(self: Calls, command: 'stepOut', args:dap.StepOutArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'terminateThreads', args:dap.TerminateThreadsArguments): { wait: fun(): nil }
---@overload fun(self: Calls, command: 'variables', args: dap.VariablesArguments): { wait: fun(): dap.VariablesResponseBody }
function Calls:call(command, params)
  self.sequence = self.sequence + 1
  local request_seq = self.sequence

  local message = {
    command = command,
    arguments = params,
    seq = request_seq,
    type = "request",
  }

  local future = nio.control.future()

  self.listeners[request_seq] = function(response)
    if response.success then
      future.set(response.body or nil)
    else
      future.set_error(response.message)
    end
  end

  -- print("Sending " .. message.command, vim.inspect(message.arguments))

  self.send(message)

  return future
end

function Calls:answer(request, body)
  self.sequence = self.sequence + 1
  local request_seq = self.sequence
  local response = {
    command = request.command,
    body = body,
    seq = request_seq,
    type = "response",
    request_seq = request.seq,
    success = true,
  }

  self.send(response)
end

local commands = {
  'attach',
  'breakpointLocations',
  'completions',
  'configurationDone',
  'continue',
  'dataBreakpointInfo',
  'disassemble',
  'disconnect',
  'evaluate',
  'exceptionInfo',
  'goto',
  'gotoTargets',
  'initialize',
  'launch',
  'loadedSources',
  'locations',
  'modules',
  'next',
  'pause',
  'readMemory',
  'restart',
  'restartFrame',
  'reverseContinue',
  'scopes',
  'setBreakpoints',
  'setDataBreakpoints',
  'setExceptionBreakpoints',
  'setExpression',
  'setFunctionBreakpoints',
  'setInstructionBreakpoints',
  'setVariable',
  'source',
  'stackTrace',
  'stepBack',
  'stepIn',
  'stepInTargets',
  'stepOut',
  'terminateThreads',
  'variables',
}



for _, command in ipairs(commands) do
  Calls[command] = function(self, args)
    return self:call(command, args)
  end
end


return Calls
