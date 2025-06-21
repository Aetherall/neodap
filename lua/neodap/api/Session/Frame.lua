local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Session.Scope')


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
  vim.schedule(function()
    local source = self.ref.source
    if not source then
      return
    end

    local uri = vim.uri_from_fname(source.path)
    local bufnr = vim.uri_to_bufnr(uri)
    if bufnr == -1 then
      return
    end

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { self.ref.line, self.ref.column - 1 })
  end)
end

---@param namespace integer
---@param hl_group string
function Frame:highlight(namespace, hl_group)
  vim.schedule(function()
    local source = self.ref.source
    if not source then
      return
    end

    -- Ensure line is within buffer bounds for extmark

    local uri = vim.uri_from_fname(source.path)

    print(uri)
    local bufnr = vim.uri_to_bufnr(uri)
    print(bufnr)
    if bufnr == -1 then
      return
    end

    local line_count = vim.api.nvim_buf_line_count(0)
    local safe_extmark_line = math.min(self.ref.line - 1, line_count - 1)
    safe_extmark_line = math.max(0, safe_extmark_line)

    -- Use a safe end_col value
    local line_content = vim.api.nvim_buf_get_lines(0, safe_extmark_line, safe_extmark_line + 1, false)[1] or ""
    local safe_end_col = math.max(0, #line_content)

    local current_line = vim.api.nvim_buf_get_lines(bufnr, self.ref.line - 1, self.ref.line, false)[1]
    local end_col = #current_line

    print("Debug: Highlighting frame at line " ..
      self.ref.line .. ", column " .. self.ref.column .. ", end_col " .. end_col)

    vim.api.nvim_buf_set_extmark(bufnr, namespace, self.ref.line - 1, self.ref.column - 1, {
      end_row = self.ref.line - 1,
      end_col = end_col,
      hl_group = hl_group,
      id = 112882
    })
  end)

  return function()
    vim.schedule(function()
      local source = self.ref.source
      if not source then
        return
      end

      local uri = vim.uri_from_fname(source.path)
      local bufnr = vim.uri_to_bufnr(uri)
      if bufnr == -1 then
        return
      end

      vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    end)
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
