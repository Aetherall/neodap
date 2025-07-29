-- DebugTree Interactive Navigation Test
-- Tests that DebugTreeFrame supports Variables4-level interactivity

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up debugging session with complex state
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j")
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables")
  T.sleep(1500) -- Wait for session to start and hit breakpoint
  
  -- Test 1: Open DebugTreeFrame and verify initial state
  T.TerminalSnapshot('before_interactive_test')
  
  T.cmd("DebugTreeFrame")
  T.sleep(500)
  T.TerminalSnapshot('debugtree_frame_collapsed')
  
  -- Test 2: Try to expand a scope with Enter key
  T.cmd("normal! j") -- Move to first scope (Local: testVariables)
  T.cmd("execute \"normal \\<CR>\"") -- Press Enter to expand
  T.sleep(800) -- Wait for async expansion
  T.TerminalSnapshot('debugtree_scope_expanded')
  
  -- Test 3: Navigate with hjkl keys
  T.cmd("normal! j") -- Move down to first variable
  T.sleep(200)
  T.TerminalSnapshot('debugtree_navigate_down')
  
  T.cmd("normal! k") -- Move back up
  T.sleep(200)
  T.TerminalSnapshot('debugtree_navigate_up')
  
  -- Test 4: Try focus mode
  T.cmd("normal! f") -- Focus on current scope
  T.sleep(300)
  T.TerminalSnapshot('debugtree_focus_mode')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('debugtree_interactive_cleanup')
end)





--[[ TERMINAL SNAPSHOT: before_interactive_test
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| function testVariables() {
 4|     // Primitive types
 5|     let numberVar = 42;
 6|     let stringVar = "Hello, Debug!";
 7|     let booleanVar = true;
 8|     let nullVar = null;
 9|     let undefinedVar = undefined;
10|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
11|     let longStringValue = "This is a very long string value that should be trunc
12| ated when displayed in the tree view to prevent line wrapping";
13| 
14|     // Complex types
15|     let arrayVar = [1, 2, 3, "four", { five: 5 }];
16|     let objectVar = {
17|         name: "Test Object",
18|         count: 100,
19|         nested: {
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: debugtree_frame_collapsed
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▶ 📁  Local: testVariables                                       │
 5|     let│▶ 📁  Global                                                     │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| W10: Warning: Changing a readonly file                        1,1           All
]]


--[[ TERMINAL SNAPSHOT: debugtree_scope_expanded
Size: 24x80
Cursor: [130, 0] (line 130, col 0)
Mode: n

117| // Test fixture for Variables plugin - various variable types
118| 
119| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
120|     // │╰─ ▶ 󰊕 Uint16Array: ƒ Uint16Array()                             │
121|     let│╰─ ▶ 󰊕 Uint32Array: ƒ Uint32Array()                             │
122|     let│╰─ ▶ 󰊕 Uint8Array: ƒ Uint8Array()                               │
123|     let│╰─ ▶ 󰊕 Uint8ClampedArray: ƒ Uint8ClampedArray()                 │
124|     let│╰─   󰟢 undefined: undefined                                     │
125|     let│╰─ ▶ 󰊕 unescape: ƒ unescape()                                   │
126|     let│╰─ ▶ 󰊕 URIError: ƒ URIError()                                   │lue";
127|     let│╰─ ▶ 󰊕 URL: class URL { #context = new URLContext...            │e trunc
128| ated wh│╰─ ▶ 󰊕 URLSearchParams: class URLSearchParams { #searchParams...│
129|        │╰─ ▶ 󰊕 WeakMap: ƒ WeakMap()                                     │
130|     // │╰─ ▶ 󰊕 WeakRef: ƒ WeakRef()                                     │
131|     let│╰─ ▶ 󰊕 WeakSet: ƒ WeakSet()                                     │
132|     let│╰─ ▶ 󰀬 WebAssembly: WebAssembly {compile: ƒ, validate: <c6>...  │
133|        │╰─ ▶ 󰅩 [{Prototype}]: Object                                    │
134|        │                                                                │
135|        ╰────────────────────────────────────────────────────────────────╯
136|             level: 2,
137|             data: ["a", "b", "c"]
138|         },
139| lua/testing/fixtures/variables/complex.js                     7,1            Top
140| W10: Warning: Changing a readonly file                        130,1         Bot
]]


--[[ TERMINAL SNAPSHOT: debugtree_navigate_down
Size: 24x80
Cursor: [130, 0] (line 130, col 0)
Mode: n

117| // Test fixture for Variables plugin - various variable types
118| 
119| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
120|     // │╰─ ▶ 󰊕 Uint16Array: ƒ Uint16Array()                             │
121|     let│╰─ ▶ 󰊕 Uint32Array: ƒ Uint32Array()                             │
122|     let│╰─ ▶ 󰊕 Uint8Array: ƒ Uint8Array()                               │
123|     let│╰─ ▶ 󰊕 Uint8ClampedArray: ƒ Uint8ClampedArray()                 │
124|     let│╰─   󰟢 undefined: undefined                                     │
125|     let│╰─ ▶ 󰊕 unescape: ƒ unescape()                                   │
126|     let│╰─ ▶ 󰊕 URIError: ƒ URIError()                                   │lue";
127|     let│╰─ ▶ 󰊕 URL: class URL { #context = new URLContext...            │e trunc
128| ated wh│╰─ ▶ 󰊕 URLSearchParams: class URLSearchParams { #searchParams...│
129|        │╰─ ▶ 󰊕 WeakMap: ƒ WeakMap()                                     │
130|     // │╰─ ▶ 󰊕 WeakRef: ƒ WeakRef()                                     │
131|     let│╰─ ▶ 󰊕 WeakSet: ƒ WeakSet()                                     │
132|     let│╰─ ▶ 󰀬 WebAssembly: WebAssembly {compile: ƒ, validate: <c6>...  │
133|        │╰─ ▶ 󰅩 [{Prototype}]: Object                                    │
134|        │                                                                │
135|        ╰────────────────────────────────────────────────────────────────╯
136|             level: 2,
137|             data: ["a", "b", "c"]
138|         },
139| lua/testing/fixtures/variables/complex.js                     7,1            Top
140| W10: Warning: Changing a readonly file                        130,1         Bot
]]


--[[ TERMINAL SNAPSHOT: debugtree_navigate_up
Size: 24x80
Cursor: [129, 0] (line 129, col 0)
Mode: n

117| // Test fixture for Variables plugin - various variable types
118| 
119| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
120|     // │╰─ ▶ 󰊕 Uint16Array: ƒ Uint16Array()                             │
121|     let│╰─ ▶ 󰊕 Uint32Array: ƒ Uint32Array()                             │
122|     let│╰─ ▶ 󰊕 Uint8Array: ƒ Uint8Array()                               │
123|     let│╰─ ▶ 󰊕 Uint8ClampedArray: ƒ Uint8ClampedArray()                 │
124|     let│╰─   󰟢 undefined: undefined                                     │
125|     let│╰─ ▶ 󰊕 unescape: ƒ unescape()                                   │
126|     let│╰─ ▶ 󰊕 URIError: ƒ URIError()                                   │lue";
127|     let│╰─ ▶ 󰊕 URL: class URL { #context = new URLContext...            │e trunc
128| ated wh│╰─ ▶ 󰊕 URLSearchParams: class URLSearchParams { #searchParams...│
129|        │╰─ ▶ 󰊕 WeakMap: ƒ WeakMap()                                     │
130|     // │╰─ ▶ 󰊕 WeakRef: ƒ WeakRef()                                     │
131|     let│╰─ ▶ 󰊕 WeakSet: ƒ WeakSet()                                     │
132|     let│╰─ ▶ 󰀬 WebAssembly: WebAssembly {compile: ƒ, validate: <c6>...  │
133|        │╰─ ▶ 󰅩 [{Prototype}]: Object                                    │
134|        │                                                                │
135|        ╰────────────────────────────────────────────────────────────────╯
136|             level: 2,
137|             data: ["a", "b", "c"]
138|         },
139| lua/testing/fixtures/variables/complex.js                     7,1            Top
140| W10: Warning: Changing a readonly file                        129,1         Bot
]]


--[[ TERMINAL SNAPSHOT: debugtree_focus_mode
Size: 24x80
Cursor: [129, 0] (line 129, col 0)
Mode: n

117| // Test fixture for Variables plugin - various variable types
118| 
119| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
120|     // │╰─ ▶ 󰊕 Uint16Array: ƒ Uint16Array()                             │
121|     let│╰─ ▶ 󰊕 Uint32Array: ƒ Uint32Array()                             │
122|     let│╰─ ▶ 󰊕 Uint8Array: ƒ Uint8Array()                               │
123|     let│╰─ ▶ 󰊕 Uint8ClampedArray: ƒ Uint8ClampedArray()                 │
124|     let│╰─   󰟢 undefined: undefined                                     │
125|     let│╰─ ▶ 󰊕 unescape: ƒ unescape()                                   │
126|     let│╰─ ▶ 󰊕 URIError: ƒ URIError()                                   │lue";
127|     let│╰─ ▶ 󰊕 URL: class URL { #context = new URLContext...            │e trunc
128| ated wh│╰─ ▶ 󰊕 URLSearchParams: class URLSearchParams { #searchParams...│
129|        │╰─ ▶ 󰊕 WeakMap: ƒ WeakMap()                                     │
130|     // │╰─ ▶ 󰊕 WeakRef: ƒ WeakRef()                                     │
131|     let│╰─ ▶ 󰊕 WeakSet: ƒ WeakSet()                                     │
132|     let│╰─ ▶ 󰀬 WebAssembly: WebAssembly {compile: ƒ, validate: <c6>...  │
133|        │╰─ ▶ 󰅩 [{Prototype}]: Object                                    │
134|        │                                                                │
135|        ╰────────────────────────────────────────────────────────────────╯
136|             level: 2,
137|             data: ["a", "b", "c"]
138|         },
139| lua/testing/fixtures/variables/complex.js                     7,1            Top
140| W10: Warning: Changing a readonly file                        129,1         Bot
]]


--[[ TERMINAL SNAPSHOT: debugtree_interactive_cleanup
Size: 24x80
Cursor: [129, 0] (line 129, col 0)
Mode: n

117| // Test fixture for Variables plugin - various variable types
118| 
119| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
120|     // │╰─ ▶ 󰊕 Uint16Array: ƒ Uint16Array()                             │
121|     let│╰─ ▶ 󰊕 Uint32Array: ƒ Uint32Array()                             │
122|     let│╰─ ▶ 󰊕 Uint8Array: ƒ Uint8Array()                               │
123|     let│╰─ ▶ 󰊕 Uint8ClampedArray: ƒ Uint8ClampedArray()                 │
124|     let│╰─   󰟢 undefined: undefined                                     │
125|     let│╰─ ▶ 󰊕 unescape: ƒ unescape()                                   │
126|     let│╰─ ▶ 󰊕 URIError: ƒ URIError()                                   │lue";
127|     let│╰─ ▶ 󰊕 URL: class URL { #context = new URLContext...            │e trunc
128| ated wh│╰─ ▶ 󰊕 URLSearchParams: class URLSearchParams { #searchParams...│
129|        │╰─ ▶ 󰊕 WeakMap: ƒ WeakMap()                                     │
130|     // │╰─ ▶ 󰊕 WeakRef: ƒ WeakRef()                                     │
131|     let│╰─ ▶ 󰊕 WeakSet: ƒ WeakSet()                                     │
132|     let│╰─ ▶ 󰀬 WebAssembly: WebAssembly {compile: ƒ, validate: <c6>...  │
133|        │╰─ ▶ 󰅩 [{Prototype}]: Object                                    │
134|        │                                                                │
135|        ╰────────────────────────────────────────────────────────────────╯
136|             level: 2,
137|             data: ["a", "b", "c"]
138|         },
139| lua/testing/fixtures/variables/complex.js                     7,1            Top
140| W10: Warning: Changing a readonly file                        129,1         Bot
]]