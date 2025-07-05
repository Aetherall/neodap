-- Silent helper to get the log file path
local Logger = require('neodap.tools.logger')

local function get_log_path()
  local log = Logger.get()
  return log:getFilePath()
end

return get_log_path