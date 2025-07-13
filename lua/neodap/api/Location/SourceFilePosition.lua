local Class = require('neodap.tools.class')
local BaseLocation = require('neodap.api.Location.Base')
local nio = require("nio")
local SourceFile = require("neodap.api.Location.SourceFile")

---@class api.SourceFilePositionProps: api.BaseLocationProps
---@field path string
---@field line integer
---@field column integer

---@class api.SourceFilePosition: api.SourceFilePositionProps
---@field new Constructor<api.SourceFilePositionProps>
local SourceFilePosition = Class(BaseLocation)


---@param opts { path: string, line: integer, column: integer }
function SourceFilePosition.create(opts)
  return SourceFilePosition:new({
    type = 'source_file_position',
    key = opts.path .. ":" .. (opts.line or 0) .. ":" .. (opts.column or 0),
    path = opts.path,
    line = opts.line,
    column = opts.column,
  })
end

---@param source api.FileSource
---@param opts { line: integer, column: integer }
---@return api.SourceFilePosition
function SourceFilePosition.fromSource(source, opts)
  local path = source:absolutePath()
  return SourceFilePosition.create({
    path = path,
    line = opts.line,
    column = opts.column,
  })
end

---@return api.SourceFilePosition
function SourceFilePosition.fromCursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] or 0
  local column = (cursor[2] or 0) + 1 -- Convert to 1-based index
  local path = vim.api.nvim_buf_get_name(0)

  return SourceFilePosition:new({
    type = 'source_file_position',
    key = path .. ":" .. line .. ":" .. column,
    path = path,
    line = line,
    column = column,
  })
end

---@param other api.Location
---@return_cast other api.SourceFilePosition
function SourceFilePosition:equals(other)
  return self.key == other.key
end


---@return integer?
function SourceFilePosition:bufnr()
  local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(self.path))
  if bufnr == -1 then
    return nil
  end
  return bufnr
end

---@param ns integer
---@param opts vim.api.keyset.set_extmark
---@return integer?
function SourceFilePosition:mark(ns, opts)
  local bufnr = self:bufnr()
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end

  local line = math.max(0, (self.line or 0) - 1)
  local column = math.max(0, (self.column or 0) - 1)
  local bufpos = { line, column }

  -- Check if there is an existing extmark at this location
  local existing_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, bufpos, bufpos, { details = true })
  if #existing_extmarks > 0 then
    -- Update existing extmark
    local id = existing_extmarks[1][1]
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, column, vim.tbl_extend("force", opts, { id = id }))
    return id
  end

  -- Create new extmark
  return vim.api.nvim_buf_set_extmark(bufnr, ns, line, column, opts)
end

---@param ns integer
function SourceFilePosition:unmark(ns)
  local bufnr = self:bufnr()
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local line = math.max(0, (self.line or 0) - 1)
  local column = math.max(0, (self.column or 0) - 1)
  local bufpos = { line, column }

  -- Get all extmarks at this location
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, bufpos, bufpos, { details = true })

  for _, extmark in ipairs(extmarks) do
    local id = extmark[1]
    vim.api.nvim_buf_del_extmark(bufnr, ns, id)
  end
end

function SourceFilePosition:SourceFile()
  return SourceFile.create({
    path = self.path,
  })
end


return SourceFilePosition