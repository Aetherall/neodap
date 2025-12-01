-- User-facing API - Singleton debugger
-- This is what end users require

local sdk = require('neodap.sdk')
local debugger = sdk:create_debugger()

-- Setup URI handler for virtual sources
require("neodap.plugins.source_buffer").setup(debugger)

return debugger
