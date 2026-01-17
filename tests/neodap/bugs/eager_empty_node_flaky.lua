-- Verify: nodes show consistent icon state
-- Semantic: A node shows expanded (◉) if any edge is expanded (open).
-- Sessions is collapsed by default, Targets is eager (expanded).

local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["empty node expansion"] = MiniTest.new_set()

T["empty node expansion"]["shows consistent collapsed icon"] = function()
  local child = MiniTest.new_child_neovim()
  child.restart({ "-u", "tests/init.lua", "--headless" })

  -- Setup neodap with tree_buffer
  child.cmd('lua require("neodap").setup()')
  child.cmd('lua require("neodap").use(require("neodap.plugins.tree_buffer"))')

  -- Open tree at debugger - Sessions has eager=true but no sessions
  child.cmd("edit dap://tree/@debugger")
  vim.loop.sleep(100)

  -- Capture the Sessions line multiple times to check consistency
  local results = {}
  for i = 1, 5 do
    child.cmd("redraw")
    local lines = child.api.nvim_buf_get_lines(0, 0, 5, false)

    -- Find the Sessions line and check its icon
    for _, line in ipairs(lines) do
      if line:match("Sessions") then
        -- Check for expanded (◉) or collapsed (○) icon before "Sessions"
        if line:match("◉ Sessions") then
          table.insert(results, "expanded")
        elseif line:match("○ Sessions") then
          table.insert(results, "collapsed")
        else
          table.insert(results, "unknown")
        end
        break
      end
    end

    -- Small delay between checks
    vim.loop.sleep(50)
  end

  child.stop()

  -- All results should be the same
  local first = results[1]
  for i, state in ipairs(results) do
    MiniTest.expect.equality(state, first,
      string.format("Inconsistent state at iteration %d: got %s, expected %s (all results: %s)",
        i, state, first, table.concat(results, ", ")))
  end

  -- Sessions is collapsed by default (not eager)
  MiniTest.expect.equality(first, "collapsed",
    string.format("Expected 'collapsed' for Sessions (not eager), got %s", first))
end

T["empty node expansion"]["consistent across instances"] = function()
  -- Run multiple separate instances to check cross-process consistency
  local results = {}

  for i = 1, 3 do
    local child = MiniTest.new_child_neovim()
    child.restart({ "-u", "tests/init.lua", "--headless" })

    child.cmd('lua require("neodap").setup()')
    child.cmd('lua require("neodap").use(require("neodap.plugins.tree_buffer"))')
    child.cmd("edit dap://tree/@debugger")
    vim.loop.sleep(100)

    child.cmd("redraw")
    local lines = child.api.nvim_buf_get_lines(0, 0, 5, false)

    for _, line in ipairs(lines) do
      if line:match("Sessions") then
        if line:match("◉ Sessions") then
          table.insert(results, "expanded")
        elseif line:match("○ Sessions") then
          table.insert(results, "collapsed")
        else
          table.insert(results, "unknown")
        end
        break
      end
    end

    child.stop()
  end

  -- All instances should produce the same result
  local first = results[1]
  for i, state in ipairs(results) do
    MiniTest.expect.equality(state, first,
      string.format("Instance %d got %s, expected %s (all: %s)",
        i, state, first, table.concat(results, ", ")))
  end

  -- Sessions is collapsed by default (not eager)
  MiniTest.expect.equality(first, "collapsed",
    string.format("Expected 'collapsed' for Sessions (not eager), got %s", first))
end

return T
