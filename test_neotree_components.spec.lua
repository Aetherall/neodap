local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Test Neo-tree Components", function()
  Test.It("compares_filesystem_vs_our_components", function()
    local api, start = prepare()
    api:getPluginInstance(SimpleVariableTree4)
    
    local stopped = Test.spy("stopped")
    
    api:onSession(function(session)
      if session.ref.id == 1 then return end
      
      session:onThread(function(thread)
        thread:onStopped(function(event)
          stopped.trigger()
        end)
        thread:pause()
      end)
    end)
    
    -- Open test file
    vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")
    nio.sleep(100)
    
    start("loop.js")
    stopped.wait()
    nio.sleep(500)
    
    print("=== TESTING NEO-TREE COMPONENTS ===")
    
    -- Test 1: Compare filesystem vs our source  
    require('neo-tree').setup({
      sources = { 
        "filesystem",
        "neodap.plugins.SimpleVariableTree4" 
      },
      default_source = "filesystem"  -- Start with filesystem
    })
    nio.sleep(500)
    
    -- Open filesystem first to see what it looks like
    print("\\n1. Opening filesystem Neo-tree for comparison...")
    vim.cmd("Neotree float filesystem")
    nio.sleep(1000)
    
    -- Check filesystem buffer content  
    local fs_buffer_content = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
      if ft == 'neo-tree' then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, 10, false)
        fs_buffer_content = lines
        print("Filesystem Neo-tree content:")
        for i, line in ipairs(lines) do
          if i <= 10 then
            print(string.format("  %d: '%s'", i, line))
          end
        end
        break
      end
    end
    
    -- Take snapshot of filesystem
    Test.TerminalSnapshot("filesystem_comparison")
    
    -- Close filesystem
    vim.cmd("Neotree close")
    nio.sleep(500)
    
    -- Test 2: Open our variables source
    print("\\n2. Opening our variables source...")
    vim.cmd("Neotree float neodap_variables")
    nio.sleep(1000)
    
    -- Check our buffer content
    local our_buffer_content = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
      if ft == 'neo-tree' then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, 10, false)
        our_buffer_content = lines
        print("Our variables source content:")
        for i, line in ipairs(lines) do
          if i <= 10 then
            print(string.format("  %d: '%s'", i, line))
          end
        end
        break
      end
    end
    
    -- Take snapshot of our source
    Test.TerminalSnapshot("variables_comparison")
    
    -- Test 3: Check components being used
    print("\\n3. Checking components...")
    print("Filesystem components:", vim.inspect(require("neo-tree.sources.filesystem").components))
    print("Our components:", vim.inspect(SimpleVariableTree4.components))
    
    -- Test 4: Check if we can force a manual icon render
    print("\\n4. Testing manual icon rendering...")
    local utils = require("neo-tree.utils")
    local components = require("neo-tree.sources.filesystem.components")
    
    -- Create a test node like filesystem would
    local test_node = {
      id = "test_directory",
      name = "Test Directory", 
      type = "directory",
      path = "/test/path",
      loaded = false,
    }
    
    print("Test node type:", test_node.type)
    print("Is expandable:", utils.is_expandable and utils.is_expandable(test_node) or "utils.is_expandable not found")
    
    if components.icon then
      print("Icon component found")
      -- Try to render an icon for our test node
      local icon_result = components.icon({}, test_node, {})
      print("Icon result:", vim.inspect(icon_result))
    else
      print("No icon component found")
    end
    
    print("\\n*** COMPONENT COMPARISON RESULTS ***")
    print("Filesystem lines:", #fs_buffer_content)
    print("Our source lines:", #our_buffer_content)
    
    -- Compare first lines to see format differences
    if #fs_buffer_content > 0 and #our_buffer_content > 0 then
      print("Filesystem first line:", "'" .. fs_buffer_content[1] .. "'")
      print("Our source first line:", "'" .. our_buffer_content[1] .. "'")
    end
    
    api:destroy()
  end)
end)

--[[ TERMINAL SNAPSHOT: filesystem_comparison
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree Filesystem                    ▏
 3|  console.log("ALoop▕  ~/workspace/github/neodap            ▏
 4|  console.log("BLoop▕    bin                                ▏
 5|  console.log("CLoop▕    docs                               ▏
 6|  console.log("DLoop▕    examples                           ▏
 7| }, 1000)           ▕    lua                               ▏
 8| ~                  ▕    spec                               ▏
 9| ~                  ▕    CLAUDE.md                          ▏
10| ~                  ▕    Makefile                           ▏
11| ~                  ▕   󰂺 README.md                          ▏
12| ~                  ▕    architectural_comparison.md       ▏
13| ~                  ▕    crash_test.lua                     ▏
14| ~                  ▕    debug_expansion.lua                ▏
15| ~                  ▕    debug_get_items.spec.lua          ▏
16| ~                  ▕    debug_real_expansion.spec.lua      ▏
17| ~                  ▕    debug_tree_rendering.spec.lua     ▏
18| ~                  ▕    flake.lock                         ▏
19| ~                  ▕    flake.nix                          ▏
20| ~                  ▕    test_authentic_4_level.spec.lua    ▏
21| ~                  ▕    test_expansion.lua                 ▏
22| ~                   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
23| spec/fixtures/workspaces/single-node-project/loop.js          1,1            All
24|                                                               1,1           Top
]]

--[[ TERMINAL SNAPSHOT: variables_comparison
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree Neodap_variables              ▏
 3|  console.log("ALoop▕  Local                                ▏
 4|  console.log("BLoop▕  Closure                              ▏
 5|  console.log("CLoop▕  Global                               ▏
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
23| spec/fixtures/workspaces/single-node-project/loop.js          1,1            All
24|                                                               1,1           All
]]