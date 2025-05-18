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
          local frames = stack:frames()

          local frame = frames[1] -- Get the first frame (the stopped frame)
          if not frame then
            print("No stopped frame found.")
            return
          end

          frame:jump()
        end, { name = name .. ".onStopped" })
      end, { name = name .. ".onThread" })
    end, { name = name .. ".onSession" })
  end

}
