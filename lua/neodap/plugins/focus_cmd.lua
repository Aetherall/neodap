-- Plugin: DapFocus command for focusing debug entities
--
-- Usage:
--   :DapFocus /sessions                  - pick session to focus (if multiple)
--   :DapFocus @session/threads           - pick thread to focus
--   :DapFocus @session/threads[0]        - focus first thread (no picker)
--   :DapFocus sessions[0]                - focus first session

local url_completion = require("neodap.plugins.utils.url_completion")
local uri_picker = require("neodap.plugins.uri_picker")
local log = require("neodap.logger")

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
      log:error("DapFocus: Missing URL")
      if callback then callback(false) end
      return false
    end

    picker:resolve(url, function(entity)
      if not entity then
        log:warn("DapFocus: No entity found", { url = url })
        if callback then callback(false) end
        return
      end

      local entity_type = entity:type()

      if entity_type == "Frame" or entity_type == "Thread" or entity_type == "Session" then
        debugger.ctx:focus(entity.uri:get())
        log:debug("DapFocus: focused " .. entity.uri:get())
        if callback then callback(true) end
      else
        log:warn("DapFocus: Cannot focus", { entity_type = entity_type })
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

  ---Pick a Config and focus its first target (or first stopped target)
  ---@param callback? fun(config: any?) Optional callback
  function api.pick_config(callback)
    -- Collect active configs
    local configs = {}
    for cfg in debugger.activeConfigs:iter() do
      table.insert(configs, cfg)
    end

    if #configs == 0 then
      log:info("No active Configs")
      if callback then callback(nil) end
      return
    end

    if #configs == 1 then
      -- Single config - focus directly
      local cfg = configs[1]
      local target = cfg.firstStoppedTarget:get() or cfg.firstTarget:get()
      if target then
        debugger.ctx:focus(target.uri:get())
        log:debug("DapConfigs: focused target in " .. cfg:displayName())
      end
      if callback then callback(cfg) end
      return
    end

    -- Multiple configs - show picker
    vim.ui.select(configs, {
      prompt = "Select Config:",
      format_item = function(cfg)
        local state_icon = cfg.state:get() == "active" and "▶" or "⏹"
        local stopped = cfg.stoppedTargetCount:get()
        local total = cfg.targetCount:get()
        local targets_info = stopped > 0
          and string.format("⏸ %d/%d", stopped, total)
          or string.format("%d targets", total)
        return string.format("%s %s (%s)", state_icon, cfg:displayName(), targets_info)
      end,
    }, function(selected)
      if selected then
        local target = selected.firstStoppedTarget:get() or selected.firstTarget:get()
        if target then
          debugger.ctx:focus(target.uri:get())
          log:debug("DapConfigs: focused target in " .. selected:displayName())
        end
      end
      if callback then callback(selected) end
    end)
  end

  ---Pick a target, grouped by Config
  ---@param callback? fun(target: any?) Optional callback
  function api.pick_target(callback)
    -- Collect all active targets grouped by Config
    local items = {}
    for cfg in debugger.activeConfigs:iter() do
      for target in cfg.targets:iter() do
        if target.state:get() ~= "terminated" then
          table.insert(items, { config = cfg, target = target })
        end
      end
    end

    if #items == 0 then
      log:info("No active targets")
      if callback then callback(nil) end
      return
    end

    if #items == 1 then
      -- Single target - focus directly
      debugger.ctx:focus(items[1].target.uri:get())
      if callback then callback(items[1].target) end
      return
    end

    -- Multiple targets - show picker with Config grouping
    vim.ui.select(items, {
      prompt = "Select Target:",
      format_item = function(item)
        local state = item.target:displayState()
        local icon = state == "stopped" and "⏸" or (state == "running" and "▶" or "⏹")
        local name = item.target.name:get() or "Session"
        local cfg_name = item.config:displayName()
        return string.format("%s %s [%s]", icon, name, cfg_name)
      end,
    }, function(selected)
      if selected then
        debugger.ctx:focus(selected.target.uri:get())
        log:debug("DapTargets: focused " .. selected.target.uri:get())
      end
      if callback then callback(selected and selected.target or nil) end
    end)
  end

  vim.api.nvim_create_user_command("DapConfigs", function()
    api.pick_config()
  end, {
    desc = "Pick a Config to focus",
  })

  vim.api.nvim_create_user_command("DapTargets", function()
    api.pick_target()
  end, {
    desc = "Pick a target to focus (grouped by Config)",
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapFocus")
    pcall(vim.api.nvim_del_user_command, "DapConfigs")
    pcall(vim.api.nvim_del_user_command, "DapTargets")
  end

  return api
end
