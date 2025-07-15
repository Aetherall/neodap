local Location = require("neodap.api.Location")
local nio = require("nio")

local M = {}
M.__index = M

local NAMESPACE = vim.api.nvim_create_namespace("neodap_callstack_viewer")

function M.new(window)
  local self = setmetatable({
    window = window,
    frames = {},
    frame_map = {},
    current_frame_line = nil,
  }, M)
  
  window:set_on_select(function(line)
    self:select_frame(line)
  end)
  
  return self
end

function M:render(stack, thread)
  if not stack then
    self.window:set_lines({"No stack available"})
    return
  end
  
  local frames = stack:frames()
  if #frames == 0 then
    self.window:set_lines({"Empty call stack"})
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
  
  self.window:set_lines(lines)
  
  for i, hl_parts in ipairs(highlights) do
    for _, hl in ipairs(hl_parts) do
      self.window:add_highlight(i - 1, hl[1], hl[2], hl[3])
    end
  end
  
  nio.run(function()
    nio.sleep(50)
    self:update_current_frame_highlight()
  end)
end

function M:highlight_frame_at_line(bufnr, line)
  local current_frame = self:find_frame_for_location(bufnr, line)
  
  if current_frame then
    for i, frame in ipairs(self.frames) do
      if frame.ref.id == current_frame.ref.id then
        self:highlight_frame(i)
        break
      end
    end
  else
    self:clear_frame_highlight()
  end
end

function M:find_frame_for_location(bufnr, line)
  for _, frame in ipairs(self.frames) do
    if frame.ref.source and frame.ref.line == line then
      local source = frame.stack.thread.session:source(frame.ref.source)
      local location = Location.fromSource(source, {
        line = frame.ref.line,
        column = frame.ref.column
      })
      
      local frame_bufnr = location:manifests(frame.stack.thread.session)
      if frame_bufnr == bufnr then
        return frame
      end
    end
  end
  
  return nil
end

function M:highlight_frame(line_num)
  self.window:clear_namespace(NAMESPACE)
  
  if self.current_frame_line == line_num then
    return
  end
  
  self.current_frame_line = line_num
  
  if line_num > 0 and line_num <= #self.frames then
    vim.api.nvim_buf_add_highlight(
      self.window:get_bufnr(),
      NAMESPACE,
      "NeodapCallStackCurrent",
      line_num - 1,
      0,
      -1
    )
    
    if self.window:get_winid() then
      vim.api.nvim_win_set_cursor(self.window:get_winid(), {line_num, 0})
    end
  end
end

function M:clear_frame_highlight()
  self.window:clear_namespace(NAMESPACE)
  self.current_frame_line = nil
end

function M:select_frame(line)
  local frame = self.frame_map[line]
  if not frame or not frame.ref.source then
    return
  end
  
  nio.run(function()
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
  end)
end

function M:update_current_frame_highlight()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  self:highlight_frame_at_line(bufnr, line)
end

return M