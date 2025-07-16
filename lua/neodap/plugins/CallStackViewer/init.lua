local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local StackNavigation = require("neodap.plugins.StackNavigation")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local NvimAsync = require("neodap.tools.async")

---@class neodap.plugin.CallStackViewerProps
---@field api Api
---@field logger Logger
---@field stackNavigation neodap.plugin.StackNavigation
---@field debugOverlay neodap.plugin.DebugOverlay

---@class neodap.plugin.CallStackViewer: neodap.plugin.CallStackViewerProps
---@field new Constructor<neodap.plugin.CallStackViewerProps>
local CallStackViewer = Class()

CallStackViewer.name = "CallStackViewer"
CallStackViewer.description = "Displays call stack in floating window with cursor synchronization"

function CallStackViewer.plugin(api)
  local logger = Logger.get("CallStackViewer")
  
  local instance = CallStackViewer:new({
    api = api,
    logger = logger,
    stackNavigation = api:getPluginInstance(StackNavigation),
    debugOverlay = api:getPluginInstance(DebugOverlay),
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
  
  if not self.debugOverlay:is_open() then
    self.debugOverlay:show()
  end
  
  self:render(stack, thread)
  
  -- Highlight current frame based on cursor position
  local cursor = Location.fromCursor()
  
  local frame = self.stackNavigation:getSmartClosestFrame(cursor)
  if not frame then return end

  self:highlight_frame_by_id(frame.ref.id)
end

function CallStackViewer:hide()
  self.debugOverlay:clear_right_panel()
end

function CallStackViewer:toggle()
  if self.debugOverlay:is_open() then
    self:hide()
  else
    self:show()
  end
end

function CallStackViewer:listen()
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function(stopped_event)
        -- Automatically show the overlay when debug session stops (breakpoint hit, etc.)
        if not self.debugOverlay:is_open() then
          self.debugOverlay:show()
        end
        
        local stack = thread:stack()
        self:render(stack, thread)
      end)
      
      thread:onResumed(function()
        if self.debugOverlay:is_open() then
          self.debugOverlay:clear_right_panel()
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
        self:OnNavigationChanged(event.data)
    end,
    group = vim.api.nvim_create_augroup("NeodapCallStackViewer", { clear = true }),
  })
  
  -- Listen for cursor movement to update CallStackViewer hover
  vim.api.nvim_create_autocmd("CursorMoved", {
    callback = function()
        self:OnGlobalCursorMoved()
    end,
    group = vim.api.nvim_create_augroup("NeodapCallStackViewer", { clear = false }),
  })
  
  -- Listen for overlay right panel selection events
  vim.api.nvim_create_autocmd("User", {
    pattern = "NeodapDebugOverlayRightSelect",
    callback = function(event)
        self:OnPanelSelect(event.data.line)
    end,
    group = vim.api.nvim_create_augroup("NeodapCallStackViewer", { clear = false }),
  })
end

-- Event Handling Methods
function CallStackViewer:OnNavigationChanged(event_data)
  -- Only update if overlay is open
  if not self.debugOverlay:is_open() then
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

function CallStackViewer:OnGlobalCursorMoved()
  -- Only update if overlay is open
  if not self.debugOverlay:is_open() then
    return
  end
  
  -- Skip if cursor is in any overlay window
  local current_win = vim.api.nvim_get_current_win()
  if self.debugOverlay:is_managed_window(current_win) then
    return
  end
  
  -- Get the smart closest frame for current cursor position
  local cursor = Location.fromCursor()
  if not cursor then
    return
  end
  
  local frame = self.stackNavigation:getSmartClosestFrame(cursor)
  if not frame then
    return
  end
  
  -- Update CallStackViewer cursor position to hover over the closest frame
  self:highlight_frame_by_id(frame.ref.id)
end

-- Panel interaction methods
function CallStackViewer:OnPanelSelect(line)
  self:SelectFrame(line)
end

function CallStackViewer:onPanelCursorMoved(line)
  -- Navigate to the frame under the cursor automatically
  self:NavigateToFrame(line)
end

function CallStackViewer:find_target_window()
  -- Find any window that's not managed by the debug overlay
  return self.debugOverlay:get_target_window_for_navigation()
end

function CallStackViewer:NavigateToFrame(line)
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
      vim.api.nvim_set_current_win(current_win)  -- Keep focus on overlay
    end
  end)
end

function CallStackViewer:setup_highlights()
  vim.cmd([[
    highlight default NeodapCallStackCurrent guifg=#ff9e64 gui=bold
    highlight default NeodapCallStackFrame guifg=#7aa2f7
    highlight default NeodapCallStackSource guifg=#565f89
    highlight default NeodapCallStackLineNumber guifg=#bb9af7
    highlight default link NeodapCallStackSelected CursorLine
  ]])
end

-- Rendering Methods
function CallStackViewer:render(stack, thread)
  if not stack then
    self.debugOverlay:set_right_panel_content({"No stack available"}, {}, { frame_map = {} })
    return
  end
  
  local frames = stack:frames()
  if #frames == 0 then
    self.debugOverlay:set_right_panel_content({"Empty call stack"}, {}, { frame_map = {} })
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
  
  -- Send content to debug overlay
  self.debugOverlay:set_right_panel_content(lines, highlights, { frame_map = self.frame_map })
  
  -- Set up highlights
  self:setup_highlights()
  
  -- Schedule frame highlighting to ensure buffer is populated
  vim.schedule(function()
    self:update_current_frame_highlight()
  end)
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
  if not self.frames or #self.frames == 0 then
    self.logger:debug("CallStackViewer: No frames available for highlighting")
    return
  end
  
  for i, frame in ipairs(self.frames) do
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
  if self.current_frame_line == line_num then
    return
  end
  
  -- Check if debug overlay is available and visible
  if not self.debugOverlay or not self.debugOverlay:is_open() then
    self.logger:debug("CallStackViewer: Debug overlay not available for highlighting")
    return
  end
  
  self.current_frame_line = line_num
  
  if line_num > 0 and line_num <= #(self.frames or {}) then
    -- Get the right panel buffer and apply highlighting
    local winid = self.debugOverlay:get_right_panel_winid()
    if winid and vim.api.nvim_win_is_valid(winid) then
      -- Clear previous highlights
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, self.highlight_namespace, 0, -1)
        
        -- Check if the line exists in the buffer
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if line_num <= line_count then
          -- Add current frame highlight
          vim.api.nvim_buf_add_highlight(
            bufnr,
            self.highlight_namespace,
            "NeodapCallStackCurrent",
            line_num - 1,
            0,
            -1
          )
          
          -- Set cursor position
          vim.api.nvim_win_set_cursor(winid, {line_num, 0})
        else
          self.logger:warn("CallStackViewer: Attempted to highlight line", line_num, "but buffer only has", line_count, "lines")
        end
      end
    end
  end
end

function CallStackViewer:clear_frame_highlight()
  -- Check if debug overlay is available and visible
  if not self.debugOverlay or not self.debugOverlay:is_open() then
    self.logger:debug("CallStackViewer: Debug overlay not available for clearing highlights")
    self.current_frame_line = nil
    self.last_highlighted_frame_id = nil
    return
  end
  
  -- Clear highlights in the overlay's right panel
  local winid = self.debugOverlay:get_right_panel_winid()
  if winid and vim.api.nvim_win_is_valid(winid) then
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, self.highlight_namespace, 0, -1)
    end
  end
  
  self.current_frame_line = nil
  self.last_highlighted_frame_id = nil
end

function CallStackViewer:SelectFrame(line)
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