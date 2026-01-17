-- Unit tests for URI parsing
-- Tests the uri module without requiring a debug session
local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local uri = require("neodap.uri")

T["parse"] = MiniTest.new_set()

T["parse"]["returns nil for invalid URI"] = function()
  MiniTest.expect.equality(uri.parse("invalid"), nil)
  MiniTest.expect.equality(uri.parse("unknown:type"), nil)
end

T["parse"]["returns nil for empty string"] = function()
  MiniTest.expect.equality(uri.parse(""), nil)
end

return T
