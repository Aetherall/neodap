-- Unit tests for tree buffer help module
-- Tests build_content, get_desc, entries without requiring a debug session
local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local help = require("neodap.plugins.tree_buffer.help")

---------------------------------------------------------------------------
-- get_desc
---------------------------------------------------------------------------

T["get_desc"] = MiniTest.new_set()

T["get_desc"]["returns description for global key"] = function()
  MiniTest.expect.equality(help.get_desc("?"), "Toggle help")
  MiniTest.expect.equality(help.get_desc("q"), "Close tree")
  MiniTest.expect.equality(help.get_desc("R"), "Refresh")
end

T["get_desc"]["returns description for context key"] = function()
  MiniTest.expect.equality(help.get_desc("c"), "Continue")
  MiniTest.expect.equality(help.get_desc("D"), "Disconnect")
  MiniTest.expect.equality(help.get_desc("e"), "Edit value")
end

T["get_desc"]["returns nil for unknown key"] = function()
  MiniTest.expect.equality(help.get_desc("Z"), nil)
  MiniTest.expect.equality(help.get_desc(""), nil)
end

---------------------------------------------------------------------------
-- get_types
---------------------------------------------------------------------------

T["get_types"] = MiniTest.new_set()

T["get_types"]["returns nil for global keys"] = function()
  MiniTest.expect.equality(help.get_types("<CR>"), nil)
  MiniTest.expect.equality(help.get_types("q"), nil)
  MiniTest.expect.equality(help.get_types("?"), nil)
end

T["get_types"]["returns types for context keys"] = function()
  local types = help.get_types("c")
  assert(types ~= nil, "c should have types")
  assert(vim.tbl_contains(types, "Thread"), "c should include Thread")
end

T["get_types"]["X applies to Session and Config"] = function()
  local types = help.get_types("X")
  assert(types ~= nil, "X should have types")
  assert(vim.tbl_contains(types, "Session"), "X should include Session")
  assert(vim.tbl_contains(types, "Config"), "X should include Config")
end

T["get_types"]["returns nil for unknown key"] = function()
  MiniTest.expect.equality(help.get_types("Z"), nil)
end

---------------------------------------------------------------------------
-- build_content
---------------------------------------------------------------------------

T["build_content"] = MiniTest.new_set()

-- Helper: check if any line contains the given text
local function has_line_containing(lines, text)
  for _, line in ipairs(lines) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

T["build_content"]["navigation keymaps always included"] = function()
  local content = help.build_content(nil)
  assert(#content.lines > 0, "should have lines")
  assert(has_line_containing(content.lines, "Navigation"), "should have Navigation header")
  assert(has_line_containing(content.lines, "<CR>"), "should have <CR>")
  assert(has_line_containing(content.lines, "Toggle expand/collapse"), "should have expand/collapse desc")
  assert(has_line_containing(content.lines, "?"), "should have ? key")
end

T["build_content"]["no entity type shows only navigation"] = function()
  local content = help.build_content(nil)
  -- Should NOT have any entity-type headers
  assert(not has_line_containing(content.lines, "Thread"), "should not have Thread header")
  assert(not has_line_containing(content.lines, "Continue"), "should not have Thread-specific entries")
end

T["build_content"]["Thread shows thread keymaps"] = function()
  local content = help.build_content("Thread")
  assert(has_line_containing(content.lines, "Navigation"), "should have Navigation header")
  assert(has_line_containing(content.lines, "Thread"), "should have Thread header")
  assert(has_line_containing(content.lines, "Continue"), "should have Continue")
  assert(has_line_containing(content.lines, "Pause"), "should have Pause")
  assert(has_line_containing(content.lines, "Step over"), "should have Step over")
  assert(has_line_containing(content.lines, "Step into"), "should have Step into")
  assert(has_line_containing(content.lines, "Step out"), "should have Step out")
  -- Should NOT have Config-specific entries
  assert(not has_line_containing(content.lines, "Toggle view mode"), "should not have Config entries")
end

T["build_content"]["Config shows config keymaps"] = function()
  local content = help.build_content("Config")
  assert(has_line_containing(content.lines, "Config"), "should have Config header")
  assert(has_line_containing(content.lines, "Restart"), "should have Restart")
  assert(has_line_containing(content.lines, "Toggle view mode"), "should have Toggle view mode")
  assert(has_line_containing(content.lines, "Terminate"), "should have Terminate")
  -- Should NOT have Thread entries
  assert(not has_line_containing(content.lines, "Continue"), "should not have Thread entries")
end

T["build_content"]["Breakpoint shows breakpoint keymaps"] = function()
  local content = help.build_content("Breakpoint")
  assert(has_line_containing(content.lines, "Breakpoint"), "should have Breakpoint header")
  assert(has_line_containing(content.lines, "Toggle enabled"), "should have Toggle enabled")
  assert(has_line_containing(content.lines, "Remove"), "should have Remove")
  assert(has_line_containing(content.lines, "Edit condition"), "should have Edit condition")
  assert(has_line_containing(content.lines, "Edit hit condition"), "should have Edit hit condition")
  assert(has_line_containing(content.lines, "Edit log message"), "should have Edit log message")
end

T["build_content"]["Variable shows variable keymaps"] = function()
  local content = help.build_content("Variable")
  assert(has_line_containing(content.lines, "Variable"), "should have Variable header")
  assert(has_line_containing(content.lines, "Edit value"), "should have Edit value")
  assert(has_line_containing(content.lines, "Yank value"), "should have Yank value")
  assert(has_line_containing(content.lines, "Yank name"), "should have Yank name")
end

T["build_content"]["Session shows disconnect and terminate"] = function()
  local content = help.build_content("Session")
  assert(has_line_containing(content.lines, "Session"), "should have Session header")
  assert(has_line_containing(content.lines, "Disconnect"), "should have Disconnect")
  assert(has_line_containing(content.lines, "Terminate"), "should have Terminate")
end

T["build_content"]["unknown entity type shows only navigation"] = function()
  local content = help.build_content("SomeUnknownType")
  assert(has_line_containing(content.lines, "Navigation"), "should have Navigation")
  -- No entity section
  local empty_line_count = 0
  for _, line in ipairs(content.lines) do
    if line == "" then empty_line_count = empty_line_count + 1 end
  end
  MiniTest.expect.equality(empty_line_count, 0, "should have no separator (no entity section)")
end

T["build_content"]["highlights include section headers and keys"] = function()
  local content = help.build_content("Thread")
  assert(#content.highlights > 0, "should have highlights")

  local has_section_hl = false
  local has_key_hl = false
  for _, hl in ipairs(content.highlights) do
    if hl[4] == "DapHelpSection" then has_section_hl = true end
    if hl[4] == "DapHelpKey" then has_key_hl = true end
  end
  assert(has_section_hl, "should have DapHelpSection highlights")
  assert(has_key_hl, "should have DapHelpKey highlights")
end

T["build_content"]["BreakpointBinding shows binding keymaps"] = function()
  local content = help.build_content("BreakpointBinding")
  assert(has_line_containing(content.lines, "BreakpointBinding"), "should have BreakpointBinding header")
  assert(has_line_containing(content.lines, "Toggle enabled"), "should have Toggle enabled")
  assert(has_line_containing(content.lines, "Clear override"), "should have Clear override")
  assert(has_line_containing(content.lines, "Edit condition"), "should have Edit condition")
  -- Should NOT have Remove (that's Breakpoint-only)
  assert(not has_line_containing(content.lines, "Remove"), "should not have Remove")
end

T["build_content"]["ExceptionFilterBinding shows filter keymaps"] = function()
  local content = help.build_content("ExceptionFilterBinding")
  assert(has_line_containing(content.lines, "ExceptionFilterBinding"), "should have header")
  assert(has_line_containing(content.lines, "Toggle enabled"), "should have Toggle enabled")
  assert(has_line_containing(content.lines, "Edit condition"), "should have Edit condition")
  assert(has_line_containing(content.lines, "Clear override"), "should have Clear override")
end

T["build_content"]["Frame shows evaluate keymaps"] = function()
  local content = help.build_content("Frame")
  assert(has_line_containing(content.lines, "Frame"), "should have Frame header")
  assert(has_line_containing(content.lines, "Evaluate in REPL"), "should have Evaluate in REPL")
end

T["build_content"]["Scope shows refresh keymaps"] = function()
  local content = help.build_content("Scope")
  assert(has_line_containing(content.lines, "Scope"), "should have Scope header")
  assert(has_line_containing(content.lines, "Refresh variables"), "should have Refresh variables")
end

T["build_content"]["Stdio shows REPL input keymaps"] = function()
  local content = help.build_content("Stdio")
  assert(has_line_containing(content.lines, "Stdio"), "should have Stdio header")
  assert(has_line_containing(content.lines, "REPL input"), "should have REPL input")
end

---------------------------------------------------------------------------
-- entries
---------------------------------------------------------------------------

T["entries"] = MiniTest.new_set()

T["entries"]["returns all entries"] = function()
  local entries = help.entries()
  assert(#entries > 0, "should have entries")
  -- Verify structure
  for _, entry in ipairs(entries) do
    assert(type(entry.key) == "string", "entry should have key string")
    assert(type(entry.desc) == "string", "entry should have desc string")
    assert(entry.types == nil or type(entry.types) == "table", "types should be nil or table")
  end
end

T["entries"]["every default keybind has a help entry"] = function()
  local entries = help.entries()
  local keys_in_help = {}
  for _, entry in ipairs(entries) do
    keys_in_help[entry.key] = true
  end
  -- These are all the keys that should be documented
  local expected_keys = {
    "<CR>", "l", "h", "<Space>", "gd", "q", "R", "?",
    "c", "p", "n", "s", "S", "gn", "gs", "gS",
    "D", "X", "r", "v", "e", "y", "Y", "E", "i",
    "t", "dd", "C", "H", "L", "x",
  }
  for _, key in ipairs(expected_keys) do
    assert(keys_in_help[key], "key '" .. key .. "' should be in help entries")
  end
end

return T
