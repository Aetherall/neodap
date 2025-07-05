local Logger = require('neodap.tools.logger')

local M = {}

---Print the log file path to the console
function M.show_log_path()
  local logger = Logger.get()
  local path = logger:getFilePath()
  print("\n=== Neodap Debug Log ===")
  print("Log file location: " .. path)
  print("View with: tail -f " .. path)
  print("========================\n")
  return path
end

---Open the log file in a new buffer
function M.open_log()
  local logger = Logger.get()
  local path = logger:getFilePath()
  vim.cmd('split ' .. path)
  vim.cmd('setlocal autoread')
  -- Jump to end of file
  vim.cmd('normal! G')
end

---Start tailing the log file in a terminal
function M.tail_log()
  local logger = Logger.get()
  local path = logger:getFilePath()
  vim.cmd('split | terminal tail -f ' .. path)
  vim.cmd('startinsert')
end

return M