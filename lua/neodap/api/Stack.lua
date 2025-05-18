local Class = require('neodap.tools.class')

local Frame = require('neodap.api.Frame')

---@class api.StackProps
---@field thread api.Thread
---@field _frames api.Frame[] | nil

---@class api.Stack: api.StackProps
---@field new Constructor<api.StackProps>
local Stack = Class()

---@param thread api.Thread
---@param stack dap.StackTraceResponseBody
function Stack.instanciate(thread, stack)
  local stack = Stack:new(function(self)
    return {
      thread = thread,
      --- State
      _frames = vim.tbl_map(function(frame)
        return Frame.instanciate(self, frame)
      end, stack.stackFrames),
      --- DAP
      totalFrames = stack.totalFrames,
    }
  end)
  return stack
end

---@return api.Frame[]
function Stack:frames()
  if self._frames then
    return self._frames
  end

  local trace = self.thread.session.ref.calls:stackTrace({ threadId = self.thread.id }):wait()

  self._frames = vim.tbl_map(function(frame)
    return Frame.instanciate(self, frame)
  end, trace.stackFrames)

  return self._frames
end

return Stack
