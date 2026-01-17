-- Plugin: Polyfill for adapters that don't send hitBreakpointIds
--
-- The DAP spec says adapters SHOULD send hitBreakpointIds in stopped events
-- when reason="breakpoint", but many adapters (like debugpy) don't.
-- This plugin infers hit state from frame location when hitBreakpointIds is missing.

---@param debugger neodap.entities.Debugger
return function(debugger)
  -- Subscribe to sources with breakpoints
  debugger.sources:each(function(source)
    -- Subscribe to frames on this source (fires after source link is established)
    source.frames:each(function(frame)
      -- Only process top frame (index 0)
      if frame.index:get() ~= 0 then return end

      -- Get session from frame's stack
      local stack = frame.stack:get()
      if not stack then return end
      local thread = stack.thread:get()
      if not thread then return end
      local session = thread.session:get()
      if not session then return end

      -- Only when session is stopped
      if session.state:get() ~= "stopped" then return end

      -- Check if any binding already has hit=true (adapter sent hitBreakpointIds)
      for sb in session.sourceBindings:iter() do
        for binding in sb.breakpointBindings:iter() do
          if binding.hit:get() == true then
            return -- Adapter already marked hit, no polyfill needed
          end
        end
      end

      local line = frame.line:get()
      if not line then return end

      -- Find matching breakpoint binding at this line for this session
      for bp in source.breakpoints:iter() do
        if bp:isEnabled() then
          for binding in bp.bindings:iter() do
            if binding.verified:get() then
              local actual_line = binding.actualLine:get() or bp.line:get()
              if actual_line == line then
                local sb = binding.sourceBinding:get()
                if sb and sb.session:get() == session then
                  binding:update({ hit = true })
                  return
                end
              end
            end
          end
        end
      end
    end)
  end)

  return {}
end
