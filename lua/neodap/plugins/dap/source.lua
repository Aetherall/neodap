-- Source and SourceBinding entity DAP methods
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local a = require("neodap.async")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local log = require("neodap.logger")

local Source = entities.Source
local SourceBinding = entities.SourceBinding

local get_dap_session = context.get_dap_session

---Load source content via DAP request
---@param self neodap.entities.SourceBinding
---@return string content
function SourceBinding:loadContent()
  local source_ref = self.sourceReference:get()
  if not source_ref or source_ref == 0 then
    error("No sourceReference", 0)
  end

  local session = self.session:get()
  if not session then
    error("No session", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

  local source = self.source:get()
  local path = source and source.path:get()
  local name = source and source.name:get()

  local body = a.wait(function(cb)
    dap_session.client:request("source", {
      sourceReference = source_ref,
      source = {
        path = path,
        name = name,
        sourceReference = source_ref,
      },
    }, cb)
  end, "SourceBinding:loadContent")

  -- Update source content if we have a source
  if source then
    source:update({ content = body.content })
  end
  return body.content
end
SourceBinding.loadContent = a.memoize(SourceBinding.loadContent)

---Load source content and store in content property
---@param self neodap.entities.Source
---@param session_id? string Optional session ID for explicit binding
---@return string content
function Source:loadContent(session_id)
  -- Explicit session: use that binding
  if session_id then
    local binding = self:findBinding(session_id)
    if not binding then error("No binding for session: " .. session_id, 0) end
    return binding:loadContent()
  end

  -- Virtual source: delegate to context-resolved binding
  if self:isVirtual() then
    local binding = self:bindingForContext()
    if binding then
      return binding:loadContent()
    end
  end

  -- File-based source: read from filesystem
  local path = self.path:get()
  if path and vim.fn.filereadable(path) == 1 then
    local lines = vim.fn.readfile(path)
    local content = table.concat(lines, "\n")
    self:update({ content = content })
    return content
  end

  error("Cannot load source content", 0)
end
Source.loadContent = a.memoize(Source.loadContent)

---Open this source in a buffer and optionally position cursor
---Handles both file-based and virtual sources transparently
---@param self neodap.entities.Source
---@param opts? { line?: number, column?: number }
---@return number? bufnr Buffer number or nil
function Source:open(opts)
  opts = opts or {}
  local location = self:bufferUri()
  if not location then
    return nil
  end

  local function position_cursor(bufnr)
    if opts.line and vim.api.nvim_buf_line_count(bufnr) >= opts.line then
      vim.api.nvim_win_set_cursor(0, { opts.line, opts.column or 0 })
    end
    return bufnr
  end

  if self:isVirtual() then
    -- For virtual sources, set dap_pending_cursor BEFORE opening the buffer.
    -- This way source_buffer.lua will position cursor after async content loads.
    -- We can't position cursor directly because content isn't loaded yet.
    vim.cmd("edit " .. vim.fn.fnameescape(location))
    local bufnr = vim.api.nvim_get_current_buf()
    if opts.line then
      vim.b[bufnr].dap_pending_cursor = { line = opts.line, col = opts.column or 0 }
    end
    return bufnr
  else
    -- File-based: content is available immediately
    vim.cmd("edit " .. vim.fn.fnameescape(location))
    local bufnr = vim.api.nvim_get_current_buf()
    return position_cursor(bufnr)
  end
end
Source.open = a.fn(Source.open)

---Add a breakpoint to this source
---@param self neodap.entities.Source
---@param opts { line: number, column?: number, condition?: string, hitCondition?: string, logMessage?: string, enabled?: boolean }
---@return neodap.entities.Breakpoint
function Source:addBreakpoint(opts)
  local graph = self._graph
  local debugger = self.debugger:get()
  local source_path = self.path:get() or self.key:get()

  -- Default enabled to true if not specified
  local enabled = (opts.enabled == nil) and true or opts.enabled

  local bp = entities.Breakpoint.new(graph, {
    uri = uri.breakpoint(source_path, opts.line, opts.column),
    line = opts.line,
    column = opts.column,
    condition = opts.condition,
    hitCondition = opts.hitCondition,
    logMessage = opts.logMessage,
    enabled = enabled,
  })

  -- Link to source and debugger
  self.breakpoints:link(bp)
  if debugger then
    debugger.breakpoints:link(bp)
  end

  log:info("Breakpoint added: " .. bp.uri:get())

  return bp
end

return {
  Source = Source,
  SourceBinding = SourceBinding,
}
