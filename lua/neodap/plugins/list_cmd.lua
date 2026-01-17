-- Plugin: DapList command for listing DAP entities in quickfix
--
-- Usage:
--   :DapList breakpoints                    - list all breakpoints
--   :DapList breakpoints(enabled=true)      - list enabled breakpoints
--   :DapList @session/threads               - threads in focused session
--   :DapList @thread/stack/frames    - frames in current stack

local quickfix = require("neodap.plugins.utils.quickfix")
local url_completion = require("neodap.plugins.utils.url_completion")

---@class neodap.plugins.DapListConfig
---@field open_quickfix? boolean Whether to open quickfix after list (default: true)

---@param debugger neodap.entities.Debugger
---@param config? neodap.plugins.DapListConfig
---@return table api Plugin API
return function(debugger, config)
  config = config or {}
  local open_quickfix = config.open_quickfix ~= false

  local api = {}

  -- Re-export for backwards compatibility
  api.to_quickfix = quickfix.entry

  ---List entities matching a URL query
  ---@param url string URL query string
  ---@return boolean success
  function api.list(url)
    if not url or url == "" then
      vim.notify("DapList: Missing URL", vim.log.levels.ERROR)
      return false
    end

    local entities = debugger:query(url)

    if not entities then
      vim.notify("DapList: Invalid URL: " .. url, vim.log.levels.ERROR)
      return false
    end

    -- Handle single entity result
    if type(entities) ~= "table" or entities.uri then
      entities = { entities }
    end

    if #entities == 0 then
      vim.notify("DapList: No matches for " .. url, vim.log.levels.INFO)
      return true
    end

    local items = {}
    for _, entity in ipairs(entities) do
      local item = api.to_quickfix(entity)
      if item then
        table.insert(items, item)
      end
    end

    vim.fn.setqflist(items, "r")
    vim.fn.setqflist({}, "a", { title = "Dap: " .. url })

    if open_quickfix then
      vim.cmd("copen")
    end

    vim.notify(string.format("DapList: %d items", #items), vim.log.levels.INFO)
    return true
  end

  -- Create user command
  vim.api.nvim_create_user_command("DapList", function(opts)
    api.list(opts.args)
  end, {
    nargs = "+",
    desc = "List DAP entities in quickfix",
    complete = url_completion.create_completer(debugger, "DapList"),
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapList")
  end

  return api
end
