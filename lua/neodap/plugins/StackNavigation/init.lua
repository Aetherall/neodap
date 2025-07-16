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
        -- Per-thread navigation state: [session_id][thread_id] = { current_frame_id }
        navigation_states = {},
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
    local current = self:getSmartClosestFrame()
    local parent = current and current:up()
    if parent then
        parent:jump()
        self:updateNavigationState(parent)
        self:emitNavigationEvent(parent, "up")
    end
end

---Navigate down the call stack (towards callee)
function StackNavigation:down()
    local current = self:getSmartClosestFrame()
    local child = current and current:down()
    if child then
        child:jump()
        self:updateNavigationState(child)
        self:emitNavigationEvent(child, "down")
    end
end

---Navigate to top frame (most recent call)
function StackNavigation:top()
    local current = self:getSmartClosestFrame()
    local top = current and current.stack:top()
    if top then
        top:jump()
        self:updateNavigationState(top)
        self:emitNavigationEvent(top, "top")
    end
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

    -- Strategy: Prefer frame closest to current navigation context for the same thread
    for _, candidate in ipairs(candidates) do
        local current_frame = self:validateNavigationContext(candidate.stack.thread)
        if current_frame then
            -- Find frame adjacent to current context in the same thread
            local current_depth = current_frame.ref.id
            local candidate_depth = candidate.ref.id
            if math.abs(candidate_depth - current_depth) <= 1 then
                return candidate
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

    -- Find the current thread based on cursor location
    local current_thread = self:getCurrentThread()
    if not current_thread then
        -- No stopped thread found - fall back to original method
        return self:getClosestFrame(target)
    end

    -- First try to use navigation context if valid for this thread
    local current_frame = self:validateNavigationContext(current_thread)
    if current_frame then
        return current_frame
    end

    -- Get all frames at the target location
    local candidates = self:getFramesAtLocation(target)

    if #candidates == 0 then
        -- No frames at location - fall back to original distance-based selection
        return self:getClosestFrame(target)
    end

    -- Filter candidates to prefer frames from the current thread
    local thread_candidates = {}
    for _, candidate in ipairs(candidates) do
        if candidate.stack.thread.id == current_thread.id then
            table.insert(thread_candidates, candidate)
        end
    end

    -- Use thread-specific candidates if available, otherwise use all candidates
    local final_candidates = #thread_candidates > 0 and thread_candidates or candidates

    -- Use smart candidate selection for multiple frames
    return self:selectBestCandidate(final_candidates, target)
end

-- Navigation State Management Methods

---Get the current thread that the cursor is in
---@return api.Thread?
function StackNavigation:getCurrentThread()
    local cursor_location = Location.fromCursor()
    if not cursor_location then
        return nil
    end

    -- Find the thread that has a frame at the cursor location
    for session in self.api:eachSession() do
        for thread in session:eachThread({ filter = 'stopped' }) do
            local stack = thread:stack()
            if stack then
                for frame in stack:eachFrame({ sourceId = cursor_location.sourceId }) do
                    local frame_location = frame:location()
                    if frame_location and frame_location:distance(cursor_location) < 1000 then
                        return thread
                    end
                end
            end
        end
    end

    -- Fallback: return any stopped thread
    for session in self.api:eachSession() do
        for thread in session:eachThread({ filter = 'stopped' }) do
            return thread
        end
    end

    return nil
end

---Get navigation state for a specific thread
---@param session_id number
---@param thread_id number
---@return table?
function StackNavigation:getThreadNavigationState(session_id, thread_id)
    if not self.navigation_states[session_id] then
        return nil
    end
    return self.navigation_states[session_id][thread_id]
end

---Set navigation state for a specific thread
---@param session_id number
---@param thread_id number
---@param frame_id number
function StackNavigation:setThreadNavigationState(session_id, thread_id, frame_id)
    if not self.navigation_states[session_id] then
        self.navigation_states[session_id] = {}
    end
    self.navigation_states[session_id][thread_id] = {
        current_frame_id = frame_id
    }
end

---Clear navigation state for a specific thread
---@param session_id number
---@param thread_id number
function StackNavigation:clearThreadNavigationState(session_id, thread_id)
    if not self.navigation_states[session_id] then
        return
    end

    local had_state = self.navigation_states[session_id][thread_id] ~= nil
    self.navigation_states[session_id][thread_id] = nil

    -- Clean up empty session entry
    local has_threads = false
    for _ in pairs(self.navigation_states[session_id]) do
        has_threads = true
        break
    end
    if not has_threads then
        self.navigation_states[session_id] = nil
    end

    if had_state then
        self.logger:debug("StackNavigation: Cleared navigation state for thread", thread_id, "in session", session_id)
    end
end

---Validate that the current navigation state is still valid for a specific thread
---@param thread api.Thread
---@return api.Frame?
function StackNavigation:validateNavigationContext(thread)
    local thread_state = self:getThreadNavigationState(thread.session.id, thread.id)
    if not thread_state or not thread_state.current_frame_id then
        return nil
    end

    -- Find the tracked frame in the thread's stack
    local stack = thread:stack()
    if stack then
        for frame in stack:eachFrame() do
            if frame.ref.id == thread_state.current_frame_id then
                return frame
            end
        end
    end

    -- Frame no longer exists - clear state for this thread
    self:clearThreadNavigationState(thread.session.id, thread.id)
    return nil
end

---Update navigation state with current frame
---@param frame api.Frame
function StackNavigation:updateNavigationState(frame)
    self:setThreadNavigationState(frame.stack.thread.session.id, frame.stack.thread.id, frame.ref.id)
    self.logger:debug("StackNavigation: Updated navigation state to frame", frame.ref.id, "in thread",
        frame.stack.thread.id)
end

---Clear navigation state (legacy method - now clears all states)
function StackNavigation:clearNavigationState()
    local had_state = false
    for session_id, session_states in pairs(self.navigation_states) do
        for thread_id, _ in pairs(session_states) do
            had_state = true
            break
        end
        if had_state then break end
    end

    self.navigation_states = {}

    if had_state then
        self.logger:debug("StackNavigation: Cleared all navigation states")
    end
end

---Emit navigation event for other plugins to listen to
---@param frame api.Frame
---@param direction string
function StackNavigation:emitNavigationEvent(frame, direction)
    vim.schedule(function()
        vim.api.nvim_exec_autocmds("User", {
            pattern = "NeodapStackNavigationChanged",
            data = {
                frame_id = frame.ref.id,
                thread_id = frame.stack.thread.id,
                session_id = frame.stack.thread.session.id,
                direction = direction,
                timestamp = os.time()
            }
        })
    end)

    self.logger:debug("StackNavigation: Emitted navigation event", direction, "for frame", frame.ref.id)
end

---Setup reactive listeners for state management
function StackNavigation:setupListeners()
    self.api:onSession(function(session)
        session:onThread(function(thread)
            thread:onStopped(function()
                -- Clear navigation state for this specific thread when it stops (new stop event)
                self:clearThreadNavigationState(session.id, thread.id)
            end)

            thread:onResumed(function()
                -- Clear navigation state for this specific thread when it resumes
                self:clearThreadNavigationState(session.id, thread.id)
            end)
        end)

        session:onTerminated(function()
            -- Clear navigation state for all threads in this session when session terminates
            if self.navigation_states[session.id] then
                for thread_id, _ in pairs(self.navigation_states[session.id]) do
                    self:clearThreadNavigationState(session.id, thread_id)
                end
            end
        end)
    end, { name = self.name .. ".setupListeners" })
end

return StackNavigation