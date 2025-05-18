local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Scope')


---@class api.FrameProps
---@field stack api.Stack
---@field ref dap.StackFrame

---@class api.Frame: api.FrameProps
---@field _scopes api.Scope[] | nil
---@field new Constructor<api.FrameProps>
local Frame = Class()

---@param stack api.Stack
---@param frame dap.StackFrame
function Frame.instanciate(stack, frame)
  local instance = Frame:new({
    stack = stack,
    --- DAP
    _scopes = nil,
    --- State
    ref = frame,
  })
  return instance
end

---@return api.Scope[]
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

function Frame:next()
  local context = self.stack:frames()
  local current_index = vim.tbl_index_of(context, self)
  if current_index == -1 or current_index == 1 then
    return nil
  end

  return context[current_index - 1]
end

function Frame:previous()
  local context = self.stack:frames()
  local current_index = vim.tbl_index_of(context, self)
  if current_index == -1 or current_index == #context then
    return nil
  end

  return context[current_index + 1]
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

    local uri = vim.uri_from_fname(source.path)
    local bufnr = vim.uri_to_bufnr(uri)
    if bufnr == -1 then
      return
    end

    local current_line = vim.api.nvim_buf_get_lines(bufnr, self.ref.line - 1, self.ref.line, false)[1]
    local end_col = #current_line

    vim.api.nvim_buf_set_extmark(bufnr, namespace, self.ref.line - 1, self.ref.column - 1, {
      end_row = self.ref.line - 1,
      end_col = end_col,
      hl_group = hl_group,
      id = self.ref.id,
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

return Frame
