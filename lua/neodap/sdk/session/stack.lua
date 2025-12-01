---@class Stack : Class
---@field thread Thread
---@field id string
---@field uri string
---@field sequence number  -- Monotonically increasing sequence number
---@field timestamp number
---@field reason string
---@field frames Collection<Frame>
---@field get_index fun(self: Stack): number  -- Relative index: 0 = latest (newest), increasing for older

local neostate = require("neostate")
local Frame = require("neodap.sdk.session.frame")

local M = {}

---@class Stack : Class
local Stack = neostate.Class("Stack")

function Stack:init(thread, frames_data, reason, sequence)
  self.thread = thread
  self.timestamp = vim.loop.now()
  self.reason = reason
  self.sequence = sequence

  -- URI and key for EntityStore
  self.uri = string.format(
    "dap:session:%s/thread:%d/stack:%d",
    thread.session.id,
    thread.id,
    sequence
  )
  self.id = self.uri -- Use URI as ID
  self.key = "stack:" .. sequence
  self._type = "stack"

  -- Eager expansion: stacks auto-expand in tree views
  self.eager = true

  -- Track if this stack is current or stale
  self._is_current = self:signal(true, "is_current")

  -- Reactive index: 0 = latest (newest), increasing for older stacks
  -- Index updates are managed reactively by Debugger.stacks:on_added()
  self.index = self:signal(0, "index")

  local debugger = thread.session.debugger

  -- Add to EntityStore (no edges yet - we'll add parent edge with prepend)
  debugger.store:add(self, "stack", {})
  -- Use prepend_edge so newer stacks appear above older ones in tree view
  debugger.store:prepend_edge(self.uri, "parent", thread.uri)
  -- Add children edge from thread to stack (for follow traversal)
  debugger.store:prepend_edge(thread.uri, "stacks", self.uri)

  -- Create frame objects
  for i, frame_data in ipairs(frames_data) do
    local frame = Frame.Frame:new(self, frame_data, i - 1)

    -- Add to EntityStore with parent edge to stack
    debugger.store:add(frame, "frame", {
      { type = "parent", to = self.uri }
    })
    -- Add children edge from stack to frame (for follow traversal)
    debugger.store:add_edge(self.uri, "frames", frame.uri)
  end
end

---Get filtered frames for this stack
---@return table Filtered collection of frames
function Stack:frames()
  if not self._frames then
    local debugger = self.thread.session.debugger
    self._frames = debugger.frames:where(
      "by_stack_id",
      self.id,
      "Frames:Stack:" .. self.id
    )
  end
  return self._frames
end

---Get top frame
---@return Frame?
function Stack:top()
  return self:frames():get_one("by_index", 0)
end

---Check if this stack is current (not stale)
---@return boolean
function Stack:is_current()
  return self._is_current:get()
end

---Get the relative index of this stack (0 = latest, increasing for older)
---@return number
function Stack:get_index()
  return self.index:get()
end

---Mark this stack as expired (no longer current)
---Propagates expiration to all frames, scopes, and variables
---@private
function Stack:_mark_expired()
  self._is_current:set(false)
  -- Mark all frames in this stack as expired
  for frame in self:frames():iter() do
    frame:_mark_expired()
  end
end

-- =============================================================================
-- LIFECYCLE HOOKS
-- =============================================================================

---Register callback for when this stack expires (becomes stale)
---@param fn function  -- Called with no arguments
---@return function unsubscribe
function Stack:onExpired(fn)
  return self._is_current:watch(function(is_current)
    if not is_current then
      fn()
    end
  end)
end

---Register callback for frames in this stack
---@param fn function  -- Called with (frame)
---@return function unsubscribe
function Stack:onFrame(fn)
  return self:frames():each(fn)
end

M.Stack = Stack

-- Backwards compatibility
function M.create(thread, frame_data, reason)
  return Stack:new(thread, frame_data, reason)
end

return M
