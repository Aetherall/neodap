-- Source entity methods for neograph-native
local Location = require("neodap.location")

return function(Source)
  ---Get location as Location object (file-only, no line/column, supports virtual sources)
  ---@return neodap.Location?
  function Source:location()
    local uri = self:bufferUri()
    if not uri then return nil end
    return Location.new(uri)
  end

  ---Get display name (name or basename of path)
  ---@return string
  function Source:displayName()
    local name = self.name:get()
    if name and name ~= "" then
      return name
    end
    local path = self.path:get() or ""
    return path:match("([^/\\]+)$") or path
  end

  ---Check if key matches this source
  ---@param key string
  ---@return boolean
  function Source:matchKey(key)
    return self.key:get() == key
  end

  ---Check if this source is virtual (needs to be fetched from debug adapter)
  ---A source is virtual if any of its bindings has a sourceReference > 0
  ---@return boolean
  function Source:isVirtual()
    for binding in self.bindings:iter() do
      local ref = binding.sourceReference:get()
      if ref and ref > 0 then
        return true
      end
    end
    return false
  end

  ---Get the buffer URI for this source
  ---Returns file path if it exists on disk, otherwise dap://source/source:{key} for virtual sources
  ---@return string? uri Buffer URI or nil if no path
  function Source:bufferUri()
    -- Prefer real file if it exists, even for virtual sources
    local path = self.path:get()
    if path and vim.fn.filereadable(path) == 1 then
      return path
    end

    -- Fall back to virtual source URI
    if self:isVirtual() then
      local key = self.key:get()
      if not key then return nil end
      return "dap://source/source:" .. key
    end

    return path
  end

  ---Find binding for a specific session
  ---@param session_id string Session ID
  ---@return neodap.entities.SourceBinding?
  function Source:findBinding(session_id)
    for binding in self.bindings:iter() do
      local session = binding.session:get()
      if session and session.sessionId:get() == session_id then
        return binding
      end
    end
    return nil
  end

  ---Resolve binding based on context (focused session, first available)
  ---@return neodap.entities.SourceBinding?
  function Source:bindingForContext()
    local debugger = self.debugger:get()
    if not debugger then
      -- Fall back to first binding
      for binding in self.bindings:iter() do
        return binding
      end
      return nil
    end

    -- Try focused session first
    local focused = debugger.ctx.session:get()
    if focused then
      local binding = self:findBinding(focused.sessionId:get())
      if binding then return binding end
    end

    -- Fall back to first binding
    for binding in self.bindings:iter() do
      return binding
    end
    return nil
  end

  ---Iterate over all frames at this source
  ---@return fun(): any? iterator
  function Source:iterFrames()
    return self.frames:iter()
  end

  ---Iterate over active frames at this source (frames in a stack)
  ---@return fun(): any? iterator
  function Source:iterActiveFrames()
    local frame_iter = self.frames:iter()
    return function()
      for frame in frame_iter do
        if frame:isActive() then
          return frame
        end
      end
      return nil
    end
  end

  ---Iterate over top frames at this source (index 0 in active stacks)
  ---@return fun(): any? iterator
  function Source:iterTopFrames()
    local frame_iter = self.frames:iter()
    return function()
      for frame in frame_iter do
        if frame:isActive() and frame:isTop() then
          return frame
        end
      end
      return nil
    end
  end

  ---Get all active frames at a specific line
  ---@param line number Line number
  ---@return any[] frames Array of frames at this line
  function Source:framesAtLine(line)
    local result = {}
    for frame in self:iterActiveFrames() do
      if frame.line:get() == line then
        table.insert(result, frame)
      end
    end
    return result
  end

  ---Check if there are any active frames at a specific line
  ---@param line number Line number
  ---@return boolean
  function Source:hasFrameAtLine(line)
    for frame in self:iterActiveFrames() do
      if frame.line:get() == line then
        return true
      end
    end
    return false
  end

  ---Find the closest active frame to a given line
  ---@param line number Target line number
  ---@return any? frame Closest frame or nil
  function Source:closestFrame(line)
    local best, best_dist = nil, math.huge
    for frame in self:iterActiveFrames() do
      local frame_line = frame.line:get() or 0
      local dist = math.abs(frame_line - line)
      if dist < best_dist then
        best_dist, best = dist, frame
      end
    end
    return best
  end
end
