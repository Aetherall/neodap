local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')
local Location = require('neodap.api.Location')
local NvimAsync = require('neodap.tools.async')

---@class StackNavigationProps
---@field api Api
---@field logger Logger
---@field thread_positions table<integer, StackThreadPosition>
---@field primary_thread_id integer?

---@class StackThreadPosition
---@field current_frame_index integer -- 1-based index into stack frames
---@field stack_size integer -- Total frames available  
---@field last_accessed number -- Timestamp for cleanup prioritization

---@class StackNavigation: StackNavigationProps
---@field new Constructor<StackNavigationProps>
local StackNavigation = Class()

-- Event Handlers

---Handle thread stopped event - initialize stack position tracking
---@param thread api.Thread
---@param body table
function StackNavigation:_onThreadStopped(thread, body)
  self.logger:debug("StackNavigation: Thread", thread.id, "stopped, initializing position tracking")
  
  local stack = thread:stack()
  if not stack then
    self.logger:warn("StackNavigation: No stack available for stopped thread", thread.id)
    return
  end
  
  local frames = stack:frames()
  local stack_size = frames and #frames or 0
  
  if stack_size == 0 then
    self.logger:warn("StackNavigation: Empty stack for thread", thread.id)
    return
  end
  
  -- Initialize or update position tracking
  self.thread_positions[thread.id] = {
    current_frame_index = 1, -- Start at top frame
    stack_size = stack_size,
    last_accessed = os.time()
  }
  
  -- Update primary thread to most recently stopped
  self.primary_thread_id = thread.id
  
  self.logger:info("StackNavigation: Initialized thread", thread.id, "with", stack_size, "frames")
end

---Handle thread resumed event - clear position tracking
---@param thread api.Thread  
---@param body table
function StackNavigation:_onThreadResumed(thread, body)
  self.logger:debug("StackNavigation: Thread", thread.id, "resumed, clearing position tracking")
  
  -- Clear position tracking for this thread
  self.thread_positions[thread.id] = nil
  
  -- Clear primary thread if it was this thread
  if self.primary_thread_id == thread.id then
    self.primary_thread_id = nil
  end
end

---Handle thread exit event - clean up position tracking  
---@param thread api.Thread
---@param body table
function StackNavigation:_onThreadExited(thread, body)
  self.logger:debug("StackNavigation: Thread", thread.id, "exited, cleaning up position tracking")
  
  -- Clean up position tracking for this thread
  self.thread_positions[thread.id] = nil
  
  -- Clear primary thread if it was this thread
  if self.primary_thread_id == thread.id then
    self.primary_thread_id = nil
  end
end

-- Thread Detection Logic

---Find the most relevant thread based on cursor position
---@return api.Thread?, StackThreadPosition?
function StackNavigation:_detectRelevantThread()
  local cursor_location = Location.fromCursor()
  local cursor_bufnr = cursor_location:bufnr()
  
  -- self.logger:debug("StackNavigation: Detecting relevant thread for cursor at", cursor_location:toString())
  
  -- Get all stopped threads with position tracking
  local candidate_threads = {}
  for thread_id, position in pairs(self.thread_positions) do
    local thread = self:_getThreadById(thread_id)
    if thread and thread.stopped then
      table.insert(candidate_threads, { thread = thread, position = position })
    end
  end
  
  if #candidate_threads == 0 then
    self.logger:debug("StackNavigation: No stopped threads available")
    return nil, nil
  end
  
  -- Strategy 1: Find threads with frames at exact cursor position
  if cursor_bufnr then
    for _, candidate in ipairs(candidate_threads) do
      local thread = candidate.thread
      local stack = thread:stack()
      if stack then
        local frames = stack:frames()
        for _, frame in ipairs(frames or {}) do
          if self:_frameMatchesLocation(frame, cursor_location, cursor_bufnr) then
            self.logger:debug("StackNavigation: Found exact match thread", thread.id)
            return thread, candidate.position
          end
        end
      end
    end
  end
  
  -- Strategy 2: Find threads with frames in same file
  if cursor_bufnr then
    for _, candidate in ipairs(candidate_threads) do
      local thread = candidate.thread
      local stack = thread:stack()
      if stack then
        local frames = stack:frames()
        for _, frame in ipairs(frames or {}) do
          if self:_frameInSameBuffer(frame, cursor_bufnr) then
            self.logger:debug("StackNavigation: Found same-file thread", thread.id)
            return thread, candidate.position
          end
        end
      end
    end
  end
  
  -- Strategy 3: Use primary thread (most recently stopped)
  if self.primary_thread_id and self.thread_positions[self.primary_thread_id] then
    local thread = self:_getThreadById(self.primary_thread_id)
    if thread and thread.stopped then
      self.logger:debug("StackNavigation: Using primary thread", self.primary_thread_id)
      return thread, self.thread_positions[self.primary_thread_id]
    end
  end
  
  -- Strategy 4: Use any available stopped thread
  local fallback = candidate_threads[1]
  self.logger:debug("StackNavigation: Using fallback thread", fallback.thread.id)
  return fallback.thread, fallback.position
end

---Check if frame matches the exact cursor location
---@param frame api.Frame
---@param cursor_location api.Location
---@param cursor_bufnr integer
---@return boolean
function StackNavigation:_frameMatchesLocation(frame, cursor_location, cursor_bufnr)
  if not frame.ref.source or not frame.ref.line then
    return false
  end
  
  -- Get source object for frame
  local source_obj = frame.stack.thread.session:getSourceFor(frame.ref.source)
  if not source_obj then
    return false
  end
  
  -- Create location for frame position
  local frame_location
  if source_obj:isFile() then
    frame_location = Location.fromSource(source_obj, {
      line = frame.ref.line,
      column = frame.ref.column or 1
    })
  elseif source_obj:isVirtual() then
    frame_location = Location.fromVirtualSource(source_obj, {
      line = frame.ref.line, 
      column = frame.ref.column or 1
    })
  else
    return false
  end
  
  local frame_bufnr = frame_location:bufnr()
  if frame_bufnr ~= cursor_bufnr then
    return false
  end
  
  -- Check if same line (exact position match)
  return frame.ref.line == cursor_location.line
end

---Check if frame is in the same buffer as cursor
---@param frame api.Frame
---@param cursor_bufnr integer
---@return boolean
function StackNavigation:_frameInSameBuffer(frame, cursor_bufnr)
  if not frame.ref.source then
    return false
  end
  
  -- Get source object for frame
  local source_obj = frame.stack.thread.session:getSourceFor(frame.ref.source)
  if not source_obj then
    return false
  end
  
  -- Create location for frame (just need buffer check)
  local frame_location
  if source_obj:isFile() then
    frame_location = Location.fromSource(source_obj, {
      line = frame.ref.line or 1,
      column = 1
    })
  elseif source_obj:isVirtual() then
    frame_location = Location.fromVirtualSource(source_obj, {
      line = frame.ref.line or 1,
      column = 1  
    })
  else
    return false
  end
  
  local frame_bufnr = frame_location:bufnr()
  return frame_bufnr == cursor_bufnr
end

---Get thread by ID from all sessions
---@param thread_id integer
---@return api.Thread?
function StackNavigation:_getThreadById(thread_id)
  for session in self.api:eachSession() do
    local thread = session._threads and session._threads[thread_id]
    if thread then
      return thread
    end
  end
  return nil
end

-- Public Navigation API

---Move up the call stack (towards caller)
function StackNavigation:up()
  NvimAsync.run(function ()
    local thread, position = self:_detectRelevantThread()
    if not thread or not position then
      self.logger:warn("StackNavigation: No relevant thread found for up navigation")
      return
    end
    
    if position.current_frame_index >= position.stack_size then
      self.logger:debug("StackNavigation: Already at bottom of stack")
      return
    end
    
    -- Move down in the stack array (towards bottom/caller)
    position.current_frame_index = position.current_frame_index + 1
    position.last_accessed = os.time()
    
    self:_jumpToCurrentFrame(thread, position)
  end)
end

---Move down the call stack (towards callee)  
function StackNavigation:down()
  NvimAsync.run(function ()
    local thread, position = self:_detectRelevantThread()
    if not thread or not position then
      self.logger:warn("StackNavigation: No relevant thread found for down navigation")
      return
    end
    
    if position.current_frame_index <= 1 then
      self.logger:debug("StackNavigation: Already at top of stack")
      return
    end
    
    -- Move up in the stack array (towards top/callee)
    position.current_frame_index = position.current_frame_index - 1
    position.last_accessed = os.time()
    
     self:_jumpToCurrentFrame(thread, position)
  end)
end

---Jump to top frame (most recent call)
function StackNavigation:top()
  NvimAsync.run(function ()
    local thread, position = self:_detectRelevantThread()
    if not thread or not position then
      self.logger:warn("StackNavigation: No relevant thread found for top navigation")
      return
    end
    
    position.current_frame_index = 1
    position.last_accessed = os.time()
    
    self:_jumpToCurrentFrame(thread, position)
  end)
end

---Jump to bottom frame (program entry)
function StackNavigation:bottom()
NvimAsync.run(function ()
  local thread, position = self:_detectRelevantThread()
  if not thread or not position then
    self.logger:warn("StackNavigation: No relevant thread found for bottom navigation")
    return
  end
  
  position.current_frame_index = position.stack_size
  position.last_accessed = os.time()

  self:_jumpToCurrentFrame(thread, position)
end)
end

---Jump to specific frame index
---@param index integer 1-based frame index
---@return boolean success
function StackNavigation:jumpToFrame(index)
  local thread, position = self:_detectRelevantThread()
  if not thread or not position then
    self.logger:warn("StackNavigation: No relevant thread found for frame jump")
    return false
  end
  
  if index < 1 or index > position.stack_size then
    self.logger:warn("StackNavigation: Frame index", index, "out of bounds (1 to", position.stack_size, ")")
    return false
  end
  
  position.current_frame_index = index
  position.last_accessed = os.time()
  
  return self:_jumpToCurrentFrame(thread, position)
end

-- Frame Navigation Helper

---Jump to the current frame for a thread
---@param thread api.Thread
---@param position StackThreadPosition
---@return boolean success
function StackNavigation:_jumpToCurrentFrame(thread, position)
  local stack = thread:stack()
  if not stack then
    self.logger:error("StackNavigation: No stack available for thread", thread.id)
    return false
  end
  
  local frames = stack:frames()
  if not frames or #frames == 0 then
    self.logger:error("StackNavigation: No frames available for thread", thread.id)
    return false
  end
  
  local frame = frames[position.current_frame_index]
  if not frame then
    self.logger:error("StackNavigation: Frame", position.current_frame_index, "not found")
    return false
  end
  
  self.logger:info("StackNavigation: Jumping to frame", position.current_frame_index, "of", position.stack_size, "in thread", thread.id)
  frame:jump()
  return true
end

-- Information Methods

---Get current frame object
---@return api.Frame?
function StackNavigation:getCurrentFrame()
  local thread, position = self:_detectRelevantThread()
  if not thread or not position then
    return nil
  end
  
  local stack = thread:stack()
  if not stack then
    return nil
  end
  
  local frames = stack:frames()
  if not frames then
    return nil
  end
  
  return frames[position.current_frame_index]
end

---Get current position information
---@return { thread_id: integer, frame_index: integer, stack_size: integer }?
function StackNavigation:getCurrentPosition()
  local thread, position = self:_detectRelevantThread()
  if not thread or not position then
    return nil
  end
  
  return {
    thread_id = thread.id,
    frame_index = position.current_frame_index,
    stack_size = position.stack_size
  }
end

---Get stack information for relevant thread
---@return { thread_id: integer, frames: api.Frame[], current_index: integer }?
function StackNavigation:getStackInfo()
  local thread, position = self:_detectRelevantThread()
  if not thread or not position then
    return nil
  end
  
  local stack = thread:stack()
  if not stack then
    return nil
  end
  
  local frames = stack:frames()
  if not frames then
    return nil
  end
  
  return {
    thread_id = thread.id,
    frames = frames,
    current_index = position.current_frame_index
  }
end

local name = "StackNavigation"

return {
  name = name,
  description = "Navigate through call stacks of stopped threads with cursor awareness",
  
  ---@param api Api
  plugin = function(api)
    local logger = Logger.get()
    
    local instance = StackNavigation:new({
      api = api,
      logger = logger,
      thread_positions = {},
      primary_thread_id = nil
    })
    
    -- Set up hierarchical event handling
    api:onSession(function(session)
      session:onThread(function(thread)
        -- When thread stops, initialize/update position tracking
        thread:onStopped(function(body)
          instance:_onThreadStopped(thread, body)
        end, { name = name .. ".onStopped" })
        
        -- When thread resumes, clear stack position tracking
        thread:onResumed(function(body)
          instance:_onThreadResumed(thread, body)
        end, { name = name .. ".onResumed" })
        
        -- When thread exits, clean up position tracking
        thread:onExited(function(body)
          instance:_onThreadExited(thread, body)
        end, { name = name .. ".onExited" })
        
      end, { name = name .. ".onThread" })
    end, { name = name .. ".onSession" })
    
    return instance
  end
}