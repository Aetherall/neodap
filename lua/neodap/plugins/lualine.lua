-- Plugin: Lualine components for debug context
--
-- Provides multiple components for lualine that show debugging state.
--
-- Usage:
--   local neodap = require("neodap")
--   neodap.setup()
--   local lualine = neodap.use(require("neodap.plugins.lualine"))
--
--   require("lualine").setup({
--     sections = {
--       lualine_x = {
--         lualine.status(),   -- Icon showing stopped/running/none
--         lualine.session(),  -- Session/adapter name
--         lualine.thread(),   -- Thread name and state
--         lualine.frame(),    -- Function name:line
--       }
--     }
--   })
--
-- Each component factory accepts options:
--   lualine.status({ icons = { stopped = "", running = "" } })
--   lualine.session({ show_chain = true })
--   lualine.thread({ show_count = true })
--   lualine.frame({ max_name_length = 20 })
--   lualine.context({ separator = " | " })
--
-- Legacy API (still supported):
--   local component = neodap.use(require("neodap.plugins.lualine"), {
--     session = true, thread = true, frame = true, separator = " > "
--   })

---@class neodap.plugins.lualine.StatusConfig
---@field icons? { stopped?: string, running?: string, none?: string } Icons for each state
---@field labels? { stopped?: string, running?: string, none?: string } Text labels for each state

---@class neodap.plugins.lualine.SessionConfig
---@field show_state? boolean Show session state (default: false)
---@field show_chain? boolean Show full session chain for nested sessions (default: false)
---@field separator? string Separator for chain names (default: " > ")

---@class neodap.plugins.lualine.ThreadConfig
---@field show_name? boolean Show thread name (default: true)
---@field show_state? boolean Show thread state (default: true)
---@field show_count? boolean Show thread count when multiple (default: false)

---@class neodap.plugins.lualine.FrameConfig
---@field show_name? boolean Show function name (default: true)
---@field show_line? boolean Show line number (default: true)
---@field show_index? boolean Show frame index in stack (default: false)
---@field max_name_length? number Truncate function name (default: nil, no truncation)

---@class neodap.plugins.lualine.ContextConfig
---@field session? boolean Show session name (default: true)
---@field thread? boolean Show thread state (default: true)
---@field frame? boolean Show frame function:line (default: true)
---@field separator? string Separator between parts (default: " > ")
---@field empty? string What to return when no session (default: "")
---@field format? fun(ctx: { session?: table, thread?: table, frame?: table }): string Custom format function

---@class neodap.plugins.lualine.Config
---@field status? neodap.plugins.lualine.StatusConfig
---@field session? neodap.plugins.lualine.SessionConfig
---@field thread? neodap.plugins.lualine.ThreadConfig
---@field frame? neodap.plugins.lualine.FrameConfig
---@field context? neodap.plugins.lualine.ContextConfig

local default_config = {
  status = {
    icons = {
      stopped = "",
      running = "",
      none = "",
    },
    labels = {
      stopped = nil,
      running = nil,
      none = nil,
    },
  },
  session = {
    show_state = false,
    show_chain = false,
    separator = " > ",
  },
  thread = {
    show_name = true,
    show_state = true,
    show_count = false,
  },
  frame = {
    show_name = true,
    show_line = true,
    show_index = false,
    max_name_length = nil,
  },
  context = {
    session = true,
    thread = true,
    frame = true,
    separator = " > ",
    empty = "",
    format = nil,
  },
}

---Create a component that triggers redraw on focus changes
---@param debugger neodap.entities.Debugger
---@param build_fn fun(): string Function that builds the component string
---@return fun(): string component Lualine component function
local function create_component(debugger, build_fn)
  local value = build_fn()

  debugger.focusedUrl:use(function()
    local new_value = build_fn()
    if new_value ~= value then
      value = new_value
      vim.schedule(function()
        vim.cmd("redraw")
      end)
    end
  end)

  return function()
    return value
  end
end

---Check if config uses legacy flat format
---Legacy format has: session/thread/frame as booleans, or separator/empty/format at top level
---@param cfg table
---@return boolean
local function is_legacy_config(cfg)
  if not cfg then return false end
  return cfg.separator ~= nil
    or cfg.empty ~= nil
    or cfg.format ~= nil
    or type(cfg.session) == "boolean"
    or type(cfg.thread) == "boolean"
    or type(cfg.frame) == "boolean"
end

---Convert legacy config to new format
---@param cfg table
---@return table
local function convert_legacy_config(cfg)
  return {
    status = default_config.status,
    session = default_config.session,
    thread = default_config.thread,
    frame = default_config.frame,
    context = {
      session = cfg.session ~= false,
      thread = cfg.thread ~= false,
      frame = cfg.frame ~= false,
      separator = cfg.separator or default_config.context.separator,
      empty = cfg.empty or default_config.context.empty,
      format = cfg.format,
    },
  }
end

---@param debugger neodap.entities.Debugger
---@param config neodap.plugins.lualine.Config
---@return neodap.plugins.lualine.Components
return function(debugger, config)
  local user_config = config or {}
  local is_legacy = is_legacy_config(user_config)

  if is_legacy then
    config = convert_legacy_config(user_config)
  else
    config = vim.tbl_deep_extend("force", default_config, user_config)
  end

  local M = {}

  ---Status indicator showing debug state icon (uses session's icon component)
  ---@param opts? neodap.plugins.lualine.StatusConfig
  ---@return fun(): string
  function M.status(opts)
    opts = vim.tbl_deep_extend("force", config.status, opts or {})

    return create_component(debugger, function()
      local session = debugger.ctx.session:get()
      if not session then
        return opts.icons.none or ""
      end

      -- Use the session's icon component for consistency
      return debugger:render_text(session, { "icon" })
    end)
  end

  ---Session name component
  ---Shows session chain: "root > child" for nested sessions, or just "session" for single
  ---@param opts? neodap.plugins.lualine.SessionConfig
  ---@return fun(): string
  function M.session(opts)
    opts = vim.tbl_deep_extend("force", config.session, opts or {})

    return create_component(debugger, function()
      local session = debugger.ctx.session:get()
      if not session then
        return ""
      end

      -- Use the same layout as tree_buffer: root_session_name + chain_arrow + session_name
      local layout = { "root_session_name", "chain_arrow", "session_name" }
      if opts.show_state then
        layout[#layout + 1] = { "state", prefix = " [", suffix = "]" }
      end

      return debugger:render_text(session, layout)
    end)
  end

  ---Counter component showing current/total stopped sessions [1/2]
  ---Only shows when there are 2+ stopped sessions
  ---@return fun(): string
  function M.counter()
    return create_component(debugger, function()
      local session = debugger.ctx.session:get()
      if not session then
        return ""
      end

      return debugger:render_text(session, { "stopped_counter" })
    end)
  end

  ---Config component showing Config index and target position
  ---Format: [#1] for single target, [#1: 1/3] for multiple targets
  ---@param opts? { show_position?: boolean, always_show_position?: boolean }
  ---@return fun(): string
  function M.config(opts)
    opts = opts or {}
    local show_position = opts.show_position ~= false  -- default true
    local always_show_position = opts.always_show_position or false

    return create_component(debugger, function()
      local session = debugger.ctx.session:get()
      if not session then
        return ""
      end

      local cfg = session.config:get()
      if not cfg then
        return ""
      end

      local index = cfg.index:get() or 1
      local target_count = cfg.targetCount:get() or 0

      -- Find current target's position within Config
      local current_pos = nil
      if show_position and session.leaf:get() then
        current_pos = cfg:targetIndex(session)
      end

      -- Format: [#1] or [#1: 1/3]
      if show_position and current_pos and (always_show_position or target_count > 1) then
        return string.format("[#%d: %d/%d]", index, current_pos, target_count)
      else
        return string.format("[#%d]", index)
      end
    end)
  end

  ---Thread state component
  ---@param opts? neodap.plugins.lualine.ThreadConfig
  ---@return fun(): string
  function M.thread(opts)
    opts = vim.tbl_deep_extend("force", config.thread, opts or {})

    return create_component(debugger, function()
      local session = debugger.ctx.session:get()
      if not session then
        return ""
      end

      local thread = debugger.ctx.thread:get()
      if not thread then
        if opts.show_count then
          local text = debugger:render_text(session, { { "thread_count", suffix = " threads" } })
          if text ~= "" then return text end
        end
        return ""
      end

      local layout = {}
      if opts.show_name then layout[#layout + 1] = "title" end
      if opts.show_state then
        layout[#layout + 1] = { "state", prefix = #layout > 0 and " " or nil }
      end

      local text = debugger:render_text(thread, layout)

      if opts.show_count then
        local count_text = debugger:render_text(session, { { "thread_count", prefix = "(", suffix = ")" } })
        if count_text ~= "" then
          text = text .. (text ~= "" and " " or "") .. count_text
        end
      end

      return text
    end)
  end

  ---Frame info component (function name and line)
  ---@param opts? neodap.plugins.lualine.FrameConfig
  ---@return fun(): string
  function M.frame(opts)
    opts = vim.tbl_deep_extend("force", config.frame, opts or {})

    return create_component(debugger, function()
      local frame = debugger.ctx.frame:get()
      if not frame then
        return ""
      end

      local layout = {}
      if opts.show_index then
        layout[#layout + 1] = { "index", prefix = #layout > 0 and " " or nil }
      end
      if opts.show_name then
        local entry = { "title", prefix = #layout > 0 and " " or nil }
        if opts.max_name_length then entry.truncate = opts.max_name_length end
        layout[#layout + 1] = entry
      end
      if opts.show_line then
        layout[#layout + 1] = { "line", prefix = ":" }
      end

      return debugger:render_text(frame, layout)
    end)
  end

  ---Combined context component (backward compatible with original API)
  ---@param opts? neodap.plugins.lualine.ContextConfig
  ---@return fun(): string
  function M.context(opts)
    opts = vim.tbl_deep_extend("force", config.context, opts or {})

    return create_component(debugger, function()
      local session = debugger.ctx.session:get()
      local thread = debugger.ctx.thread:get()
      local frame = debugger.ctx.frame:get()

      -- Custom format function takes precedence
      if opts.format then
        return opts.format({ session = session, thread = thread, frame = frame }) or opts.empty
      end

      -- No session = empty status
      if not session then
        return opts.empty
      end

      local parts = {}

      if opts.session then
        local text = debugger:render_text(session, { "session_name" })
        if text ~= "" then table.insert(parts, text) end
      end

      if opts.thread and thread then
        local text = debugger:render_text(thread, { "state" })
        if text ~= "" then table.insert(parts, text) end
      end

      if opts.frame and frame then
        local text = debugger:render_text(frame, { "title", { "line", prefix = ":" } })
        if text ~= "" then table.insert(parts, text) end
      end

      if #parts > 0 then
        return table.concat(parts, opts.separator)
      else
        return opts.empty
      end
    end)
  end

  if is_legacy then
    -- Return legacy-compatible single function
    return M.context()
  end

  -- Create a cached default context for the callable interface
  local default_context = M.context()

  -- Return the factory functions table
  -- The table is also callable for backward compatibility: lualine() returns context
  return setmetatable({}, {
    __index = M,
    __call = function()
      return default_context()
    end,
  })
end
