local name = "HighlightCurrentFrame"
return {
  name = name,
  description = "Plugin to highlight the current frame in a thread",
  ---@param api Api
  plugin = function(api)
    --- Create the namespace for highlighting

    local namespace = vim.api.nvim_create_namespace(name)

    -- Create the highlight group

    -- vim.api.nvim_set_hl(namespace, "Search")

    -- Register the plugin with the API

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

          local clear = frame:highlight(namespace, "Search")

          thread:onResumed(clear, { once = true })
        end, { name = name .. ".onStopped", priority = 50 })
      end, { name = name .. ".onThread" })
    end, { name = name .. ".onSession" })
  end
}
