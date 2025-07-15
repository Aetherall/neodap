local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local NvimAsync = require("neodap.tools.async")

---@class neodap.plugin.StackNavigationProps
---@field api Api
---@field logger Logger

---@class neodap.plugin.StackNavigation: neodap.plugin.StackNavigationProps
---@field new Constructor<neodap.plugin.StackNavigationProps>
local StackNavigation = Class()

StackNavigation.name = "StackNavigation"
StackNavigation.description = "Navigate through call stacks with cursor awareness"

function StackNavigation.plugin(api)
  local logger = Logger.get()

  local instance = StackNavigation:new({
    api = api,
    logger = logger,
    navigation_state = {
      current_frame_id = nil,
      thread_id = nil,
      session_id = nil,
    },
  })
  
  instance:setupListeners()
  return instance
end

---@param location api.Location?
---@return api.Frame?
function StackNavigation:getClosestFrame(location)
  local target = location or Location.fromCursor()

  local closest = nil
  local closest_distance = math.huge
  
  -- Find frame closest to cursor across all sessions and threads
  for session in self.api:eachSession() do
    for thread in session:eachThread({ filter = 'stopped' }) do
      local stack = thread:stack()
      if stack then
        for frame in stack:eachFrame({ sourceId = target.sourceId }) do
          local location = frame:location()
          if location then
            local distance = location:distance(target)
            if distance < closest_distance then
              closest_distance = distance
              closest = frame
            end
          end
        end
      end
    end
  end

  self.logger:debug("Closest frame is ", closest and closest:location().key, " at distance ", closest_distance)

  self.logger:debug("StackNavigation: Closest frame found:", vim.inspect(closest and closest.ref))
  return closest
end

---Navigate up the call stack (towards caller)
function StackNavigation:up()
  NvimAsync.run(function()
    local current = self:getSmartClosestFrame()
    local parent = current and current:up()
    if parent then 
      parent:jump()
      self:updateNavigationState(parent)
    end 
  end)
end

---Navigate down the call stack (towards callee)
function StackNavigation:down()
  NvimAsync.run(function()
    local current = self:getSmartClosestFrame()
    local child = current and current:down()
    if child then 
      child:jump()
      self:updateNavigationState(child)
    end 
  end)
end

---Navigate to top frame (most recent call)
function StackNavigation:top()
  NvimAsync.run(function()
    local current = self:getSmartClosestFrame()
    local top = current and current.stack:top()
    if top then 
      top:jump()
      self:updateNavigationState(top)
    end
  end)
end

-- Smart Selection Methods

---Get all frames at the given location
---@param location api.Location
---@return api.Frame[]
function StackNavigation:getFramesAtLocation(location)
  local frames = {}
  
  for session in self.api:eachSession() do
    for thread in session:eachThread({ filter = 'stopped' }) do
      local stack = thread:stack()
      if stack then
        for frame in stack:eachFrame({ sourceId = location.sourceId }) do
          local frame_location = frame:location()
          if frame_location and frame_location:distance(location) < 1000 then -- same line tolerance
            table.insert(frames, frame)
          end
        end
      end
    end
  end
  
  return frames
end

---Select the best candidate from multiple frames at the same location
---@param candidates api.Frame[]
---@param location api.Location
---@return api.Frame?
function StackNavigation:selectBestCandidate(candidates, location)
  if #candidates == 0 then
    return nil
  elseif #candidates == 1 then
    return candidates[1]
  end
  
  -- Sort candidates by stack depth (topmost first)
  table.sort(candidates, function(a, b) return a.ref.id < b.ref.id end)
  
  -- Strategy: Prefer frame closest to current navigation context
  local current_frame = self:validateNavigationContext()
  if current_frame then
    -- Find frame adjacent to current context
    for _, candidate in ipairs(candidates) do
      if candidate.stack.thread.id == current_frame.stack.thread.id then
        -- Same thread - prefer frames close to current depth
        local current_depth = current_frame.ref.id
        local candidate_depth = candidate.ref.id
        if math.abs(candidate_depth - current_depth) <= 1 then
          return candidate
        end
      end
    end
  end
  
  -- Default strategy: return topmost frame (most recent call)
  -- This gives users a predictable starting point for recursive functions
  return candidates[1]
end

---Get the smart closest frame, considering navigation context
---@param location api.Location?
---@return api.Frame?
function StackNavigation:getSmartClosestFrame(location)
  local target = location or Location.fromCursor()
  
  -- First try to use navigation context if valid
  local current_frame = self:validateNavigationContext()
  if current_frame then
    return current_frame
  end
  
  -- Get all frames at the target location
  local candidates = self:getFramesAtLocation(target)
  
  if #candidates == 0 then
    -- No frames at location - fall back to original distance-based selection
    return self:getClosestFrame(target)
  end
  
  -- Use smart candidate selection for multiple frames
  return self:selectBestCandidate(candidates, target)
end

-- Navigation State Management Methods

---Validate that the current navigation state is still valid
---@return api.Frame?
function StackNavigation:validateNavigationContext()
  if not self.navigation_state.current_frame_id then
    return nil
  end
  
  -- Find the tracked frame in current thread state
  for session in self.api:eachSession() do
    if session.id == self.navigation_state.session_id then
      for thread in session:eachThread({ filter = 'stopped' }) do
        if thread.id == self.navigation_state.thread_id then
          local stack = thread:stack()
          if stack then
            for frame in stack:eachFrame() do
              if frame.ref.id == self.navigation_state.current_frame_id then
                return frame
              end
            end
          end
        end
      end
    end
  end
  
  -- Frame no longer exists - clear state
  self:clearNavigationState()
  return nil
end

---Update navigation state with current frame
---@param frame api.Frame
function StackNavigation:updateNavigationState(frame)
  self.navigation_state.current_frame_id = frame.ref.id
  self.navigation_state.thread_id = frame.stack.thread.id
  self.navigation_state.session_id = frame.stack.thread.session.id
  
  self.logger:debug("StackNavigation: Updated navigation state to frame", frame.ref.id, "in thread", frame.stack.thread.id)
end

---Clear navigation state
function StackNavigation:clearNavigationState()
  local had_state = self.navigation_state.current_frame_id ~= nil
  
  self.navigation_state.current_frame_id = nil
  self.navigation_state.thread_id = nil
  self.navigation_state.session_id = nil
  
  if had_state then
    self.logger:debug("StackNavigation: Cleared navigation state")
  end
end

---Setup reactive listeners for state management
function StackNavigation:setupListeners()
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function()
        -- Clear navigation state when thread stops (new stop event)
        self:clearNavigationState()
      end)
      
      thread:onResumed(function()
        -- Clear navigation state when thread resumes
        self:clearNavigationState()
      end)
    end)
    
    session:onTerminated(function()
      -- Clear navigation state when session terminates
      if self.navigation_state.session_id == session.id then
        self:clearNavigationState()
      end
    end)
  end, { name = self.name .. ".setupListeners" })
end

return StackNavigation