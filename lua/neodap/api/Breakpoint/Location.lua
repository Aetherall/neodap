local Class = require('neodap.tools.class')
local nio = require("nio")

---@class api.SourceFileLocationProps
---@field key string
---@field path string
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
---@return api.SourceFileLocation?
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

---@return api.SourceFileLocation
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

---@param other api.SourceFileLocation
---@return boolean
function SourceFileLocation:matches(other)
  return self.key == other.key
end

---@param sourceId string
---@return boolean
function SourceFileLocation:isAtSourceId(sourceId)
  return sourceId == ("path:" .. self.path)
end

---@return integer?
function SourceFileLocation:bufnr()
  local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(self.path))
  if bufnr == -1 then
    return nil
  end
  return bufnr
end

---@param ns integer
---@param opts vim.api.keyset.set_extmark
---@return integer?
function SourceFileLocation:mark(ns, opts)
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
function SourceFileLocation:unmark(ns)
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

function SourceFileLocation:deferUntilLoaded()
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


return {
  SourceFile = SourceFileLocation,
}