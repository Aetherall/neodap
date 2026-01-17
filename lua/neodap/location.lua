-- Location value object: path[:line[:column]]
-- Line nil = File (path only)
-- Column nil = Line (adjust to valid column)
-- Column set = Point (exact location)

local Location = {}
Location.__index = Location

function Location.new(path, line, column)
  return setmetatable({ path = path, line = line, column = column }, Location)
end

function Location.parse(str)
  local path, line, col = str:match("(.+):(%d+):(%d+)$")
  if path then return Location.new(path, tonumber(line), tonumber(col)) end
  path, line = str:match("(.+):(%d+)$")
  if path then return Location.new(path, tonumber(line)) end
  return Location.new(str)
end

function Location.from_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local pos = vim.api.nvim_win_get_cursor(0)
  return Location.new(path, pos[1]) -- Line, not Point
end

function Location:is_file() return self.line == nil end

function Location:is_line() return self.line ~= nil and self.column == nil end

function Location:is_point() return self.column ~= nil end

function Location:format()
  if self.column then return string.format("%s:%d:%d", self.path, self.line, self.column) end
  if self.line then return string.format("%s:%d", self.path, self.line) end
  return self.path
end

function Location:__tostring() return self:format() end

---Get buffer number for this location's path
---@return number? bufnr
function Location:bufnr()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) == self.path then
      return bufnr
    end
  end
  return nil
end

return Location
