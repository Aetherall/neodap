local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Session.Scope')
local Logger = require('neodap.tools.logger')
local Location = require("neodap.api.Location")


---@class api.FrameProps
---@field stack api.Stack
---@field ref dap.StackFrame

---@class api.Frame: api.FrameProps
---@field _scopes { [integer]: api.Scope? } | nil
---@field _source api.BaseSource | nil
---@field new Constructor<api.FrameProps>
local Frame = Class()

---@param stack api.Stack
---@param frame dap.StackFrame
function Frame.instanciate(stack, frame)
  local instance = Frame:new({
    stack = stack,
    --- DAP
    _scopes = nil,
    _source = frame.source and stack.thread.session:getSourceFor(frame.source),
    --- State
    ref = frame,
  })
  return instance
end

---@param stack api.Stack
---@param stackFrames dap.StackFrame[]
---@return api.Frame[], table<integer, integer>
function Frame.indexAll(stack, stackFrames)
  local frames = {}
  local index = {}

  for i, frame in ipairs(stackFrames) do
    frames[i] = Frame.instanciate(stack, frame)
    index[frame.id] = i
  end

  return frames, index
end

---@return { [integer]: api.Scope? } | nil
function Frame:scopes()
  if self._scopes then
    return self._scopes
  end

  local response = self.stack.thread.session.ref.calls:scopes({
    frameId = self.ref.id,
    threadId = self.stack.thread.id,
  }):wait()


  self._scopes = vim.tbl_map(function(scope)
    return Scope.instanciate(self, scope)
  end, response.scopes)

  return self._scopes
end

function Frame:variables(variablesReference)
  local response = self.stack.thread.session.ref.calls:variables({
    variablesReference = variablesReference
  }):wait()

  return response.variables
end

function Frame:up()
  return self.stack:upOf(self.ref.id)
end

function Frame:down()
  return self.stack:downOf(self.ref.id)
end

function Frame:jump()
  local source = self.ref.source
  if not source then
    return
  end
  
  -- Get the source object from session
  local source_obj = self.stack.thread.session:getSourceFor(source)
  if not source_obj then
    return
  end
  
  local bufnr = source_obj:bufnr()
  
  if not bufnr then
    return
  end
  
  -- Ensure the buffer is valid before switching to it
  if not vim.api.nvim_buf_is_valid(bufnr) then
    local Logger = require('neodap.tools.logger')
    local log = Logger.get()
    log:error("Frame:jump - Invalid buffer", bufnr, "for source", source.name or "unnamed")
    return
  end
  
  -- Switch to the buffer and set cursor position
  vim.api.nvim_set_current_buf(bufnr)
  
  -- Ensure line and column are valid for the buffer
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local safe_line = math.min(math.max(1, self.ref.line), line_count)
  local safe_column = math.max(0, (self.ref.column or 1) - 1) -- Convert to 0-based
  
  vim.api.nvim_win_set_cursor(0, { safe_line, safe_column })
  
  -- Log successful jump for debugging
  local Logger = require('neodap.tools.logger')
  local log = Logger.get()
  log:debug("Frame:jump - Successfully jumped to", source_obj.type == 'virtual' and "virtual" or "file", "source", 
            source.name or "unnamed", "at line", safe_line, "column", safe_column + 1)
end

---@param namespace integer
---@param hl_group string
function Frame:highlight(namespace, hl_group)
  local source = self.ref.source
  if not source then
    return
  end
  
  -- Get the source object from session
  local source_obj = self.stack.thread.session:getSourceFor(source)
  if not source_obj then
    return
  end
  
  local bufnr = nil
  
  if source_obj.type == 'file' then
    -- Handle file sources
    local Location = require('neodap.api.Location')
    local location = Location.fromSource(source_obj, {
      line = self.ref.line,
      column = self.ref.column
    })
    bufnr = location:bufnr()
    
  elseif source_obj.type == 'virtual' then
    -- Handle virtual sources - ensure buffer is created with DAP content
    bufnr = source_obj:bufnr() -- This triggers DAP content loading
    
    if not bufnr then
      -- If buffer creation failed, return without highlighting
      return
    end
    
  else
    -- Generic sources not navigable
    return
  end
  
  if not bufnr then
    return
  end
  
  local log = Logger.get()
  log:debug("Frame highlight - Buffer number:", bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local safe_extmark_line = math.min(self.ref.line - 1, line_count - 1)
  safe_extmark_line = math.max(0, safe_extmark_line)

  -- Use a safe end_col value
  local line_content = vim.api.nvim_buf_get_lines(bufnr, safe_extmark_line, safe_extmark_line + 1, false)[1] or ""
  local safe_end_col = math.max(0, #line_content)

  local current_line = vim.api.nvim_buf_get_lines(bufnr, self.ref.line - 1, self.ref.line, false)[1]
  local end_col = current_line and #current_line or 0

  local log = Logger.get()
  log:debug("Highlighting frame at line", self.ref.line, "column", self.ref.column, "end_col", end_col)

  vim.api.nvim_buf_set_extmark(bufnr, namespace, self.ref.line - 1, self.ref.column - 1, {
    end_row = self.ref.line - 1,
    end_col = end_col,
    hl_group = hl_group,
    id = 112882
  })

  return function()
    -- Cleanup function - clear the highlighting
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    end
  end
end

function Frame:toString()
  local pretty = self._source and self._source:toString() or 'unknown source'

  for _, scope in ipairs(self:scopes()) do
    pretty = pretty .. "\n  " .. scope:toString()
  end

  return string.format("Frame(%s) %s", self.ref.id, pretty)
end

return Frame
