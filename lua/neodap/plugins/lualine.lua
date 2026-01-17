-- Plugin: Lualine status component for debug context
--
-- Returns a function suitable for lualine configuration:
--   local component = neodap.use(require("neodap.plugins.lualine"), { ... })
--   require("lualine").setup({ sections = { lualine_x = { component } } })

---@class LualineConfig
---@field session? boolean Show session name (default: true)
---@field thread? boolean Show thread state (default: true)
---@field frame? boolean Show frame function:line (default: true)
---@field separator? string Separator between parts (default: " > ")
---@field empty? string What to return when no session (default: "")
---@field format? fun(ctx: LualineContext): string Custom format function

---@class LualineContext
---@field session? table Session entity
---@field thread? table Thread entity
---@field frame? table Frame entity

local default_config = {
  session = true,
  thread = true,
  frame = true,
  separator = " > ",
  empty = "",
  format = nil,
}

---@param debugger neodap.entities.Debugger
---@param config? LualineConfig
---@return fun(): string component Lualine component function
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  -- Cached status string
  local status = config.empty

  -- Build status string from current context
  local function update_status()
    local session = debugger.ctx.session:get()
    local thread = debugger.ctx.thread:get()
    local frame = debugger.ctx.frame:get()

    -- Custom format function takes precedence
    if config.format then
      status = config.format({ session = session, thread = thread, frame = frame }) or config.empty
      return
    end

    -- No session = empty status
    if not session then
      status = config.empty
      return
    end

    local parts = {}

    -- Session: adapter name
    if config.session then
      local name = session.name:get()
      if name and name ~= "" then
        table.insert(parts, name)
      end
    end

    -- Thread: state
    if config.thread and thread then
      local state = thread.state:get()
      if state then
        table.insert(parts, state)
      end
    end

    -- Frame: function:line
    if config.frame and frame then
      local name = frame.name:get() or ""
      local line = frame.line:get()
      if name ~= "" and line then
        table.insert(parts, name .. ":" .. line)
      elseif name ~= "" then
        table.insert(parts, name)
      end
    end

    if #parts > 0 then
      status = table.concat(parts, config.separator)
    else
      status = config.empty
    end
  end

  -- Initial update
  update_status()

  -- Subscribe to focus changes
  local first_call = true
  debugger.focusedUrl:use(function()
    if first_call then
      first_call = false
      return
    end
    update_status()
    vim.schedule(function()
      vim.cmd("redraw")
    end)
  end)

  -- Return lualine component function
  return function()
    return status
  end
end
