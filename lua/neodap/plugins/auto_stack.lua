-- Plugin: Automatically fetch stack trace when a thread stops
-- Ensures frame data is available immediately after breakpoints/stepping
-- Also pins default context to top frame for frame_highlights

local neostate = require("neostate")

---@param debugger Debugger
---@return function cleanup
return function(debugger)
  return debugger:onThread(function(thread)
    return thread:onStopped(function()
      neostate.void(function()
        local stack = thread:stack()
        if stack then
          local top_frame = stack:top()
          if top_frame then
            -- Pin default context to top frame for frame_highlights
            debugger:context():pin(top_frame.uri)
          end
        end
      end)()
    end)
  end)
end
