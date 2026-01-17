#!/usr/bin/env -S nvim -u NONE -S

-- neodap Demo Script
-- Run with: nvim -u NONE -S run.lua
-- Or make executable and run: ./run.lua

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local DEMO_LANG = vim.env.DEMO_LANG or "node" -- "node" or "python"
local JSDBG_PATH = vim.env.JSDBG_PATH or "js-debug"
local DEBUGPY_PATH = vim.env.DEBUGPY_PATH

--------------------------------------------------------------------------------
-- Setup paths (no lazy.nvim - direct rtp)
--------------------------------------------------------------------------------

local root = "/tmp/neodap-demo"
vim.fn.mkdir(root, "p")

-- Add plugins to runtimepath
-- Note: code-workspace and neograph are vendored in neodap
local neodap_path = vim.fn.getcwd()
local treesitter_path = vim.env.TREESITTER_PATH

vim.opt.rtp:prepend(neodap_path)

-- Add treesitter with parsers if available (from nix flake)
if treesitter_path and vim.fn.isdirectory(treesitter_path) == 1 then
  vim.opt.rtp:prepend(treesitter_path)
end

-- Add neotest and dependencies from .tests/plugins
local test_plugins = neodap_path .. "/.tests/plugins"
vim.opt.rtp:prepend(test_plugins .. "/neotest")
vim.opt.rtp:prepend(test_plugins .. "/neotest-jest")
vim.opt.rtp:prepend(test_plugins .. "/nvim-nio")
vim.opt.rtp:prepend(test_plugins .. "/plenary.nvim")
vim.opt.rtp:prepend(test_plugins .. "/FixCursorHold.nvim")
vim.opt.rtp:prepend(test_plugins .. "/overseer.nvim")

-- Source neotest plugin file to register commands
vim.cmd("runtime plugin/neotest.lua")

-- Set up overseer for task running (preLaunchTask/postDebugTask support)
require("overseer").setup({
  strategy = "jobstart",
  templates = { "builtin", "vscode" },
})

-- Use test harness treesitter parsers (already symlinked from nix)
local ts_dir = neodap_path .. "/.tests/treesitter"
if vim.uv.fs_stat(ts_dir .. "/parser/javascript.so") then
  vim.opt.runtimepath:prepend(ts_dir)
end

--------------------------------------------------------------------------------
-- Basic Neovim Settings
--------------------------------------------------------------------------------
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.termguicolors = true
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.swapfile = false 

--------------------------------------------------------------------------------
-- Demo Files & Workspace Setup
--------------------------------------------------------------------------------

local demo_dir = root .. "/demo-files"
vim.fn.mkdir(demo_dir, "p")
vim.fn.mkdir(demo_dir .. "/.vscode", "p")

-- JavaScript demo file
local js_demo = demo_dir .. "/demo.js"
local js_content = [[
// neodap Demo - JavaScript
// Set breakpoints and step through!

function fibonacci(n) {
  if (n <= 1) return n;
  return fibonacci(n - 1) + fibonacci(n - 2);
}

function main() {
  console.log("Starting fibonacci demo...");

  const numbers = [5, 10, 15];
  const results = {};

  for (const num of numbers) {
    const result = fibonacci(num);
    results[num] = result;
    console.log(`fibonacci(${num}) = ${result}`);
  }

  console.log("Results:", results);
  return results;
}

main();
]]

-- Python demo file
local py_demo = demo_dir .. "/demo.py"
local py_content = [[
# neodap Demo - Python
# Set breakpoints and step through!

def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

def main():
    print("Starting fibonacci demo...")

    numbers = [5, 10, 15]
    results = {}

    for num in numbers:
        result = fibonacci(num)
        results[num] = result
        print(f"fibonacci({num}) = {result}")

    print("Results:", results)
    return results

if __name__ == "__main__":
    main()
]]

-- JavaScript stress test (thousands of logs)
local js_stress = demo_dir .. "/stress.js"
local js_stress_content = [=[
// Stress test - produces thousands of log lines

function main() {
  console.log("Starting stress test...");

  for (let i = 0; i < 5000; i++) {
    const status = i % 2 === 0 ? "even" : "odd";
    const hash = (i * 2654435761) >>> 0;
    console.log(`[${i.toString().padStart(4, '0')}] Processing item ${i} - status: ${status} - hash: ${hash}`);
    if (i % 1000 === 0 && i > 0) {
      console.log(`=== Milestone: ${i} items processed ===`);
    }
  }

  console.log("Stress test complete!");
}

main();
]=]

-- tasks.json for overseer (preLaunchTask/postDebugTask)
local tasks_json = demo_dir .. "/.vscode/tasks.json"
local tasks_content = [[
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "echo",
      "args": ["[preLaunchTask] Building project..."],
      "problemMatcher": []
    },
    {
      "label": "cleanup",
      "type": "shell",
      "command": "echo",
      "args": ["[postDebugTask] Cleaning up..."],
      "problemMatcher": []
    }
  ]
}
]]

-- launch.json for VS Code style configuration
local launch_json = demo_dir .. "/.vscode/launch.json"
local launch_content = string.format([[
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "pwa-node",
      "request": "launch",
      "name": "jsfile",
      "program": "${file}",
      "stopOnEntry": false,
      "sourceMaps": true
    },
    {
      "type": "pwa-node",
      "request": "launch",
      "name": "jsfile (with build task)",
      "program": "${file}",
      "stopOnEntry": false,
      "sourceMaps": true,
      "preLaunchTask": "build",
      "postDebugTask": "cleanup"
    },
    {
      "type": "python",
      "request": "launch",
      "name": "pyfile",
      "program": "${file}",
      "console": "internalConsole",
      "stopOnEntry": true
    },
    {
      "type": "pwa-node",
      "request": "launch",
      "name": "Stress Test (5000 logs)",
      "program": "%s/stress.js",
      "stopOnEntry": false
    }
  ]
}
]], demo_dir)

-- Write demo files
local function write_file(path, content)
  local file = io.open(path, "w")
  if file then
    file:write(content)
    file:close()
  end
end

-- Python test file for neotest demo
local py_test = demo_dir .. "/test_demo.py"
local py_test_content = [[
# Test file for neotest + neodap demo
import pytest

def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

def test_fibonacci_base():
    """Test base cases"""
    assert fibonacci(0) == 0
    assert fibonacci(1) == 1

def test_fibonacci_small():
    """Test small values"""
    assert fibonacci(5) == 5
    assert fibonacci(10) == 55

def test_fibonacci_larger():
    """Test larger value - set breakpoint here!"""
    result = fibonacci(15)
    assert result == 610  # This is correct
]]

write_file(js_demo, js_content)
write_file(py_demo, py_content)
write_file(js_stress, js_stress_content)
write_file(py_test, py_test_content)
write_file(tasks_json, tasks_content)
write_file(launch_json, launch_content)

--------------------------------------------------------------------------------
-- Adapter Configuration
--------------------------------------------------------------------------------

-- Build adapters table for neodap.setup()
local adapters = {}

-- Node.js adapter (js-debug) - spawns server, detects port, connects
adapters["pwa-node"] = {
  type = "server",
  command = JSDBG_PATH,
  args = { "0" },  -- port 0 = auto-assign
  connect_condition = function(output)
    -- js-debug outputs "Debug server listening at ::1:PORT"
    local port = output:match(":(%d+)%s*$")
    if port then return tonumber(port), "::1" end
  end,
}

-- Python adapter (debugpy)
if DEBUGPY_PATH then
  adapters["python"] = {
    type = "stdio",
    command = DEBUGPY_PATH,
    args = { "-m", "debugpy.adapter" },
  }
end

--------------------------------------------------------------------------------
-- Plugin Setup
--------------------------------------------------------------------------------

-- Clear neodap cache to ensure fresh code on reload
for k in pairs(package.loaded) do
  if type(k) == "string" and (k:match("^neodap") or k:match("^dap%-lua")) then
    package.loaded[k] = nil
  end
end

local neodap = require("neodap")
local debugger = require("neodap.boost").setup({
  adapters = adapters,
  keys = true,
})

-- Load neotest strategy plugin (polyfill replaces neotest's "dap" strategy)
local neotest_strategy = debugger:use(neodap.plugins.neotest_strategy, { polyfill = true })

-- Load overseer plugin (preLaunchTask/postDebugTask support)
local overseer = debugger:use(neodap.plugins.overseer)

-- Configure neotest with Jest adapter for JavaScript
-- The "dap" strategy is polyfilled by neotest_strategy plugin above
local ok, err = pcall(function()
  require("neotest").setup({
    adapters = {
      require("neotest-jest")({
        jestCommand = "npx jest",
        jestConfigFile = "jest.config.js",
        env = { CI = true },
        cwd = function() return vim.fn.getcwd() end,
        -- Custom isTestFile bypasses async hasJestDependency check
        isTestFile = function(file_path)
          return file_path:match("%.test%.[jt]sx?$") or file_path:match("%.spec%.[jt]sx?$")
        end,
      }),
    },
  })

  -- Add treesitter parsers to neotest subprocess
  -- Use add_to_rtp with our parser module - this adds the containing directory to rtp
  vim.defer_fn(function()
    local lib = require("neotest.lib")
    if lib.subprocess.enabled() then
      local neodap_parsers = require("neodap_parsers")
      lib.subprocess.add_to_rtp({ neodap_parsers.setup })
    end
  end, 500)
end)
if not ok then
  vim.notify("neotest setup failed: " .. tostring(err), vim.log.levels.WARN)
end

-- Store references globally for interactive exploration
_G.neodap = neodap
_G.debugger = neodap.debugger

--------------------------------------------------------------------------------
-- Keymaps
--------------------------------------------------------------------------------

local function setup_keymaps()
  -- Breakpoints
  vim.keymap.set("n", "<leader>B", "<cmd>Dap breakpoint condition<cr>", { desc = "Conditional Breakpoint" })

  -- Launch/Toggle
  vim.keymap.set("n", "<leader>ds", "<cmd>DapLaunch<cr>", { desc = "Start Debug (pick config)" })
  vim.keymap.set("n", "<leader>dt", "<cmd>Dap toggle<cr>", { desc = "Toggle Debug Session" })

  -- Focus navigation
  vim.keymap.set("n", "<leader>fu", "<cmd>Dap focus frame up<cr>", { desc = "Frame Up" })
  vim.keymap.set("n", "<leader>fd", "<cmd>Dap focus frame down<cr>", { desc = "Frame Down" })

  -- Neotest (debug tests with neodap)
  vim.keymap.set("n", "<leader>td", function()
    require("neotest").run.run({ strategy = "dap" })
  end, { desc = "Debug Test (neotest + neodap)" })
  vim.keymap.set("n", "<leader>tr", function()
    require("neotest").run.run()
  end, { desc = "Run Test" })
  vim.keymap.set("n", "<leader>ts", function()
    require("neotest").summary.toggle()
  end, { desc = "Toggle Test Summary" })
end

--------------------------------------------------------------------------------
-- Demo UI
--------------------------------------------------------------------------------

local function show_help()
  local python_status = DEBUGPY_PATH and "configured" or "NOT SET"
  local help = [[
neodap Demo
===========

Keybindings:
  <F5>        - Continue
  <S-F5>      - Terminate session
  <F6>        - Pause
  <F9>        - Toggle breakpoint
  <F10>       - Step Over
  <F11>       - Step Into
  <S-F11>     - Step Out
  <leader>ds  - Start debug (pick from launch.json)
  <leader>dt  - Toggle debug session
  <leader>B   - Set conditional breakpoint
  <leader>do  - Open debug tree
  <leader>db  - List breakpoints
  <leader>fu  - Frame up
  <leader>fd  - Frame down

Commands:
  :Dap continue           - Continue execution
  :Dap step over/into/out - Stepping
  :Dap breakpoint         - Toggle breakpoint at cursor
  :Dap breakpoint condition <line> <expr>
  :Dap terminate          - Terminate session
  :Dap toggle             - Start/stop debugging
  :DapLaunch              - Pick and launch debug config
  :DapLaunch jsfile       - Launch by name

Demo files created at:
  ]] .. demo_dir .. [[


Launch configurations in:
  ]] .. launch_json .. [[


Environment:
  DEMO_LANG=node|python   - Default language (current: ]] .. DEMO_LANG .. [[)
  DEBUGPY_PATH            - Python adapter (]] .. python_status .. [[)
  JSDBG_PATH              - js-debug path (current: ]] .. JSDBG_PATH .. [[)

Press any key to dismiss...
]]

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(help, "\n"))
  vim.bo[buf].modifiable = false

  local width = 65
  local height = 35
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " neodap Demo ",
    title_pos = "center",
  })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })
end

--------------------------------------------------------------------------------
-- Initialize Demo
--------------------------------------------------------------------------------

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    setup_keymaps()

    -- Change to demo directory so launch.json is found
    vim.cmd("cd " .. demo_dir)

    -- Open demo file
    local demo_file = DEMO_LANG == "python" and py_demo or js_demo
    vim.cmd("edit " .. demo_file)

    -- Set breakpoint on line 12 (inside main/loop)
    vim.defer_fn(function()
      vim.cmd("Dap breakpoint 12")
      vim.cmd("DapLaunch jsfile")
    end, 200)
  end,
})

-- Create user command to show help
vim.api.nvim_create_user_command("DapDemoHelp", show_help, {
  desc = "Show neodap demo help",
})

print("neodap Demo loaded! Use <leader>ds or :DapLaunch to start debugging.")
