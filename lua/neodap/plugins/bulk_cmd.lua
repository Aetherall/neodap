-- Plugin: DapEnable, DapDisable, and DapRemove commands for URL-based bulk operations
--
-- Usage:
--   :DapEnable                             - enable entity at current quickfix position
--   :DapEnable breakpoints                 - enable all breakpoints
--   :DapEnable breakpoints(enabled=false)  - enable disabled breakpoints
--   :DapDisable                            - disable entity at current quickfix position
--   :DapDisable breakpoints                - disable all breakpoints
--   :DapRemove                             - remove entity at current quickfix position
--   :DapRemove breakpoints                 - remove all breakpoints

local query = require("neodap.plugins.utils.query")
local url_completion = require("neodap.plugins.utils.url_completion")
local log = require("neodap.logger")
local E = require("neodap.error")

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  local api = {}

  ---Enable entities (typically breakpoints).
  ---Throws on failure (caught by E.create_command).
  ---@param url? string Optional URL to query
  function api.enable(url)
    local entities = query.query_or_quickfix(debugger, url)
    if #entities == 0 then
      error(E.warn("DapEnable: No entities found"), 0)
    end

    local count = 0
    for _, entity in ipairs(entities) do
      if entity.enable then
        entity:enable()
        count = count + 1
      end
    end

    if count == 0 then
      error(E.warn("DapEnable: No entities support enable"), 0)
    end
  end

  ---Disable entities (typically breakpoints).
  ---Throws on failure (caught by E.create_command).
  ---@param url? string Optional URL to query
  function api.disable(url)
    local entities = query.query_or_quickfix(debugger, url)
    if #entities == 0 then
      error(E.warn("DapDisable: No entities found"), 0)
    end

    local count = 0
    for _, entity in ipairs(entities) do
      if entity.disable then
        entity:disable()
        count = count + 1
      end
    end

    if count == 0 then
      error(E.warn("DapDisable: No entities support disable"), 0)
    end
  end

  ---Remove entities (typically breakpoints).
  ---Throws on failure (caught by E.create_command).
  ---@param url? string Optional URL to query
  function api.remove(url)
    local entities = query.query_or_quickfix(debugger, url)
    if #entities == 0 then
      error(E.warn("DapRemove: No entities found"), 0)
    end

    local count = 0
    local sources_to_sync = {}

    for _, entity in ipairs(entities) do
      if entity.remove then
        -- Get source BEFORE removing (entity edges become invalid after removal)
        local source = entity.source:get()
        if source then
          sources_to_sync[source:id()] = source
        end

        entity:remove()
        count = count + 1
      end
    end

    -- Sync all affected sources
    for _, source in pairs(sources_to_sync) do
      if source.syncBreakpoints then
        source:syncBreakpoints()
      end
    end

    if count == 0 then
      error(E.warn("DapRemove: No entities support remove"), 0)
    end
  end

  E.create_command("DapEnable", function(opts)
    local url = opts.args ~= "" and opts.args or nil
    api.enable(url)
  end, {
    nargs = "?",
    desc = "Enable entities (breakpoints)",
    complete = url_completion.create_completer(debugger, "DapEnable"),
  })

  E.create_command("DapDisable", function(opts)
    local url = opts.args ~= "" and opts.args or nil
    api.disable(url)
  end, {
    nargs = "?",
    desc = "Disable entities (breakpoints)",
    complete = url_completion.create_completer(debugger, "DapDisable"),
  })

  E.create_command("DapRemove", function(opts)
    local url = opts.args ~= "" and opts.args or nil
    api.remove(url)
  end, {
    nargs = "?",
    desc = "Remove entities (breakpoints)",
    complete = url_completion.create_completer(debugger, "DapRemove"),
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapEnable")
    pcall(vim.api.nvim_del_user_command, "DapDisable")
    pcall(vim.api.nvim_del_user_command, "DapRemove")
  end

  return api
end
