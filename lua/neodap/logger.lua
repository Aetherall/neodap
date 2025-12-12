-- Logger module for neodap
--
-- Re-exports neolog with neodap-specific defaults.
--
-- Usage:
--   local log = require("neodap.logger")
--   log:debug("message")
--   log:info("message", { key = "value" })

return require("neolog").new("neodap")
