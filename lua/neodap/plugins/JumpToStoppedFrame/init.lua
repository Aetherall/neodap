local name = "JumpToStoppedFrame"
return {
  name = name,
  description = "Plugin to jump to the stopped frame in a thread",
  ---@param api Api
  plugin = function(api)
    api:onSession(function(session)
      session:onThread(function(thread)
        thread:onStopped(function()
          local stack = thread:stack()
          if not stack then
            return
          end

          local frame = stack:top()

          if not frame then
            return
          end

          frame:jump()
        end, { name = name .. ".onStopped" })
      end, { name = name .. ".onThread" })
    end, { name = name .. ".onSession" })
  end
}
