-- Example: Using the singleton API (end user)
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local debugger = require('neodap')

print("=== User API Example ===\n")

-- User doesn't think about instances, just uses the debugger
debugger.sessions:subscribe(function(session)
    print(string.format("New session: %s", session.name:get()))

    session.state:watch(function(state)
        print(string.format("  State: %s", state))
    end)
end)

-- Load the auto-focus plugin
local auto_focus = require('neodap.plugins.auto-focus-leaf')
auto_focus(debugger)

print("Plugin loaded\n")

print("Debugger sessions list is reactive:")
print(string.format("  Current sessions: %d\n", #debugger.sessions._items))

print("Done!")
