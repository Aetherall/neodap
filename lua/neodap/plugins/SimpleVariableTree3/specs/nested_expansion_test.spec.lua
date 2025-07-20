-- Test: Nested variable expansion in Neo-tree
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local SimpleVariableTree3 = require("neodap.plugins.SimpleVariableTree3")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("SimpleVariableTree3 Nested Expansion", function()
    Test.It("nested_variable_expansion_snapshots", function()
        local api, start = prepare()

        local simpleTree = api:getPluginInstance(SimpleVariableTree3)
        local neotree = require("neo-tree")

        neotree.setup({
            sources = { "neodap.plugins.SimpleVariableTree3" },
            default_source = "NeodapVariables"
        })

        -- Get plugin instances
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)

        -- Open file and set breakpoint
        vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")
        vim.api.nvim_win_set_cursor(0, { 3, 1 })
        toggleBreakpoint:toggle()
        nio.sleep(50)

        local stopped = Test.spy('stopped')

        api:onSession(function(session)
            session:onThread(function(thread)
                thread:onStopped(stopped.trigger)
            end)
        end)

        -- Start debugging
        local current_file = vim.api.nvim_buf_get_name(0)
        local workspace_info = launchJsonSupport:detectWorkspace(current_file)
        launchJsonSupport:createSessionFromConfig("Debug Loop [single-node-project]", api.manager, workspace_info)

        stopped.wait()
        nio.sleep(200)

        -- Open Neo-tree with variables
        vim.cmd("Neotree float NeodapVariables")
        nio.sleep(500)
        
        -- Debug: print window information
        local windows = vim.api.nvim_list_wins()
        print("Windows after Neo-tree command:", #windows)
        for i, win in ipairs(windows) do
            local buf = vim.api.nvim_win_get_buf(win)
            local bufname = vim.api.nvim_buf_get_name(buf)
            local filetype = vim.api.nvim_buf_get_option(buf, 'filetype')
            print(string.format("  Window %d: buf=%d, name='%s', ft='%s'", i, buf, bufname, filetype))
        end

        -- Take snapshot of initial tree (scopes only)
        Test.TerminalSnapshot('initial_scopes_view')

        -- Focus the Neo-tree window first
        local windows = vim.api.nvim_list_wins()
        local neotree_win = nil
        for _, win in ipairs(windows) do
            local buf = vim.api.nvim_win_get_buf(win)
            local filetype = vim.api.nvim_buf_get_option(buf, 'filetype')
            if filetype == 'neo-tree' then
                neotree_win = win
                break
            end
        end
        
        if neotree_win then
            vim.api.nvim_set_current_win(neotree_win)
            print("Focused Neo-tree window")
        else
            print("Neo-tree window not found!")
        end
        
        nio.sleep(100)
        
        -- Check what window we're in
        local current_buf = vim.api.nvim_get_current_buf()
        local filetype = vim.api.nvim_buf_get_option(current_buf, 'filetype')
        print("Current buffer filetype:", filetype)
        
        -- Check Neo-tree keymaps
        local keymaps = vim.api.nvim_buf_get_keymap(current_buf, 'n')
        for _, map in ipairs(keymaps) do
            if map.lhs == ' ' then
                print("Space key mapped to:", map.rhs or "function", "desc:", map.desc)
            end
        end

        -- Move to Local scope and expand with space
        vim.cmd("normal! gg")  -- Go to top
        vim.cmd("normal! j")   -- Move to first scope (Local)
        nio.sleep(100)
        
        print("About to press space to expand...")
        
        -- Test calling toggle_node directly first
        local manager = require("neo-tree.sources.manager")
        local test_state = manager.get_state("NeodapVariables")
        print("Calling toggle_node directly...")
        if test_state.commands and test_state.commands.toggle_node then
            test_state.commands.toggle_node(test_state)
        end
        
        vim.cmd("normal! \\<space>")  -- Use space to toggle/expand node
        nio.sleep(300)
        print("After pressing space")

        -- Take snapshot showing variables in Local scope
        Test.TerminalSnapshot('local_scope_expanded')

        -- Try to expand a variable if any are expandable
        vim.cmd("normal! j")  -- Move to first variable
        nio.sleep(100)
        vim.cmd("normal! \\<space>")  -- Try to expand variable
        nio.sleep(300)

        -- Take snapshot showing potential nested expansion
        Test.TerminalSnapshot('variable_nested_expansion')

        api:destroy()
    end)
end)





--[[ TERMINAL SNAPSHOT: initial_scopes_view
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

Highlights:

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree NeodapVariables               ▏
 3|  console.log("ALoop▕scope: Local                            ▏
 4|  console.log("BLoop▕scope: Closure                          ▏
 5|  console.log("CLoop▕scope: Global                           ▏
 6|  console.log("DLoop▕                                        ▏
 7| }, 1000)           ▕                                        ▏
 8| ~                  ▕                                        ▏
 9| ~                  ▕                                        ▏
10| ~                  ▕                                        ▏
11| ~                  ▕                                        ▏
12| ~                  ▕                                        ▏
13| ~                  ▕                                        ▏
14| ~                  ▕                                        ▏
15| ~                  ▕                                        ▏
16| ~                  ▕                                        ▏
17| ~                  ▕                                        ▏
18| ~                  ▕                                        ▏
19| ~                  ▕                                        ▏
20| ~                  ▕                                        ▏
21| ~                  ▕                                        ▏
22| ~                   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               1,1           All
]]









--[[ TERMINAL SNAPSHOT: local_scope_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

Highlights:

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree NeodapVariables               ▏
 3|  console.log("ALoop▕scope: Local                            ▏
 4|  console.log("BLoop▕scope: Closure                          ▏
 5|  console.log("CLoop▕scope: Global                           ▏
 6|  console.log("DLoop▕                                        ▏
 7| }, 1000)           ▕                                        ▏
 8| ~                  ▕                                        ▏
 9| ~                  ▕                                        ▏
10| ~                  ▕                                        ▏
11| ~                  ▕                                        ▏
12| ~                  ▕                                        ▏
13| ~                  ▕                                        ▏
14| ~                  ▕                                        ▏
15| ~                  ▕                                        ▏
16| ~                  ▕                                        ▏
17| ~                  ▕                                        ▏
18| ~                  ▕                                        ▏
19| ~                  ▕                                        ▏
20| ~                  ▕                                        ▏
21| ~                  ▕                                        ▏
22| ~                   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               2,1           All
]]





--[[ TERMINAL SNAPSHOT: variable_nested_expansion
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

Highlights:
  NeoTreeDirectoryIcon[1:2-1:6]
  NeoTreeRootName[1:6-1:11]
  NeoTreeDirectoryIcon[2:2-2:6]
  NeoTreeRootName[2:6-2:13]
  NeoTreeFileIcon[3:4-3:6]
  NeoTreeFileName[3:6-3:11]
  NeoTreeDirectoryIcon[4:2-4:6]
  NeoTreeRootName[4:6-4:12]

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree NeodapVariables               ▏
 3|  console.log("ALoop▕  Local                                ▏
 4|  console.log("BLoop▕  Closure                              ▏
 5|  console.log("CLoop▕   * i = 0                              ▏
 6|  console.log("DLoop▕  Global                               ▏
 7| }, 1000)           ▕                                        ▏
 8| ~                  ▕                                        ▏
 9| ~                  ▕                                        ▏
10| ~                  ▕                                        ▏
11| ~                  ▕                                        ▏
12| ~                  ▕                                        ▏
13| ~                  ▕                                        ▏
14| ~                  ▕                                        ▏
15| ~                  ▕                                        ▏
16| ~                  ▕                                        ▏
17| ~                  ▕                                        ▏
18| ~                  ▕                                        ▏
19| ~                  ▕                                        ▏
20| ~                  ▕                                        ▏
21| ~                  ▕                                        ▏
22| ~                   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               3,1           All
]]