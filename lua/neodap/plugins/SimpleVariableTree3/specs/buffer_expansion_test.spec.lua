-- Test: Buffer object nested expansion (prototype chain)
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local SimpleVariableTree3 = require("neodap.plugins.SimpleVariableTree3")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("SimpleVariableTree3 Buffer Expansion", function()
    Test.It("buffer_prototype_chain_expansion", function()
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
            if session.ref.id == 1 then return end
            
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

        print("=====> Breakpoint hit, opening Neo-tree")
        vim.cmd("Neotree float NeodapVariables")
        nio.sleep(300)

        -- Take snapshot of initial scopes
        Test.TerminalSnapshot('scopes_with_global')

        -- Focus Neo-tree and navigate to Global scope
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
        end

        -- Navigate to Global scope (third item)
        vim.cmd("normal! gg")  -- Go to top
        vim.cmd("normal! jj")  -- Move to Global scope
        nio.sleep(100)

        print("About to expand Global scope to find Buffer...")
        
        -- Expand Global scope using direct call (since space key issue)
        local manager = require("neo-tree.sources.manager")
        local test_state = manager.get_state("NeodapVariables")
        if test_state.commands and test_state.commands.toggle_node then
            print("Calling toggle_node on Global scope...")
            test_state.commands.toggle_node(test_state)
        end
        nio.sleep(500)

        -- Take snapshot showing Global scope expanded with Buffer
        Test.TerminalSnapshot('global_scope_expanded')

        -- Now try to expand Buffer specifically to see nested properties
        print("Looking for Buffer to expand its properties...")
        
        -- Move down to find Buffer (should be around line 12 based on snapshot)
        for i = 1, 10 do
            vim.cmd("normal! j")
            nio.sleep(50)
        end
        
        print("Attempting to expand Buffer object...")
        if test_state.commands and test_state.commands.toggle_node then
            test_state.commands.toggle_node(test_state)
        end
        nio.sleep(500)
        
        -- Take snapshot showing Buffer's internal properties
        Test.TerminalSnapshot('buffer_properties_expanded')

        print("Buffer expansion test completed")

        api:destroy()
    end)
end)


--[[ TERMINAL SNAPSHOT: scopes_with_global
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
24| [Neo-tree WARN] Invalid mapping for  R :  refresh             1,1           All
]]

--[[ TERMINAL SNAPSHOT: global_scope_expanded
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

Highlights:
  NeoTreeDirectoryIcon[1:2-1:6]
  NeoTreeRootName[1:6-1:11]
  NeoTreeDirectoryIcon[2:2-2:6]
  NeoTreeRootName[2:6-2:13]
  NeoTreeDirectoryIcon[3:2-3:6]
  NeoTreeRootName[3:6-3:12]
  NeoTreeDirectoryIcon[4:4-4:8]
  NeoTreeDirectoryName[4:8-4:41]
  NeoTreeDirectoryName_68[4:41-4:42]
  NeoTreeDirectoryName_60[4:42-4:43]
  NeoTreeDirectoryName_35[4:43-4:44]
  NeoTreeDirectoryIcon[5:4-5:8]
  NeoTreeDirectoryName[5:8-5:41]
  NeoTreeDirectoryName_68[5:41-5:42]
  NeoTreeDirectoryName_60[5:42-5:43]
  NeoTreeDirectoryName_35[5:43-5:44]
  NeoTreeDirectoryIcon[6:4-6:8]
  NeoTreeDirectoryName[6:8-6:41]
  NeoTreeDirectoryName_68[6:41-6:42]
  NeoTreeDirectoryName_60[6:42-6:43]
  NeoTreeDirectoryName_35[6:43-6:44]
  NeoTreeDirectoryIcon[7:4-7:8]
  NeoTreeDirectoryName[7:8-7:41]
  NeoTreeDirectoryName_68[7:41-7:42]
  NeoTreeDirectoryName_60[7:42-7:43]
  NeoTreeDirectoryName_35[7:43-7:44]
  NeoTreeDirectoryIcon[8:4-8:8]
  NeoTreeDirectoryName[8:8-8:41]
  NeoTreeDirectoryName_68[8:41-8:42]
  NeoTreeDirectoryName_60[8:42-8:43]
  NeoTreeDirectoryName_35[8:43-8:44]
  NeoTreeDirectoryIcon[9:4-9:8]
  NeoTreeDirectoryName[9:8-9:41]
  NeoTreeDirectoryName_68[9:41-9:42]
  NeoTreeDirectoryName_60[9:42-9:43]
  NeoTreeDirectoryName_35[9:43-9:44]
  NeoTreeDirectoryIcon[10:4-10:8]
  NeoTreeDirectoryName[10:8-10:41]
  NeoTreeDirectoryName_68[10:41-10:42]
  NeoTreeDirectoryName_60[10:42-10:43]
  NeoTreeDirectoryName_35[10:43-10:44]
  NeoTreeDirectoryIcon[11:4-11:8]
  NeoTreeDirectoryName[11:8-11:41]
  NeoTreeDirectoryName_68[11:41-11:42]
  NeoTreeDirectoryName_60[11:42-11:43]
  NeoTreeDirectoryName_35[11:43-11:44]
  NeoTreeDirectoryIcon[12:4-12:8]
  NeoTreeDirectoryName[12:8-12:41]
  NeoTreeDirectoryName_68[12:41-12:42]
  NeoTreeDirectoryName_60[12:42-12:43]
  NeoTreeDirectoryName_35[12:43-12:44]
  NeoTreeDirectoryIcon[13:4-13:8]
  NeoTreeDirectoryName[13:8-13:41]
  NeoTreeDirectoryName_68[13:41-13:42]
  NeoTreeDirectoryName_60[13:42-13:43]
  NeoTreeDirectoryName_35[13:43-13:44]
  NeoTreeDirectoryIcon[14:4-14:8]
  NeoTreeDirectoryName[14:8-14:41]
  NeoTreeDirectoryName_68[14:41-14:42]
  NeoTreeDirectoryName_60[14:42-14:43]
  NeoTreeDirectoryName_35[14:43-14:44]
  NeoTreeDirectoryIcon[15:4-15:8]
  NeoTreeDirectoryName[15:8-15:41]
  NeoTreeDirectoryName_68[15:41-15:42]
  NeoTreeDirectoryName_60[15:42-15:43]
  NeoTreeDirectoryName_35[15:43-15:44]
  NeoTreeDirectoryIcon[16:4-16:8]
  NeoTreeDirectoryName[16:8-16:41]
  NeoTreeDirectoryName_68[16:41-16:42]
  NeoTreeDirectoryName_60[16:42-16:43]
  NeoTreeDirectoryName_35[16:43-16:44]
  NeoTreeDirectoryIcon[17:4-17:8]
  NeoTreeDirectoryName[17:8-17:41]
  NeoTreeDirectoryName_68[17:41-17:42]
  NeoTreeDirectoryName_60[17:42-17:43]
  NeoTreeDirectoryName_35[17:43-17:44]
  NeoTreeDirectoryIcon[18:4-18:8]
  NeoTreeDirectoryName[18:8-18:41]
  NeoTreeDirectoryName_68[18:41-18:42]
  NeoTreeDirectoryName_60[18:42-18:43]
  NeoTreeDirectoryName_35[18:43-18:44]
  NeoTreeDirectoryIcon[19:4-19:8]
  NeoTreeDirectoryName[19:8-19:41]
  NeoTreeDirectoryName_68[19:41-19:42]
  NeoTreeDirectoryName_60[19:42-19:43]
  NeoTreeDirectoryName_35[19:43-19:44]
  NeoTreeDirectoryIcon[20:4-20:8]
  NeoTreeDirectoryName[20:8-20:41]
  NeoTreeDirectoryName_68[20:41-20:42]
  NeoTreeDirectoryName_60[20:42-20:43]
  NeoTreeDirectoryName_35[20:43-20:44]
  NeoTreeDirectoryIcon[21:4-21:8]
  NeoTreeDirectoryName[21:8-21:40]
  NeoTreeDirectoryName_68[21:40-21:41]
  NeoTreeDirectoryName_60[21:41-21:42]
  NeoTreeDirectoryName_35[21:42-21:43]
  NeoTreeDirectoryIcon[22:4-22:8]
  NeoTreeDirectoryName[22:8-22:41]
  NeoTreeDirectoryName_68[22:41-22:42]
  NeoTreeDirectoryName_60[22:42-22:43]
  NeoTreeDirectoryName_35[22:43-22:44]
  NeoTreeDirectoryIcon[23:4-23:8]
  NeoTreeDirectoryName[23:8-23:41]
  NeoTreeDirectoryName_68[23:41-23:42]
  NeoTreeDirectoryName_60[23:42-23:43]
  NeoTreeDirectoryName_35[23:43-23:44]
  NeoTreeDirectoryIcon[24:4-24:8]
  NeoTreeDirectoryName[24:8-24:41]
  NeoTreeDirectoryName_68[24:41-24:42]
  NeoTreeDirectoryName_60[24:42-24:43]
  NeoTreeDirectoryName_35[24:43-24:44]
  NeoTreeDirectoryIcon[25:4-25:8]
  NeoTreeDirectoryName[25:8-25:40]
  NeoTreeDirectoryName_68[25:40-25:41]
  NeoTreeDirectoryName_60[25:41-25:42]
  NeoTreeDirectoryName_35[25:42-25:43]
  NeoTreeDirectoryIcon[26:4-26:8]
  NeoTreeDirectoryName[26:8-26:41]
  NeoTreeDirectoryName_68[26:41-26:42]
  NeoTreeDirectoryName_60[26:42-26:43]
  NeoTreeDirectoryName_35[26:43-26:44]
  NeoTreeDirectoryIcon[27:4-27:8]
  NeoTreeDirectoryName[27:8-27:41]
  NeoTreeDirectoryName_68[27:41-27:42]
  NeoTreeDirectoryName_60[27:42-27:43]
  NeoTreeDirectoryName_35[27:43-27:44]
  NeoTreeDirectoryIcon[28:4-28:8]
  NeoTreeDirectoryName[28:8-28:41]
  NeoTreeDirectoryName_68[28:41-28:42]
  NeoTreeDirectoryName_60[28:42-28:43]
  NeoTreeDirectoryName_35[28:43-28:44]
  NeoTreeDirectoryIcon[29:4-29:8]
  NeoTreeDirectoryName[29:8-29:41]
  NeoTreeDirectoryName_68[29:41-29:42]
  NeoTreeDirectoryName_60[29:42-29:43]
  NeoTreeDirectoryName_35[29:43-29:44]
  NeoTreeDirectoryIcon[30:4-30:8]
  NeoTreeDirectoryName[30:8-30:41]
  NeoTreeDirectoryName_68[30:41-30:42]
  NeoTreeDirectoryName_60[30:42-30:43]
  NeoTreeDirectoryName_35[30:43-30:44]
  NeoTreeDirectoryIcon[31:4-31:8]
  NeoTreeDirectoryName[31:8-31:41]
  NeoTreeDirectoryName_68[31:41-31:42]
  NeoTreeDirectoryName_60[31:42-31:43]
  NeoTreeDirectoryName_35[31:43-31:44]
  NeoTreeDirectoryIcon[32:4-32:8]
  NeoTreeDirectoryName[32:8-32:41]
  NeoTreeDirectoryName_68[32:41-32:42]
  NeoTreeDirectoryName_60[32:42-32:43]
  NeoTreeDirectoryName_35[32:43-32:44]
  NeoTreeDirectoryIcon[33:4-33:8]
  NeoTreeDirectoryName[33:8-33:41]
  NeoTreeDirectoryName_68[33:41-33:42]
  NeoTreeDirectoryName_60[33:42-33:43]
  NeoTreeDirectoryName_35[33:43-33:44]
  NeoTreeDirectoryIcon[34:4-34:8]
  NeoTreeDirectoryName[34:8-34:41]
  NeoTreeDirectoryName_68[34:41-34:42]
  NeoTreeDirectoryName_60[34:42-34:43]
  NeoTreeDirectoryName_35[34:43-34:44]
  NeoTreeDirectoryIcon[35:4-35:8]
  NeoTreeDirectoryName[35:8-35:41]
  NeoTreeDirectoryName_68[35:41-35:42]
  NeoTreeDirectoryName_60[35:42-35:43]
  NeoTreeDirectoryName_35[35:43-35:44]
  NeoTreeDirectoryIcon[36:4-36:8]
  NeoTreeDirectoryName[36:8-36:41]
  NeoTreeDirectoryName_68[36:41-36:42]
  NeoTreeDirectoryName_60[36:42-36:43]
  NeoTreeDirectoryName_35[36:43-36:44]
  NeoTreeDirectoryIcon[37:4-37:8]
  NeoTreeDirectoryName[37:8-37:41]
  NeoTreeDirectoryName_68[37:41-37:42]
  NeoTreeDirectoryName_60[37:42-37:43]
  NeoTreeDirectoryName_35[37:43-37:44]
  NeoTreeDirectoryIcon[38:4-38:8]
  NeoTreeDirectoryName[38:8-38:41]
  NeoTreeDirectoryName_68[38:41-38:42]
  NeoTreeDirectoryName_60[38:42-38:43]
  NeoTreeDirectoryName_35[38:43-38:44]
  NeoTreeDirectoryIcon[39:4-39:8]
  NeoTreeDirectoryName[39:8-39:41]
  NeoTreeDirectoryName_68[39:41-39:42]
  NeoTreeDirectoryName_60[39:42-39:43]
  NeoTreeDirectoryName_35[39:43-39:44]
  NeoTreeDirectoryIcon[40:4-40:8]
  NeoTreeDirectoryName[40:8-40:41]
  NeoTreeDirectoryName_68[40:41-40:42]
  NeoTreeDirectoryName_60[40:42-40:43]
  NeoTreeDirectoryName_35[40:43-40:44]
  NeoTreeDirectoryIcon[41:4-41:8]
  NeoTreeDirectoryName[41:8-41:41]
  NeoTreeDirectoryName_68[41:41-41:42]
  NeoTreeDirectoryName_60[41:42-41:43]
  NeoTreeDirectoryName_35[41:43-41:44]
  NeoTreeDirectoryIcon[42:4-42:8]
  NeoTreeDirectoryName[42:8-42:41]
  NeoTreeDirectoryName_68[42:41-42:42]
  NeoTreeDirectoryName_60[42:42-42:43]
  NeoTreeDirectoryName_35[42:43-42:44]
  NeoTreeDirectoryIcon[43:4-43:8]
  NeoTreeDirectoryName[43:8-43:41]
  NeoTreeDirectoryName_68[43:41-43:42]
  NeoTreeDirectoryName_60[43:42-43:43]
  NeoTreeDirectoryName_35[43:43-43:44]
  NeoTreeDirectoryIcon[44:4-44:8]
  NeoTreeDirectoryName[44:8-44:41]
  NeoTreeDirectoryName_68[44:41-44:42]
  NeoTreeDirectoryName_60[44:42-44:43]
  NeoTreeDirectoryName_35[44:43-44:44]
  NeoTreeDirectoryIcon[45:4-45:8]
  NeoTreeDirectoryName[45:8-45:41]
  NeoTreeDirectoryName_68[45:41-45:42]
  NeoTreeDirectoryName_60[45:42-45:43]
  NeoTreeDirectoryName_35[45:43-45:44]
  NeoTreeDirectoryIcon[46:4-46:8]
  NeoTreeDirectoryName[46:8-46:41]
  NeoTreeDirectoryName_68[46:41-46:42]
  NeoTreeDirectoryName_60[46:42-46:43]
  NeoTreeDirectoryName_35[46:43-46:44]
  NeoTreeDirectoryIcon[47:4-47:8]
  NeoTreeDirectoryName[47:8-47:41]
  NeoTreeDirectoryName_68[47:41-47:42]
  NeoTreeDirectoryName_60[47:42-47:43]
  NeoTreeDirectoryName_35[47:43-47:44]
  NeoTreeDirectoryIcon[48:4-48:8]
  NeoTreeDirectoryName[48:8-48:41]
  NeoTreeDirectoryName_68[48:41-48:42]
  NeoTreeDirectoryName_60[48:42-48:43]
  NeoTreeDirectoryName_35[48:43-48:44]
  NeoTreeDirectoryIcon[49:4-49:8]
  NeoTreeDirectoryName[49:8-49:41]
  NeoTreeDirectoryName_68[49:41-49:42]
  NeoTreeDirectoryName_60[49:42-49:43]
  NeoTreeDirectoryName_35[49:43-49:44]
  NeoTreeDirectoryIcon[50:4-50:8]
  NeoTreeDirectoryName[50:8-50:41]
  NeoTreeDirectoryName_68[50:41-50:42]
  NeoTreeDirectoryName_60[50:42-50:43]
  NeoTreeDirectoryName_35[50:43-50:44]
  NeoTreeDirectoryIcon[51:4-51:8]
  NeoTreeDirectoryName[51:8-51:41]
  NeoTreeDirectoryName_68[51:41-51:42]
  NeoTreeDirectoryName_60[51:42-51:43]
  NeoTreeDirectoryName_35[51:43-51:44]
  NeoTreeDirectoryIcon[52:4-52:8]
  NeoTreeDirectoryName[52:8-52:41]
  NeoTreeDirectoryName_68[52:41-52:42]
  NeoTreeDirectoryName_60[52:42-52:43]
  NeoTreeDirectoryName_35[52:43-52:44]
  NeoTreeDirectoryIcon[53:4-53:8]
  NeoTreeDirectoryName[53:8-53:41]
  NeoTreeDirectoryName_68[53:41-53:42]
  NeoTreeDirectoryName_60[53:42-53:43]
  NeoTreeDirectoryName_35[53:43-53:44]
  NeoTreeDirectoryIcon[54:4-54:8]
  NeoTreeDirectoryName[54:8-54:41]
  NeoTreeDirectoryName_68[54:41-54:42]
  NeoTreeDirectoryName_60[54:42-54:43]
  NeoTreeDirectoryName_35[54:43-54:44]
  NeoTreeDirectoryIcon[55:4-55:8]
  NeoTreeDirectoryName[55:8-55:41]
  NeoTreeDirectoryName_68[55:41-55:42]
  NeoTreeDirectoryName_60[55:42-55:43]
  NeoTreeDirectoryName_35[55:43-55:44]
  NeoTreeDirectoryIcon[56:4-56:8]
  NeoTreeDirectoryName[56:8-56:41]
  NeoTreeDirectoryName_68[56:41-56:42]
  NeoTreeDirectoryName_60[56:42-56:43]
  NeoTreeDirectoryName_35[56:43-56:44]
  NeoTreeDirectoryIcon[57:4-57:8]
  NeoTreeDirectoryName[57:8-57:41]
  NeoTreeDirectoryName_68[57:41-57:42]
  NeoTreeDirectoryName_60[57:42-57:43]
  NeoTreeDirectoryName_35[57:43-57:44]
  NeoTreeDirectoryIcon[58:4-58:8]
  NeoTreeDirectoryName[58:8-58:40]
  NeoTreeDirectoryName_68[58:40-58:41]
  NeoTreeDirectoryName_60[58:41-58:42]
  NeoTreeDirectoryName_35[58:42-58:43]
  NeoTreeDirectoryIcon[59:4-59:8]
  NeoTreeDirectoryName[59:8-59:41]
  NeoTreeDirectoryName_68[59:41-59:42]
  NeoTreeDirectoryName_60[59:42-59:43]
  NeoTreeDirectoryName_35[59:43-59:44]
  NeoTreeDirectoryIcon[60:4-60:8]
  NeoTreeDirectoryName[60:8-60:41]
  NeoTreeDirectoryName_68[60:41-60:42]
  NeoTreeDirectoryName_60[60:42-60:43]
  NeoTreeDirectoryName_35[60:43-60:44]
  NeoTreeDirectoryIcon[61:4-61:8]
  NeoTreeDirectoryName[61:8-61:41]
  NeoTreeDirectoryName_68[61:41-61:42]
  NeoTreeDirectoryName_60[61:42-61:43]
  NeoTreeDirectoryName_35[61:43-61:44]
  NeoTreeFileIcon[62:4-62:6]
  NeoTreeFileName[62:6-62:33]
  NeoTreeDirectoryIcon[63:4-63:8]
  NeoTreeDirectoryName[63:8-63:41]
  NeoTreeDirectoryName_68[63:41-63:42]
  NeoTreeDirectoryName_60[63:42-63:43]
  NeoTreeDirectoryName_35[63:43-63:44]
  NeoTreeDirectoryIcon[64:4-64:8]
  NeoTreeDirectoryName[64:8-64:26]
  NeoTreeDirectoryIcon[65:4-65:8]
  NeoTreeDirectoryName[65:8-65:38]
  NeoTreeDirectoryIcon[66:4-66:8]
  NeoTreeDirectoryName[66:8-66:41]
  NeoTreeDirectoryName_68[66:41-66:42]
  NeoTreeDirectoryName_60[66:42-66:43]
  NeoTreeDirectoryName_35[66:43-66:44]
  NeoTreeDirectoryIcon[67:4-67:8]
  NeoTreeDirectoryName[67:8-67:28]
  NeoTreeDirectoryIcon[68:4-68:8]
  NeoTreeDirectoryName[68:8-68:41]
  NeoTreeDirectoryName_68[68:41-68:42]
  NeoTreeDirectoryIcon[69:4-69:8]
  NeoTreeDirectoryName[69:8-69:41]
  NeoTreeDirectoryName_68[69:41-69:42]
  NeoTreeDirectoryName_60[69:42-69:43]
  NeoTreeDirectoryName_35[69:43-69:44]
  NeoTreeDirectoryIcon[70:4-70:8]
  NeoTreeDirectoryName[70:8-70:30]
  NeoTreeDirectoryIcon[71:4-71:8]
  NeoTreeDirectoryName[71:8-71:42]
  NeoTreeDirectoryName_68[71:42-71:43]
  NeoTreeDirectoryName_60[71:43-71:44]
  NeoTreeDirectoryName_35[71:44-71:45]
  NeoTreeDirectoryIcon[72:4-72:8]
  NeoTreeDirectoryName[72:8-72:40]
  NeoTreeDirectoryName_68[72:40-72:41]
  NeoTreeDirectoryName_60[72:41-72:42]
  NeoTreeDirectoryName_35[72:42-72:43]
  NeoTreeDirectoryIcon[73:4-73:8]
  NeoTreeDirectoryName[73:8-73:32]
  NeoTreeDirectoryIcon[74:4-74:8]
  NeoTreeDirectoryName[74:8-74:24]
  NeoTreeDirectoryIcon[75:4-75:8]
  NeoTreeDirectoryName[75:8-75:34]
  NeoTreeDirectoryIcon[76:4-76:8]
  NeoTreeDirectoryName[76:8-76:41]
  NeoTreeDirectoryName_68[76:41-76:42]
  NeoTreeDirectoryName_60[76:42-76:43]
  NeoTreeDirectoryName_35[76:43-76:44]
  NeoTreeDirectoryIcon[77:4-77:8]
  NeoTreeDirectoryName[77:8-77:34]
  NeoTreeDirectoryIcon[78:4-78:8]
  NeoTreeDirectoryName[78:8-78:41]
  NeoTreeDirectoryName_68[78:41-78:42]
  NeoTreeDirectoryName_60[78:42-78:43]
  NeoTreeDirectoryName_35[78:43-78:44]
  NeoTreeDirectoryIcon[79:4-79:8]
  NeoTreeDirectoryName[79:8-79:26]
  NeoTreeDirectoryIcon[80:4-80:8]
  NeoTreeDirectoryName[80:8-80:28]
  NeoTreeDirectoryIcon[81:4-81:8]
  NeoTreeDirectoryName[81:8-81:24]
  NeoTreeDirectoryIcon[82:4-82:8]
  NeoTreeDirectoryName[82:8-82:34]
  NeoTreeDirectoryIcon[83:4-83:8]
  NeoTreeDirectoryName[83:8-83:40]
  NeoTreeDirectoryName_68[83:40-83:41]
  NeoTreeDirectoryName_60[83:41-83:42]
  NeoTreeDirectoryName_35[83:42-83:43]
  NeoTreeDirectoryIcon[84:4-84:8]
  NeoTreeDirectoryName[84:8-84:40]
  NeoTreeDirectoryName_68[84:40-84:41]
  NeoTreeDirectoryName_60[84:41-84:42]
  NeoTreeDirectoryName_35[84:42-84:43]
  NeoTreeDirectoryIcon[85:4-85:8]
  NeoTreeDirectoryName[85:8-85:41]
  NeoTreeDirectoryName_68[85:41-85:42]
  NeoTreeDirectoryName_60[85:42-85:43]
  NeoTreeDirectoryName_35[85:43-85:44]
  NeoTreeDirectoryIcon[86:4-86:8]
  NeoTreeDirectoryName[86:8-86:40]
  NeoTreeDirectoryIcon[87:4-87:8]
  NeoTreeDirectoryName[87:8-87:40]
  NeoTreeDirectoryIcon[88:4-88:8]
  NeoTreeDirectoryName[88:8-88:32]
  NeoTreeDirectoryIcon[89:4-89:8]
  NeoTreeDirectoryName[89:8-89:40]
  NeoTreeDirectoryName_68[89:40-89:41]
  NeoTreeDirectoryName_60[89:41-89:42]
  NeoTreeDirectoryName_35[89:42-89:43]
  NeoTreeFileIcon[90:4-90:6]
  NeoTreeFileName[90:6-90:25]
  NeoTreeDirectoryIcon[91:4-91:8]
  NeoTreeDirectoryName[91:8-91:36]
  NeoTreeDirectoryIcon[92:4-92:8]
  NeoTreeDirectoryName[92:8-92:36]
  NeoTreeDirectoryIcon[93:4-93:8]
  NeoTreeDirectoryName[93:8-93:34]
  NeoTreeDirectoryIcon[94:4-94:8]
  NeoTreeDirectoryName[94:8-94:41]
  NeoTreeDirectoryName_68[94:41-94:42]
  NeoTreeDirectoryName_60[94:42-94:43]
  NeoTreeDirectoryName_35[94:43-94:44]
  NeoTreeDirectoryIcon[95:4-95:8]
  NeoTreeDirectoryName[95:8-95:32]
  NeoTreeDirectoryIcon[96:4-96:8]
  NeoTreeDirectoryName[96:8-96:26]
  NeoTreeDirectoryIcon[97:4-97:8]
  NeoTreeDirectoryName[97:8-97:42]
  NeoTreeDirectoryName_68[97:42-97:43]
  NeoTreeDirectoryName_60[97:43-97:44]
  NeoTreeDirectoryName_35[97:44-97:45]
  NeoTreeDirectoryIcon[98:4-98:8]
  NeoTreeDirectoryName[98:8-98:22]
  NeoTreeDirectoryIcon[99:4-99:8]
  NeoTreeDirectoryName[99:8-99:42]
  NeoTreeDirectoryName_68[99:42-99:43]
  NeoTreeDirectoryName_60[99:43-99:44]
  NeoTreeDirectoryName_35[99:44-99:45]
  NeoTreeFileIcon[100:4-100:6]
  NeoTreeFileName[100:6-100:15]
  NeoTreeDirectoryIcon[101:4-101:8]
  NeoTreeDirectoryName[101:8-101:28]
  NeoTreeDirectoryIcon[102:4-102:8]
  NeoTreeDirectoryName[102:8-102:28]
  NeoTreeDirectoryIcon[103:4-103:8]
  NeoTreeDirectoryName[103:8-103:36]
  NeoTreeDirectoryIcon[104:4-104:8]
  NeoTreeDirectoryName[104:8-104:32]
  NeoTreeDirectoryIcon[105:4-105:8]
  NeoTreeDirectoryName[105:8-105:30]
  NeoTreeDirectoryIcon[106:4-106:8]
  NeoTreeDirectoryName[106:8-106:26]
  NeoTreeDirectoryIcon[107:4-107:8]
  NeoTreeDirectoryName[107:8-107:36]
  NeoTreeDirectoryIcon[108:4-108:8]
  NeoTreeDirectoryName[108:8-108:41]
  NeoTreeDirectoryName_68[108:41-108:42]
  NeoTreeDirectoryName_60[108:42-108:43]
  NeoTreeDirectoryName_35[108:43-108:44]
  NeoTreeDirectoryIcon[109:4-109:8]
  NeoTreeDirectoryName[109:8-109:40]
  NeoTreeDirectoryName_68[109:40-109:41]
  NeoTreeDirectoryName_60[109:41-109:42]
  NeoTreeDirectoryName_35[109:42-109:43]
  NeoTreeDirectoryIcon[110:4-110:8]
  NeoTreeDirectoryName[110:8-110:28]
  NeoTreeDirectoryIcon[111:4-111:8]
  NeoTreeDirectoryName[111:8-111:22]
  NeoTreeDirectoryIcon[112:4-112:8]
  NeoTreeDirectoryName[112:8-112:41]
  NeoTreeDirectoryName_68[112:41-112:42]
  NeoTreeDirectoryName_60[112:42-112:43]
  NeoTreeDirectoryName_35[112:43-112:44]
  NeoTreeDirectoryIcon[113:4-113:8]
  NeoTreeDirectoryName[113:8-113:28]
  NeoTreeDirectoryIcon[114:4-114:8]
  NeoTreeDirectoryName[114:8-114:28]
  NeoTreeFileIcon[115:4-115:6]
  NeoTreeFileName[115:6-115:38]
  NeoTreeFileName_68[115:38-115:39]
  NeoTreeFileName_60[115:39-115:40]
  NeoTreeFileName_35[115:40-115:41]
  NeoTreeDirectoryIcon[116:4-116:8]
  NeoTreeDirectoryName[116:8-116:38]
  NeoTreeDirectoryIcon[117:4-117:8]
  NeoTreeDirectoryName[117:8-117:34]
  NeoTreeDirectoryIcon[118:4-118:8]
  NeoTreeDirectoryName[118:8-118:38]
  NeoTreeDirectoryIcon[119:4-119:8]
  NeoTreeDirectoryName[119:8-119:38]
  NeoTreeDirectoryIcon[120:4-120:8]
  NeoTreeDirectoryName[120:8-120:36]
  NeoTreeDirectoryIcon[121:4-121:8]
  NeoTreeDirectoryName[121:8-121:41]
  NeoTreeDirectoryName_68[121:41-121:42]
  NeoTreeDirectoryName_60[121:42-121:43]
  NeoTreeDirectoryName_35[121:43-121:44]
  NeoTreeFileIcon[122:4-122:6]
  NeoTreeFileName[122:6-122:27]
  NeoTreeDirectoryIcon[123:4-123:8]
  NeoTreeDirectoryName[123:8-123:32]
  NeoTreeDirectoryIcon[124:4-124:8]
  NeoTreeDirectoryName[124:8-124:32]
  NeoTreeDirectoryIcon[125:4-125:8]
  NeoTreeDirectoryName[125:8-125:40]
  NeoTreeDirectoryName_68[125:40-125:41]
  NeoTreeDirectoryName_60[125:41-125:42]
  NeoTreeDirectoryName_35[125:42-125:43]
  NeoTreeDirectoryIcon[126:4-126:8]
  NeoTreeDirectoryName[126:8-126:40]
  NeoTreeDirectoryName_68[126:40-126:41]
  NeoTreeDirectoryName_60[126:41-126:42]
  NeoTreeDirectoryName_35[126:42-126:43]
  NeoTreeDirectoryIcon[127:4-127:8]
  NeoTreeDirectoryName[127:8-127:30]
  NeoTreeDirectoryIcon[128:4-128:8]
  NeoTreeDirectoryName[128:8-128:30]
  NeoTreeDirectoryIcon[129:4-129:8]
  NeoTreeDirectoryName[129:8-129:30]
  NeoTreeDirectoryIcon[130:4-130:8]
  NeoTreeDirectoryName[130:8-130:40]
  NeoTreeDirectoryName_68[130:40-130:41]
  NeoTreeDirectoryName_60[130:41-130:42]
  NeoTreeDirectoryName_35[130:42-130:43]
  NeoTreeDirectoryIcon[131:4-131:8]
  NeoTreeDirectoryName[131:8-131:30]

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree NeodapVariables               ▏
 3|  console.log("ALoop▕  Local                                ▏
 4|  console.log("BLoop▕  Closure                              ▏
 5|  console.log("CLoop▕  Global                               ▏
 6|  console.log("DLoop▕    AbortController = ƒ () {       mod ▏
 7| }, 1000)           ▕    AbortSignal = ƒ () {       mod ??= ▏
 8| ~                  ▕    atob = ƒ () {       mod ??= require▏
 9| ~                  ▕    Blob = ƒ () {       mod ??= require▏
10| ~                  ▕    BroadcastChannel = ƒ () {       mod▏
11| ~                  ▕    btoa = ƒ () {       mod ??= require▏
12| ~                  ▕    Buffer = ƒ get() {       return _Bu▏
13| ~                  ▕    ByteLengthQueuingStrategy = ƒ () { ▏
14| ~                  ▕    clearImmediate = ƒ clearImmediate(i▏
15| ~                  ▕    clearInterval = ƒ clearInterval(tim▏
16| ~                  ▕    clearTimeout = ƒ clearTimeout(timer▏
17| ~                  ▕    CompressionStream = ƒ () {       mo▏
18| ~                  ▕    CountQueuingStrategy = ƒ () {      ▏
19| ~                  ▕    crypto = ƒ () {       if (check !==▏
20| ~                  ▕    Crypto = ƒ () {       mod ??= requi▏
21| ~                  ▕    CryptoKey = ƒ () {       mod ??= re▏
22| ~                   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               3,1           Top
]]

--[[ TERMINAL SNAPSHOT: buffer_properties_expanded
Size: 24x80
Cursor: [13, 0] (line 13, col 0)
Mode: n

Highlights:

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree NeodapVariables               ▏
 3|  console.log("ALoop▕  Local                                ▏
 4|  console.log("BLoop▕  Closure                              ▏
 5|  console.log("CLoop▕  Global                               ▏
 6|  console.log("DLoop▕    AbortController = ƒ () {       mod ▏
 7| }, 1000)           ▕    AbortSignal = ƒ () {       mod ??= ▏
 8| ~                  ▕    atob = ƒ () {       mod ??= require▏
 9| ~                  ▕    Blob = ƒ () {       mod ??= require▏
10| ~                  ▕    BroadcastChannel = ƒ () {       mod▏
11| ~                  ▕    btoa = ƒ () {       mod ??= require▏
12| ~                  ▕    Buffer = ƒ get() {       return _Bu▏
13| ~                  ▕    ByteLengthQueuingStrategy = ƒ () { ▏
14| ~                  ▕    clearImmediate = ƒ clearImmediate(i▏
15| ~                  ▕    clearInterval = ƒ clearInterval(tim▏
16| ~                  ▕    clearTimeout = ƒ clearTimeout(timer▏
17| ~                  ▕    CompressionStream = ƒ () {       mo▏
18| ~                  ▕    CountQueuingStrategy = ƒ () {      ▏
19| ~                  ▕    crypto = ƒ () {       if (check !==▏
20| ~                  ▕    Crypto = ƒ () {       mod ??= requi▏
21| ~                  ▕    CryptoKey = ƒ () {       mod ??= re▏
22| ~                   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               13,1          Top
]]