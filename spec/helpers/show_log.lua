-- Helper script to show the log file path when running tests
local Logger = require('neodap.tools.logger')

-- Initialize the logger
local log = Logger.get()

-- Print the log file location
print("\n================================================")
print("Neodap Debug Log File:")
print(log:getFilePath())
print("================================================")
print("You can monitor this file with:")
print("tail -f " .. log:getFilePath())
print("\nOr view all logs in the project:")
print("ls -la log/")
print("================================================\n")

-- Add a test entry
log:info("Test logging system initialized")

return log:getFilePath()