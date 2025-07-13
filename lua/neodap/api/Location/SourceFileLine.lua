local Class = require('neodap.tools.class')
local BaseLocation = require('neodap.api.Location.Base')
local nio = require("nio")
local SourceFile = require("neodap.api.Location.SourceFile")

---@class api.SourceFileLineProps: api.BaseLocationProps
---@field path string
---@field line integer

---@class api.SourceFileLine: api.SourceFileLineProps & api.BaseLocationProps
---@field new Constructor<api.SourceFileLineProps>
local SourceFileLine = Class(BaseLocation)


---@param opts { path: string, line: integer }
function SourceFileLine.create(opts)
  return SourceFileLine:new({
    type = 'source_file_line',
    key = opts.path .. ":" .. (opts.line or 0),
    path = opts.path,
    line = opts.line,
  })
end


---@param source api.FileSource
---@param opts { line: integer }
---@return api.SourceFileLine
function SourceFileLine.fromSource(source, opts)
  local path = source:absolutePath()
  return SourceFileLine.create({
    path = path,
    line = opts.line,
  })
end

---@return api.SourceFileLine
function SourceFileLine.fromCursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  if not line then
    error("Cursor position is invalid or not set.")
  end

  local path = vim.api.nvim_buf_get_name(0)

  return SourceFileLine:new({
    type = 'source_file_line',
    key = path .. ":" .. line,
    path = path,
    line = line,
  })
end

---@param other api.Location
---@return_cast other api.SourceFileLine
function SourceFileLine:equals(other)
  return self.key == other.key
end

---@param sourceId string
---@return boolean
function SourceFileLine:isAtSourceId(sourceId)
  return sourceId == ("path:" .. self.path)
end

---@return integer?
function SourceFileLine:bufnr()
  local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(self.path))
  if bufnr == -1 then
    return nil
  end
  return bufnr
end

---@param ns integer
---@param opts vim.api.keyset.set_extmark
---@return integer?
function SourceFileLine:mark(ns, opts)
  local bufnr = self:bufnr()
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end

  local line = math.max(0, (self.line or 0) - 1)
  local bufpos = { line, 0 }

  -- Check if there is an existing extmark at this location
  local existing_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, bufpos, bufpos, { details = true })
  if #existing_extmarks > 0 then
    -- Update existing extmark
    local id = existing_extmarks[1][1]
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, vim.tbl_extend("force", opts, { id = id }))
    return id
  end

  -- Create new extmark
  return vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, opts)
end

---@param ns integer
function SourceFileLine:unmark(ns)
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

function SourceFileLine:deferUntilLoaded()
  local bufnr = self:bufnr()

  if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
    return self
  end
  
  local future = nio.control.future()
  
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return future.wait() -- This buffer will never load, block indefinitely
  end

  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    buffer = bufnr,
    once = true,
    callback = function()
      if not vim.api.nvim_buf_is_loaded(bufnr) then
        future.set(nil)
        return
      end
      future.set(self)
    end
  })

  return future.wait()
end


function SourceFileLine:SourceFile()
  return SourceFile.create({
    path = self.path,
  })
end


return SourceFileLine