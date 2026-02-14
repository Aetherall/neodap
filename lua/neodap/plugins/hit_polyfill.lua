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

      local session = frame:session()
      if not session then return end

      -- Only when session is stopped
      if session.state:get() ~= "stopped" then return end

      -- Check if any binding already has hit=true (adapter sent hitBreakpointIds)
      local has_hit = false
      session:forEachBreakpointBinding(function(bpb)
        if bpb.hit:get() == true then
          has_hit = true
        end
      end)
      if has_hit then return end

      local line = frame.line:get()
      if not line then return end

      -- Find matching breakpoint binding at this line for this session
      -- Uses by_line index on Source.breakpoints for O(1) line lookup
      for bp in source.breakpoints:filter({
        filters = {{ field = "line", op = "eq", value = line }}
      }):iter() do
        if bp:isEnabled() then
          -- Uses by_verified index on Breakpoint.bindings
          for binding in bp.bindings:filter({
            filters = {{ field = "verified", op = "eq", value = true }}
          }):iter() do
            local sb = binding.sourceBinding:get()
            if sb and sb.session:get() == session then
              binding:update({ hit = true })
              return
            end
          end
        end
      end
    end)
  end)

  return {}
end
