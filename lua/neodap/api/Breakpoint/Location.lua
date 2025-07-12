local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")
local logger = require("neodap.tools.logger")

local set = vim.api.nvim_buf_set_extmark

---@class api.SourceFileLocationProps
---@field key string
---@field path string
---@field line integer
---@field column? integer

---@class api.VirtualFileLocationProps
---@field key string
---@field identifier string
---@field line integer
---@field column? integer

---@class api.SourceFileLocation: api.SourceFileLocationProps
---@field new Constructor<api.SourceFileLocationProps>
local SourceFileLocation = Class()

---@param source api.FileSource
---@param opts { line: integer, column?: integer }
---@return api.SourceFileLocation
function SourceFileLocation.fromSource(source, opts)
  local path = source:absolutePath()
  return SourceFileLocation:new({
    path = path,
    line = opts.line,
    column = opts.column,
    key = path .. ":" .. (opts.line or 0) .. ":" .. (opts.column or 0),
  })
end

---@param dapBinding dap.Breakpoint
function SourceFileLocation.fromDapBinding(dapBinding)
  if not dapBinding.source or not dapBinding.source.path or not dapBinding.line then
    return nil
  end

  return SourceFileLocation:new({
    path = dapBinding.source.path,
    line = dapBinding.line,
    column = dapBinding.column,
    key = dapBinding.source.path .. ":" .. (dapBinding.line or 0) .. ":" .. (dapBinding.column or 0),
  })
end

function SourceFileLocation.fromCursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local column = cursor[2] + 1 -- Convert to 1-based index
  local path = vim.api.nvim_buf_get_name(0)

  return SourceFileLocation:new({
    path = path,
    line = line,
    column = column,
    key = path .. ":" .. line .. ":" .. column,
  })
end


function SourceFileLocation:matches(other)
  return self.key == other.key
end

function SourceFileLocation:isAtSourceId(sourceId)
  return sourceId  == ("path:".. self.path)
end

function SourceFileLocation:bufnr()
  local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(self.path))
  if bufnr == -1 then
    return nil
  end
  return bufnr
end


---@param ns integer
---@param opts vim.api.keyset.set_extmark
function SourceFileLocation:mark(ns, opts)
  local bufnr = self:bufnr()
  if not bufnr then
    return
  end

  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  
  local line = math.max(0, (self.line or 0) - 1)
  local column = math.max(0, (self.column or 0) - 1)
  local bufpos = { line, column }

  -- Check if there is an existing extmark at this location for the same namespace
  local existing_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, bufpos, bufpos, { details = true })
  if #existing_extmarks > 0 then
    -- If an extmark already exists, update it instead of creating a new one
    local id = existing_extmarks[1][1]
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, column, vim.tbl_extend("force", opts, { id = id }))
    return id
  end

  logger.get():error("SourceFileLocation:mark", bufnr, line, column )
  vim.api.nvim_buf_set_extmark(bufnr, ns, line, column, opts)
end


function SourceFileLocation:unmark(ns)
  local bufnr = self:bufnr()
  if not bufnr then
    return nil
  end

  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local line = math.max(0, (self.line or 0) - 1)
  local column = math.max(0, (self.column or 0) - 1)
  local bufpos = { line, column }

  -- Get all extmarks at this location for the given namespace
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, bufpos, bufpos, { details = true })
  logger.get():error("SourceFileLocation:unmark", bufnr, line, column, extmarks)

  for _, extmark in ipairs(extmarks) do
    local id = extmark[1]
    local found = vim.api.nvim_buf_del_extmark(bufnr, ns, id)
    if not found then
      logger.get():warn("SourceFileLocation:unmark - Failed to delete extmark", id, "at", bufnr, line, column)
    else
      logger.get():debug("SourceFileLocation:unmark - Deleted extmark", id, "at", bufnr, line, column)
    end
  end
end


---@class api.VirtualFileLocation: api.VirtualFileLocationProps
---@field new Constructor<api.VirtualFileLocationProps>
local VirtualFileLocation = Class()


return {
  SourceFile = SourceFileLocation,
  VirtualFile = VirtualFileLocation,
}