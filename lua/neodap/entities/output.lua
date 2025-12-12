-- Output entity methods for neograph-native
local Location = require("neodap.location")
local uri = require("neodap.uri")

return function(Output)

  --------------------------------------------------------------------------
  -- Class-level state: output sequence counters
  --------------------------------------------------------------------------

  -- Per-session output sequence (weak-keyed so terminated sessions are GC'd)
  Output._seqs = setmetatable({}, { __mode = "k" })

  -- Global output sequence counter (ordering across sessions)
  Output._global_seq = 0

  ---Get next per-session sequence number
  ---@param session table Session entity
  ---@return number
  function Output.next_seq(session)
    Output._seqs[session] = (Output._seqs[session] or 0) + 1
    return Output._seqs[session]
  end

  ---Get next global sequence number
  ---@return number
  function Output.next_global_seq()
    Output._global_seq = Output._global_seq + 1
    return Output._global_seq
  end

  ---Initialize sequence counter for a new session
  ---@param session table Session entity
  function Output.init_seqs(session)
    Output._seqs[session] = 0
  end

  --------------------------------------------------------------------------
  -- Class method: create and link an Output entity (protected, never throws)
  --------------------------------------------------------------------------

  ---Create an Output entity linked to a session
  ---@param session table Session entity
  ---@param text string Output text
  ---@param category string Output category ("repl", "stdout", "stderr", etc.)
  ---@param extra? table Additional output fields (variablesReference, etc.)
  function Output.create(session, text, category, extra)
    pcall(function()
      local graph = session._graph
      local session_id = session.sessionId:get()
      local seq = Output.next_seq(session)

      local props = {
        uri = uri.output(session_id, seq),
        seq = seq,
        globalSeq = Output.next_global_seq(),
        text = text,
        category = category,
        visible = true,
        matched = true,
      }
      if extra then
        for k, v in pairs(extra) do props[k] = v end
      end

      local output = Output.new(graph, props)
      session.outputs:link(output)
      session.allOutputs:link(output)

      local log_dir = session.logDir:get()
      if log_dir then
        local f = io.open(log_dir .. "/output.log", "a")
        if f then
          f:write(text)
          f:close()
        end
      end
    end)
  end

  --------------------------------------------------------------------------
  -- Instance methods
  --------------------------------------------------------------------------

  ---Get location as Location object (supports virtual sources via bufferUri)
  ---@return neodap.Location?
  function Output:location()
    return Location.fromEntity(self)
  end

  ---Check if output's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Output:isSessionTerminated()
    local session = self.session:get()
    if not session then return true end
    return session:isTerminated()
  end
end
