-- Plugin: DapFocus command for focusing debug entities
--
-- Usage:
--   :DapFocus /sessions                  - pick session to focus (if multiple)
--   :DapFocus @session/threads           - pick thread to focus
--   :DapFocus @session/threads[0]        - focus first thread (no picker)
--   :DapFocus sessions[0]                - focus first session

local url_completion = require("neodap.plugins.utils.url_completion")
local uri_picker = require("neodap.plugins.uri_picker")

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  local picker = uri_picker(debugger)
  local api = {}

  ---Focus an entity by URL (shows picker if multiple results)
  ---@param url string URL to query
  ---@param callback? fun(success: boolean) Optional callback for async picker
  ---@return boolean? success Returns immediately for single result, nil for picker
  function api.focus(url, callback)
    if not url or url == "" then
      vim.notify("DapFocus: Missing URL", vim.log.levels.ERROR)
      if callback then callback(false) end
      return false
    end

    picker:resolve(url, function(entity)
      if not entity then
        vim.notify("DapFocus: No entity found for: " .. url, vim.log.levels.WARN)
        if callback then callback(false) end
        return
      end

      local entity_type = entity:type()

      if entity_type == "Frame" or entity_type == "Thread" or entity_type == "Session" then
        debugger.ctx:focus(entity.uri:get())
        if callback then callback(true) end
      else
        vim.notify("DapFocus: Cannot focus " .. entity_type, vim.log.levels.WARN)
        if callback then callback(false) end
      end
    end)
  end

  vim.api.nvim_create_user_command("DapFocus", function(opts)
    api.focus(opts.args)
  end, {
    nargs = "+",
    desc = "Focus a debug entity",
    complete = url_completion.create_completer(debugger, "DapFocus"),
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapFocus")
  end

  return api
end
