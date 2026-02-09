-- Plugin: Stack navigation commands
--
-- Provides convenience aliases for navigating the call stack:
--   :DapUp   - Focus caller frame (up the stack), skipping label frames
--   :DapDown - Focus callee frame (down the stack), skipping label frames
--   :DapTop  - Focus top of stack (first non-skippable frame)

local navigate = require("neodap.plugins.utils.navigate")
local log = require("neodap.logger")

---@class neodap.plugins.StackNavConfig
---@field skip_hints? table<string, boolean> Presentation hints to skip (default: { label = true })
---@field auto_jump? boolean Jump to source after focusing frame (default: true)
---@field pick_window? fun(path: string, line: number, column: number): number|{win: number, focus: boolean}|nil
---@field create_window? fun(): number

local default_config = {
  skip_hints = { label = true },
  auto_jump = true,
  pick_window = nil,
  create_window = nil,
}

---@param debugger neodap.entities.Debugger
---@param config? neodap.plugins.StackNavConfig
---@return table api Plugin API
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local api = {}

  ---Check if a frame should be skipped during navigation
  ---@param frame table Frame entity
  ---@return boolean
  local function is_skippable(frame)
    return frame:isSkippable(config.skip_hints)
  end

  ---Focus a frame and optionally jump to its source
  ---@param frame table Frame entity
  local function focus_and_jump(frame)
    debugger.ctx:focus(frame.uri:get())
    if config.auto_jump then
      navigate.goto_frame(frame, {
        pick_window = config.pick_window,
        create_window = config.create_window,
      })
    end
  end

  ---Focus the caller frame (up the stack), skipping label frames
  ---@return boolean success
  function api.up()
    local n = 1
    while true do
      local frame = debugger:query("@frame+" .. n)
      if not frame then break end
      if not is_skippable(frame) then
        focus_and_jump(frame)
        return true
      end
      n = n + 1
    end

    log:warn("No caller frame (all remaining frames are skippable)")
    return false
  end

  ---Focus the callee frame (down the stack), skipping label frames
  ---@return boolean success
  function api.down()
    local n = 1
    while true do
      local frame = debugger:query("@frame-" .. n)
      if not frame then break end
      if not is_skippable(frame) then
        focus_and_jump(frame)
        return true
      end
      n = n + 1
    end

    log:warn("No callee frame (all remaining frames are skippable)")
    return false
  end

  ---Focus the top of stack (first non-skippable frame), with fallback to actual top
  ---@return boolean success
  function api.top()
    local frames = debugger:queryAll("@thread/stack/frames")
    if #frames == 0 then
      log:warn("No frame", { desc = "top" })
      return false
    end

    table.sort(frames, function(a, b) return a.index:get() < b.index:get() end)

    for _, frame in ipairs(frames) do
      if not is_skippable(frame) then
        focus_and_jump(frame)
        return true
      end
    end

    -- All frames skippable: fall back to actual top
    focus_and_jump(frames[1])
    return true
  end

  vim.api.nvim_create_user_command("DapUp", function() api.up() end, {
    desc = "Focus caller frame (up the stack)",
  })

  vim.api.nvim_create_user_command("DapDown", function() api.down() end, {
    desc = "Focus callee frame (down the stack)",
  })

  vim.api.nvim_create_user_command("DapTop", function() api.top() end, {
    desc = "Focus top of stack",
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapUp")
    pcall(vim.api.nvim_del_user_command, "DapDown")
    pcall(vim.api.nvim_del_user_command, "DapTop")
  end

  return api
end
