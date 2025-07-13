local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Session.Scope')
local Logger = require('neodap.tools.logger')


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
  
  -- Create location for the frame position
  local Location = require('neodap.api.Location')
  local location
  
  if source_obj:isFile() then
    location = Location.fromSource(source_obj, {
      line = self.ref.line,
      column = self.ref.column
    })
  elseif source_obj:isVirtual() then
    location = Location.fromVirtualSource(source_obj, {
      line = self.ref.line,
      column = self.ref.column
    })
  else
    return -- Generic sources not navigable
  end
  
  -- Use location to get buffer
  local bufnr = location:bufnr()
  if not bufnr then
    -- For virtual sources, this triggers buffer creation
    if source_obj:isVirtual() then
      bufnr = source_obj:bufnr() -- Create buffer if needed
      if not bufnr then
        return -- Buffer creation failed
      end
    else
      return
    end
  end
  
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { self.ref.line, self.ref.column - 1 })
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
  
  -- Create location for the frame position
  local Location = require('neodap.api.Location')
  local location
  
  if source_obj:isFile() then
    location = Location.fromSource(source_obj, {
      line = self.ref.line,
      column = self.ref.column
    })
  elseif source_obj:isVirtual() then
    location = Location.fromVirtualSource(source_obj, {
      line = self.ref.line,
      column = self.ref.column
    })
  else
    return -- Generic sources not navigable
  end
  
  -- Use location to get buffer
  local bufnr = location:bufnr()
  if not bufnr then
    -- For virtual sources, this triggers buffer creation
    if source_obj:isVirtual() then
      bufnr = source_obj:bufnr() -- Create buffer if needed
      if not bufnr then
        return -- Buffer creation failed
      end
    else
      return
    end
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
