-- SourceBinding entity methods for neograph-native
return function(SourceBinding)
  ---Check if this is a reference-based source (not file-based)
  ---@return boolean
  function SourceBinding:isReference()
    return (self.sourceReference:get() or 0) > 0
  end

  ---Check if key matches this source binding
  ---@param key string Source key
  ---@return boolean
  function SourceBinding:matchKey(key)
    local source = self.source:get()
    return source and source.key:get() == key
  end

  ---Get the session-explicit buffer URI for this binding
  ---Returns dap://source/{path}?session={sessionId}
  ---@return string? uri The buffer URI, or nil if missing source/session
  function SourceBinding:bufferUri()
    local source = self.source:get()
    local session = self.session:get()
    if not source or not session then return nil end

    local path = source.path:get() or source.name:get()
    if not path then return nil end

    local session_id = session.sessionId:get()
    return "dap://source/" .. path .. "?session=" .. session_id
  end
end
