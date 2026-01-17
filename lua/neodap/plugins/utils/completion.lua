-- Completion utilities

local M = {}

-- Map DAP completion types to vim complete-item kinds
M.type_to_kind = {
  method = "m",
  ["function"] = "f",
  constructor = "f",
  field = "v",
  variable = "v",
  class = "t",
  interface = "t",
  module = "m",
  property = "v",
  unit = "v",
  value = "v",
  enum = "t",
  keyword = "k",
  snippet = "s",
  text = "t",
  color = "v",
  file = "f",
  reference = "v",
  customcolor = "v",
}

---Find the start position for completion (0-indexed)
---Scans backwards from cursor to find word boundary
---@param line string Current line text
---@param col number 0-indexed cursor column
---@return number start 0-indexed start position
function M.find_completion_start(line, col)
  local start = col
  while start > 0 do
    local char = line:sub(start, start)
    -- Break on whitespace, operators, brackets, and property access (.)
    if char:match("[%s%(%[%{%,%;%=%+%-%*%/%<>%&%|%!%~%^%%%#%.]") then
      break
    end
    start = start - 1
  end
  return start
end

return M
