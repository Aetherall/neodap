local Class      = require('neodap.tools.class')
local Frame      = require('neodap.api.Session.Frame')
local Collection = require("neodap.tools.Collection")
local Hookable   = require("neodap.transport.hookable")
local Frames     = require("neodap.api.Session.Frames")

---@class api.StackProps
---@field thread api.Thread
---@field hookable Hookable

---@class api.Stack: api.StackProps
---@field new Constructor<api.StackProps>
---@field valid boolean
---@field frames api.Frames
local Stack      = Class()

---@param thread api.Thread
---@param stack dap.StackTraceResponseBody
---@param parentHookable? Hookable
function Stack.instanciate(thread, stack, parentHookable)
  local instance = Stack:new({
    thread = thread,
    valid = true,
    frames = Frames.create(),
    totalFrames = stack.totalFrames,
    hookable = Hookable.create(parentHookable)
  })

  -- Add frames to collection
  for _i, frameData in ipairs(stack.stackFrames) do
    local frame = Frame.instanciate(instance, frameData)
    instance.frames:add(frame)
  end

  return instance
end

---@return Collection?
function Stack:getFrames()
  if not self.valid then
    return nil
  end

  if self.frames and not self.frames:isEmpty() then
    return self.frames
  end

  local trace = self.thread.session.ref.calls:stackTrace({ threadId = self.thread.id }):wait()

  -- Clear and repopulate frames collection
  self.frames:clear()
  for _i, frameData in ipairs(trace.stackFrames) do
    local frame = Frame.instanciate(self, frameData)
    self.frames:add(frame)
  end

  return self.frames
end

---@param opts { sourceId: SourceIdentifier? }?
---@return fun(): api.Frame?
function Stack:eachFrame(opts)
  if not self.valid then
    return function() return nil end
  end

  local frames = self:getFrames()
  if not frames or frames:isEmpty() then
    return function() return nil end
  end

  if opts and opts.sourceId then
    -- Filter frames by sourceId
    local filteredFrames = frames:filter(function(frame)
      local location = frame:location()
      return location and location.sourceId:equals(opts.sourceId)
    end)
    return filteredFrames:each()
  else
    return frames:each()
  end
end

function Stack:top()
  if not self.valid then
    return nil
  end

  local frames = self:getFrames()
  if not frames or frames:isEmpty() then
    return nil
  end

  return frames:first()
end

function Stack:upOf(frameId)
  local frames = self:getFrames()
  if not frames or frames:isEmpty() then
    return nil
  end

  -- Find current frame and its position using Collection's indexOf
  local currentFrame = frames:getBy("id", frameId)
  if not currentFrame then
    return nil
  end

  local position = frames:indexOf(currentFrame)
  if not position or position <= 1 then
    return nil
  end

  local previous = position - 1
  return frames:at(previous)
end

function Stack:downOf(frameId)
  local frames = self:getFrames()
  if not frames or frames:isEmpty() then
    return nil
  end

  -- Find current frame and its position using Collection's indexOf
  local currentFrame = frames:getBy("id", frameId)
  if not currentFrame then
    return nil
  end

  local position = frames:indexOf(currentFrame)
  if not position or position >= frames:count() then
    return nil
  end

  local next = position + 1
  return frames:at(next)
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

--- Destroys this stack and all its child resources
--- This method ensures complete cleanup of frames and handlers
function Stack:destroy()
  -- Clean up frames using Collection methods directly
  if self.frames then
    self.frames:each(function(frame)
      if frame.destroy then frame:destroy() end
    end)
    self.frames:clear()
  end

  -- Clean up hookable
  if self.hookable and not self.hookable.destroyed then
    self.hookable:destroy()
  end

  self.valid = false
end

return Stack
