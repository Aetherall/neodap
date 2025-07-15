local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local StackNavigation = require("neodap.plugins.StackNavigation")
local UI = require("neodap.ui")

---@class neodap.plugin.CallStackViewerProps
---@field api Api
---@field logger Logger
---@field stackNavigation neodap.plugin.StackNavigation

---@class neodap.plugin.CallStackViewer: neodap.plugin.CallStackViewerProps
---@field new Constructor<neodap.plugin.CallStackViewerProps>
local CallStackViewer = Class()

CallStackViewer.name = "CallStackViewer"
CallStackViewer.description = "Displays call stack in floating window with cursor synchronization"

function CallStackViewer.plugin(api)
  local logger = Logger.get()
  
  local instance = CallStackViewer:new({
    api = api,
    logger = logger,
    stackNavigation = api:getPluginInstance(StackNavigation),
    window = nil,
    frames = {},
    frame_map = {},
    current_frame_line = nil,
    highlight_namespace = vim.api.nvim_create_namespace("neodap_callstack_viewer"),
    last_highlighted_frame_id = nil,
  })
  
  instance:setup_commands()
  instance:listen()
  
  return instance
end

function CallStackViewer:setup_commands()
  vim.api.nvim_create_user_command("NeodapCallStack", function()
    self:show()
  end, { desc = "Show call stack in floating window" })
  
  vim.api.nvim_create_user_command("NeodapCallStackHide", function()
    self:hide()
  end, { desc = "Hide call stack window" })
  
  vim.api.nvim_create_user_command("NeodapCallStackToggle", function()
    self:toggle()
  end, { desc = "Toggle call stack window" })
end

function CallStackViewer:get_current_stack()
  -- Use StackNavigation to find the closest frame, then get its stack
  local closest_frame = self.stackNavigation:getSmartClosestFrame()
  if closest_frame then
    return closest_frame.stack, closest_frame.stack.thread
  end
  
  -- Fallback: find any stopped thread
  for session in self.api:eachSession() do
    for thread in session:eachThread({ filter = 'stopped' }) do
      return thread:stack(), thread
    end
  end
  return nil, nil
end


function CallStackViewer:show()
  local stack, thread = self:get_current_stack()
  
  if not stack then
    self.logger:info("CallStackViewer: No active debug session with call stack")
    return
  end
  
  self:open_window()
  self:render(stack, thread)
  
  -- Highlight current frame based on cursor position
  local cursor = Location.fromCursor()
  
  local frame = self.stackNavigation:getSmartClosestFrame(cursor)
  if not frame then return end

  self:highlight_frame_by_id(frame.ref.id)
end

function CallStackViewer:hide()
  self:close_window()
end

function CallStackViewer:toggle()
  if self:is_window_open() then
    self:hide()
  else
    self:show()
  end
end

function CallStackViewer:listen()
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function(stopped_event)
        -- Automatically show the window when debug session stops (breakpoint hit, etc.)
        if not self:is_window_open() then
          self:open_window()
        end
        
        local stack = thread:stack()
        self:render(stack, thread)
      end)
      
      thread:onResumed(function()
        if self:is_window_open() then
          self:clear_window()
        end
      end)
    end)
    
    session:onTerminated(function()
      self:hide()
    end)
  end, { name = self.name .. ".onSession" })
  
  -- Listen for stack navigation events
  vim.api.nvim_create_autocmd("User", {
    pattern = "NeodapStackNavigationChanged",
    callback = function(event)
      self:onNavigationChanged(event.data)
    end,
    group = vim.api.nvim_create_augroup("NeodapCallStackViewer", { clear = true }),
  })
end

-- Event Handling Methods
function CallStackViewer:onNavigationChanged(event_data)
  -- Only update if window is open
  if not self:is_window_open() then
    return
  end
  
  -- Check if this navigation event affects the currently displayed thread
  local current_stack, current_thread = self:get_current_stack()
  if not current_thread then
    return
  end
  
  -- Only update if the navigation event is for the currently displayed thread
  if event_data.thread_id == current_thread.id and event_data.session_id == current_thread.session.id then
    self.logger:debug("CallStackViewer: Navigation event for current thread, updating highlight")
    self:highlight_frame_by_id(event_data.frame_id)
  end
end

-- Window Management Methods
function CallStackViewer:create_window()
  if not self.window then
    self.window = UI.Window:new({
      title = " Call Stack ",
      size = { width = 60, height = 20 },
      position = { col = vim.o.columns - 65, row = 5 },
      enter = false, -- Don't take focus when showing
      win_options = {
        cursorline = true,
        wrap = false,
        number = false,
        relativenumber = false,
        signcolumn = "no",
      },
      keymaps = {
        ["q"] = function() self:hide() end,
        ["<Esc>"] = function() self:hide() end,
        ["<CR>"] = function() self:on_window_select() end,
        ["o"] = function() self:on_window_select() end,
      }
    })
    
    -- Set buffer options
    local bufnr = self.window:get_bufnr()
    if bufnr then
      vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
      vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "neodap-callstack")
      vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
      
      -- Set up cursor movement detection for auto-navigation
      vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = bufnr,
        callback = function()
          self:on_cursor_moved()
        end,
        desc = "CallStackViewer: Navigate to frame on cursor movement"
      })
    end
    
    self:setup_window_highlights()
  end
  return self.window
end

function CallStackViewer:open_window()
  if self:is_window_open() then
    return
  end
  
  self:create_window()
  self.window:show()
end

function CallStackViewer:close_window()
  if self.window then
    self.window:hide()
  end
end

function CallStackViewer:is_window_open()
  return self.window and self.window:is_open()
end

function CallStackViewer:clear_window()
  if self.window then
    self.window:clear()
  end
end

function CallStackViewer:set_window_lines(lines)
  if self.window then
    self.window:set_lines(lines)
  end
end

function CallStackViewer:add_window_highlight(line, col_start, col_end, hl_group, namespace)
  if self.window then
    self.window:add_highlight(line, col_start, col_end, hl_group, namespace)
  end
end

function CallStackViewer:clear_window_namespace(ns_id)
  if self.window then
    self.window:clear_highlights(ns_id)
  end
end

function CallStackViewer:on_window_select()
  local line, _ = self.window:get_cursor()
  self:select_frame(line)
end

function CallStackViewer:on_cursor_moved()
  -- Navigate to the frame under the cursor automatically
  local line, _ = self.window:get_cursor()
  self:navigate_to_frame(line)
end

function CallStackViewer:find_target_window()
  -- Find any window that's not the CallStackViewer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= self.window:get_winid() then
      return win
    end
  end
  return nil
end

function CallStackViewer:navigate_to_frame(line)
  local frame = self.frame_map and self.frame_map[line]
  if not frame then
    return
  end
  
  pcall(function()
    local target_win = self:find_target_window()
    if target_win then
      local current_win = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(target_win)
      frame:jump()  -- Does all the hard work: location, manifests, cursor
      vim.api.nvim_set_current_win(current_win)  -- Keep focus on CallStackViewer
    end
  end)
end

function CallStackViewer:setup_window_highlights()
  vim.cmd([[
    highlight default NeodapCallStackCurrent guifg=#ff9e64 gui=bold
    highlight default NeodapCallStackFrame guifg=#7aa2f7
    highlight default NeodapCallStackSource guifg=#565f89
    highlight default NeodapCallStackLineNumber guifg=#bb9af7
    highlight default link NeodapCallStackSelected CursorLine
  ]])
end

function CallStackViewer:get_window_id()
  return self.window and self.window:get_winid()
end

function CallStackViewer:get_window_bufnr()
  return self.window and self.window:get_bufnr()
end

-- Rendering Methods
function CallStackViewer:render(stack, thread)
  if not stack then
    self:set_window_lines({"No stack available"})
    return
  end
  
  local frames = stack:frames()
  if #frames == 0 then
    self:set_window_lines({"Empty call stack"})
    return
  end
  
  self.frames = frames
  self.frame_map = {}
  
  local lines = {}
  local highlights = {}
  
  for i, frame in ipairs(frames) do
    local line_parts = {}
    local hl_parts = {}
    
    table.insert(line_parts, string.format("#%-2d ", i - 1))
    table.insert(hl_parts, { 0, #line_parts[1], "NeodapCallStackFrame" })
    
    local name = frame.ref.name or "<unknown>"
    table.insert(line_parts, name)
    local name_start = #table.concat(line_parts, "") - #name
    table.insert(hl_parts, { name_start, name_start + #name, "NeodapCallStackFrame" })
    
    if frame.ref.source then
      local source_info = ""
      if frame.ref.source.path then
        source_info = string.format(" at %s", vim.fn.fnamemodify(frame.ref.source.path, ":t"))
      elseif frame.ref.source.name then
        source_info = string.format(" at %s", frame.ref.source.name)
      end
      
      if frame.ref.line then
        source_info = source_info .. ":" .. frame.ref.line
        if frame.ref.column then
          source_info = source_info .. ":" .. frame.ref.column
        end
      end
      
      if source_info ~= "" then
        table.insert(line_parts, source_info)
        local source_start = #table.concat(line_parts, "") - #source_info
        table.insert(hl_parts, { source_start, source_start + #source_info, "NeodapCallStackSource" })
      end
    end
    
    local line = table.concat(line_parts, "")
    table.insert(lines, line)
    table.insert(highlights, hl_parts)
    
    self.frame_map[i] = frame
  end
  
  self:set_window_lines(lines)
  
  for i, hl_parts in ipairs(highlights) do
    for _, hl in ipairs(hl_parts) do
      self:add_window_highlight(i - 1, hl[1], hl[2], hl[3])
    end
  end
  
  self:update_current_frame_highlight()
end

function CallStackViewer:highlight_frame_at_line(bufnr, line)
  local current_frame = self:find_frame_for_location(bufnr, line)
  
  if current_frame then
    self:highlight_frame_by_id(current_frame.ref.id)
  else
    self:clear_frame_highlight()
  end
end

function CallStackViewer:highlight_frame_by_id(frame_id)
  for i, frame in ipairs(self.frames or {}) do
    if frame.ref.id == frame_id then
      self:highlight_frame(i)
      break
    end
  end
end

function CallStackViewer:find_frame_for_location(bufnr, line)
  local target_location = Location.fromBuffer(bufnr, line)
  if not target_location then
    return nil
  end
  
  -- Use StackNavigation to find the closest frame
  local closest_frame = self.stackNavigation:getClosestFrame(target_location)
  
  -- Verify the frame is in our current stack
  if closest_frame then
    for _, frame in ipairs(self.frames or {}) do
      if frame.ref.id == closest_frame.ref.id then
        return closest_frame
      end
    end
  end
  
  return nil
end

function CallStackViewer:highlight_frame(line_num)
  self:clear_window_namespace(self.highlight_namespace)
  
  if self.current_frame_line == line_num then
    return
  end
  
  self.current_frame_line = line_num
  
  if line_num > 0 and line_num <= #(self.frames or {}) then
    self:add_window_highlight(
      line_num - 1,
      0,
      -1,
      "NeodapCallStackCurrent",
      self.highlight_namespace
    )
    
    if self:is_window_open() then
      self.window:set_cursor(line_num, 0)
    end
  end
end

function CallStackViewer:clear_frame_highlight()
  self:clear_window_namespace(self.highlight_namespace)
  self.current_frame_line = nil
  self.last_highlighted_frame_id = nil
end

function CallStackViewer:select_frame(line)
  local frame = self.frame_map and self.frame_map[line]
  if not frame then
    return
  end
  
  pcall(function()
    local target_win = self:find_target_window()
    if target_win then
      vim.api.nvim_set_current_win(target_win)
      frame:jump()  -- Does all the hard work: location, manifests, cursor
      -- Keep focus on target window for actual selection
    end
  end)
end

function CallStackViewer:update_current_frame_highlight()
  local cursor_location = Location.fromCursor()
  if not cursor_location then
    return
  end
  
  -- Use StackNavigation to find the smart closest frame (considers per-thread state)
  local closest_frame = self.stackNavigation:getSmartClosestFrame(cursor_location)
  
  -- Track last highlighted frame to prevent unnecessary updates
  if closest_frame and closest_frame.ref.id ~= self.last_highlighted_frame_id then
    self.last_highlighted_frame_id = closest_frame.ref.id
    self:highlight_frame_by_id(closest_frame.ref.id)
  elseif not closest_frame and self.last_highlighted_frame_id then
    self.last_highlighted_frame_id = nil
    self:clear_frame_highlight()
  end
end

return CallStackViewer