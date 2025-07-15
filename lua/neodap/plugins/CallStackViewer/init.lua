local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local StackNavigation = require("neodap.plugins.StackNavigation")

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
  local closest_frame = self.stackNavigation:getClosestFrame()
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

function CallStackViewer:get_closest_frame(location)
  return self.stackNavigation:getClosestFrame(location)
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
  local cursor_location = Location.fromCursor()
  if cursor_location then
    local closest_frame = self:get_closest_frame(cursor_location)
    if closest_frame then
      self:highlight_frame_by_id(closest_frame.ref.id)
    end
  end
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
        if self:is_window_open() then
          local stack = thread:stack()
          self:render(stack, thread)
        end
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
end

-- Window Management Methods
function CallStackViewer:create_window()
  if not self.window then
    self.window = {
      bufnr = nil,
      winid = nil,
      config = {
        relative = "editor",
        width = 60,
        height = 20,
        col = vim.o.columns - 65,
        row = 5,
        style = "minimal",
        border = "rounded",
        title = " Call Stack ",
        title_pos = "center",
      }
    }
  end
  return self.window
end

function CallStackViewer:create_buffer()
  if self.window.bufnr and vim.api.nvim_buf_is_valid(self.window.bufnr) then
    return self.window.bufnr
  end
  
  self.window.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(self.window.bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(self.window.bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(self.window.bufnr, "filetype", "neodap-callstack")
  vim.api.nvim_buf_set_option(self.window.bufnr, "modifiable", false)
  
  return self.window.bufnr
end

function CallStackViewer:open_window()
  if self:is_window_open() then
    return
  end
  
  self:create_window()
  self:create_buffer()
  
  self.window.winid = vim.api.nvim_open_win(self.window.bufnr, false, self.window.config)
  
  vim.api.nvim_win_set_option(self.window.winid, "cursorline", true)
  vim.api.nvim_win_set_option(self.window.winid, "wrap", false)
  vim.api.nvim_win_set_option(self.window.winid, "number", false)
  vim.api.nvim_win_set_option(self.window.winid, "relativenumber", false)
  vim.api.nvim_win_set_option(self.window.winid, "signcolumn", "no")
  
  self:setup_window_keymaps()
  self:setup_window_highlights()
end

function CallStackViewer:close_window()
  if self.window and self.window.winid and vim.api.nvim_win_is_valid(self.window.winid) then
    vim.api.nvim_win_close(self.window.winid, true)
  end
  if self.window then
    self.window.winid = nil
  end
end

function CallStackViewer:is_window_open()
  return self.window and self.window.winid and vim.api.nvim_win_is_valid(self.window.winid)
end

function CallStackViewer:clear_window()
  if not self.window or not self.window.bufnr or not vim.api.nvim_buf_is_valid(self.window.bufnr) then
    return
  end
  
  vim.api.nvim_buf_set_option(self.window.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(self.window.bufnr, 0, -1, false, {})
  vim.api.nvim_buf_set_option(self.window.bufnr, "modifiable", false)
end

function CallStackViewer:set_window_lines(lines)
  if not self.window or not self.window.bufnr or not vim.api.nvim_buf_is_valid(self.window.bufnr) then
    return
  end
  
  vim.api.nvim_buf_set_option(self.window.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(self.window.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(self.window.bufnr, "modifiable", false)
end

function CallStackViewer:add_window_highlight(line, col_start, col_end, hl_group)
  if not self.window or not self.window.bufnr then
    return
  end
  
  vim.api.nvim_buf_add_highlight(
    self.window.bufnr,
    -1,
    hl_group,
    line,
    col_start,
    col_end
  )
end

function CallStackViewer:clear_window_namespace(ns_id)
  if not self.window or not self.window.bufnr then
    return
  end
  
  vim.api.nvim_buf_clear_namespace(self.window.bufnr, ns_id, 0, -1)
end

function CallStackViewer:setup_window_keymaps()
  local opts = { buffer = self.window.bufnr, nowait = true }
  
  vim.keymap.set("n", "q", function() self:close_window() end, opts)
  vim.keymap.set("n", "<Esc>", function() self:close_window() end, opts)
  vim.keymap.set("n", "<CR>", function() self:on_window_select() end, opts)
  vim.keymap.set("n", "o", function() self:on_window_select() end, opts)
end

function CallStackViewer:on_window_select()
  local cursor = vim.api.nvim_win_get_cursor(self.window.winid)
  local line = cursor[1]
  
  self:select_frame(line)
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
  return self.window and self.window.winid
end

function CallStackViewer:get_window_bufnr()
  return self.window and self.window.bufnr
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
    vim.api.nvim_buf_add_highlight(
      self:get_window_bufnr(),
      self.highlight_namespace,
      "NeodapCallStackCurrent",
      line_num - 1,
      0,
      -1
    )
    
    if self:get_window_id() then
      vim.api.nvim_win_set_cursor(self:get_window_id(), {line_num, 0})
    end
  end
end

function CallStackViewer:clear_frame_highlight()
  self:clear_window_namespace(self.highlight_namespace)
  self.current_frame_line = nil
end

function CallStackViewer:select_frame(line)
  local frame = self.frame_map and self.frame_map[line]
  if not frame or not frame.ref.source then
    return
  end
  
  local source = frame.stack.thread.session:source(frame.ref.source)
  local location = Location.fromSource(source, {
    line = frame.ref.line,
    column = frame.ref.column
  })
  
  local bufnr = location:manifests(frame.stack.thread.session)
  if bufnr then
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
          vim.api.nvim_set_current_win(win)
          if frame.ref.line then
            vim.api.nvim_win_set_cursor(win, {frame.ref.line, frame.ref.column or 0})
          end
          return
        end
      end
      
      vim.cmd("buffer " .. bufnr)
      if frame.ref.line then
        vim.api.nvim_win_set_cursor(0, {frame.ref.line, frame.ref.column or 0})
      end
    end)
  end
end

function CallStackViewer:update_current_frame_highlight()
  local cursor_location = Location.fromCursor()
  if not cursor_location then
    return
  end
  
  -- Use StackNavigation to find the closest frame
  local closest_frame = self.stackNavigation:getClosestFrame(cursor_location)
  
  if closest_frame then
    self:highlight_frame_by_id(closest_frame.ref.id)
  else
    self:clear_frame_highlight()
  end
end

return CallStackViewer