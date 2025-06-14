local Class = require('neodap.tools.class')

local Frame = require('neodap.api.Frame')
local Hookable = require("neodap.transport.hookable")

---@class api.StackProps
---@field thread api.Thread
---@field _frames { [integer]: api.Frame? } | nil
---@field _index table<integer, integer> | nil
---@field hookable Hookable
---@field valid boolean

---@class api.Stack: api.StackProps
---@field new Constructor<api.StackProps>
local Stack = Class()

---@param thread api.Thread
---@param stack dap.StackTraceResponseBody
function Stack.instanciate(thread, stack)
  local stack = Stack:new(function(self)
    local frames, index = Frame.indexAll(self, stack.stackFrames)
    return {
      thread = thread,
      --- State
      _frames = frames,
      _index = index,
      hookable = Hookable.create(),
      valid = true,
      --- DAP
      totalFrames = stack.totalFrames,
    }
  end)
  return stack
end

---@return { [integer]: api.Frame? } | nil
function Stack:frames()
  if not self.valid then
    return nil
  end

  if self._frames then
    return self._frames
  end

  local trace = self.thread.session.ref.calls:stackTrace({ threadId = self.thread.id }):wait()

  local frames, index = Frame.indexAll(self, trace.stackFrames)

  self._frames = frames
  self._index = index

  return self._frames
end

function Stack:top()
  if not self.valid then
    return nil
  end

  local frames = self:frames()
  if not frames or #frames == 0 then
    return nil
  end

  return frames[1]
end

function Stack:upOf(frameId)
  local index = self._index[frameId]
  if not index or index <= 1 then
    return nil
  end

  return self._frames[index - 1]
end

function Stack:downOf(frameId)
  local index = self._index[frameId]
  if not index or index >= #self._frames then
    return nil
  end

  return self._frames[index + 1]
end

---@param listener fun()
---@param opts? HookOptions
function Stack:onInvalidated(listener, opts)
  return self.hookable:on('invalidated', listener, opts)
end

function Stack:invalidate()
  self.valid = false
  self.hookable:emit('invalidated')
end

return Stack
