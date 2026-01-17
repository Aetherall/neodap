local MiniTest = require("mini.test")
local uri = require("neodap.uri")

local T = MiniTest.new_set()

--------------------------------------------------------------------------------
-- URI Builders
--------------------------------------------------------------------------------

T["builders"] = MiniTest.new_set()

T["builders"]["debugger"] = function()
  MiniTest.expect.equality(uri.debugger(), "debugger")
end

T["builders"]["session"] = function()
  MiniTest.expect.equality(uri.session("xotat"), "session:xotat")
  MiniTest.expect.equality(uri.session("abc123"), "session:abc123")
end

T["builders"]["thread"] = function()
  MiniTest.expect.equality(uri.thread("xotat", 1), "thread:xotat:1")
  MiniTest.expect.equality(uri.thread("abc", 42), "thread:abc:42")
end

T["builders"]["stack"] = function()
  MiniTest.expect.equality(uri.stack("xotat", 1, 5), "stack:xotat:1:5")
end

T["builders"]["frame"] = function()
  -- frame URI includes stops for uniqueness when debuggers reuse frameIds
  MiniTest.expect.equality(uri.frame("xotat", 1, 42), "frame:xotat:1:42")
  MiniTest.expect.equality(uri.frame("abc", 0, 100), "frame:abc:0:100")
end

T["builders"]["scope"] = function()
  -- scope URI includes stops
  MiniTest.expect.equality(uri.scope("xotat", 1, 42, "Locals"), "scope:xotat:1:42:Locals")
  -- Name can contain colons
  MiniTest.expect.equality(uri.scope("xotat", 1, 42, "dict['a:b']"), "scope:xotat:1:42:dict['a:b']")
end

T["builders"]["variable"] = function()
  MiniTest.expect.equality(uri.variable("xotat", 100, "x"), "variable:xotat:100:x")
  -- Name can contain colons
  MiniTest.expect.equality(uri.variable("xotat", 100, "a:b"), "variable:xotat:100:a:b")
end

T["builders"]["source"] = function()
  MiniTest.expect.equality(uri.source("/path/to/file.py"), "source:/path/to/file.py")
  MiniTest.expect.equality(uri.source("abc12_main.py"), "source:abc12_main.py")
end

T["builders"]["sourceBinding"] = function()
  MiniTest.expect.equality(uri.sourceBinding("xotat", "/path/file.py"), "sourcebinding:xotat:/path/file.py")
end

T["builders"]["breakpoint"] = function()
  MiniTest.expect.equality(uri.breakpoint("/path/file.py", 42, 0), "breakpoint:/path/file.py:42:0")
  -- Column defaults to 0
  MiniTest.expect.equality(uri.breakpoint("/path/file.py", 42), "breakpoint:/path/file.py:42:0")
  -- Path can contain colons (Windows)
  MiniTest.expect.equality(uri.breakpoint("C:/Users/file.py", 10, 5), "breakpoint:C:/Users/file.py:10:5")
end

T["builders"]["breakpointBinding"] = function()
  MiniTest.expect.equality(uri.breakpointBinding("xotat", "/path/file.py", 42, 0), "bpbinding:xotat:/path/file.py:42:0")
end

T["builders"]["output"] = function()
  MiniTest.expect.equality(uri.output("xotat", 156), "output:xotat:156")
end

T["builders"]["exceptionFilter"] = function()
  MiniTest.expect.equality(uri.exceptionFilter("xotat", "all"), "exfilter:xotat:all")
end

T["builders"]["stdio"] = function()
  MiniTest.expect.equality(uri.stdio("xotat"), "stdio:xotat")
end

T["builders"]["breakpointsGroup"] = function()
  MiniTest.expect.equality(uri.breakpointsGroup(), "breakpoints:group")
end

T["builders"]["sessionsGroup"] = function()
  MiniTest.expect.equality(uri.sessionsGroup(), "sessions:group")
end

--------------------------------------------------------------------------------
-- Type Derivation
--------------------------------------------------------------------------------

T["type_of"] = MiniTest.new_set()

T["type_of"]["extracts type from URI"] = function()
  MiniTest.expect.equality(uri.type_of("debugger"), "Debugger")
  MiniTest.expect.equality(uri.type_of("session:xotat"), "Session")
  MiniTest.expect.equality(uri.type_of("thread:xotat:1"), "Thread")
  MiniTest.expect.equality(uri.type_of("frame:xotat:42"), "Frame")
  MiniTest.expect.equality(uri.type_of("scope:xotat:42:Locals"), "Scope")
  MiniTest.expect.equality(uri.type_of("variable:xotat:100:x"), "Variable")
  MiniTest.expect.equality(uri.type_of("source:/path/file.py"), "Source")
  MiniTest.expect.equality(uri.type_of("breakpoint:/path:42:0"), "Breakpoint")
  MiniTest.expect.equality(uri.type_of("bpbinding:xotat:/path:42:0"), "BreakpointBinding")
  MiniTest.expect.equality(uri.type_of("output:xotat:1"), "Output")
  MiniTest.expect.equality(uri.type_of("stdio:xotat"), "Stdio")
end

T["type_of"]["returns nil for invalid URI"] = function()
  MiniTest.expect.equality(uri.type_of(""), nil)
  MiniTest.expect.equality(uri.type_of("invalid"), nil)
end

return T
