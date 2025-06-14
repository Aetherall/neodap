local Class = require('neodap.tools.class')

local Frame = require('neodap.api.Session.Frame')
local Hookable = require("neodap.transport.hookable")

---@class api.StackProps
---@field thread api.Thread
---@field _index table<integer, integer> | nil
---@field hookable Hookable

---@class api.Stack: api.StackProps
---@field new Constructor<api.StackProps>
---@field valid boolean
---@field _frames { [integer]: api.Frame? } | nil
local Stack = Class()

---@param thread api.Thread
---@param stack dap.StackTraceResponseBody
function Stack.instanciate(thread, stack)
  local instance = Stack:new({
    thread = thread,
    --- State
    _frames = nil,
    _index = nil,
    hookable = Hookable.create(),
    valid = true,
    --- DAP
    totalFrames = stack.totalFrames,
  })

  -- Initialize frames after the stack is created
  local frames, index = Frame.indexAll(instance, stack.stackFrames)
  instance._frames = frames
  instance._index = index

  return instance
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

  if not self._frames then
    return nil
  end

  local previous = index - 1

  return self._frames[previous]
end

function Stack:downOf(frameId)
  local index = self._index[frameId]
  if not index or index >= #self._frames then
    return nil
  end

  if not self._frames then
    return nil
  end

  local next = index + 1

  return self._frames[next]
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
