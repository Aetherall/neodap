-- Source entity methods for neograph-native
return function(Source)
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
      -- Fall back to first binding (reference rollup)
      return self.firstBinding:get()
    end

    -- Try focused session first
    local focused = debugger.ctx.session:get()
    if focused then
      local binding = self:findBinding(focused.sessionId:get())
      if binding then return binding end
    end

    -- Fall back to first binding (reference rollup)
    return self.firstBinding:get()
  end

  ---Iterate over active frames at this source (frames in a stack)
  ---Uses the pre-materialized activeFrames collection from schema
  ---@return fun(): any? iterator
  function Source:iterActiveFrames()
    return self.activeFrames:iter()
  end

  ---Check if there are any active frames at a specific line
  ---Uses by_active_line compound index on Source.frames for O(1) lookup
  ---@param line number Line number
  ---@return boolean
  function Source:hasFrameAtLine(line)
    for _ in self.frames:filter({
      filters = {
        { field = "active", op = "eq", value = true },
        { field = "line", op = "eq", value = line },
      }
    }):iter() do
      return true
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
