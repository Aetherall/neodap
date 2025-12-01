-- Example: Using the SDK layer (plugin developer)
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local sdk = require('neodap.sdk')

print("=== SDK Layer Example ===\n")

-- Plugin that works with any debugger instance
sdk:onDebugger(function(debugger)
    print(string.format("New debugger created!"))

    debugger.sessions:subscribe(function(session)
        print(string.format("  New session: %s", session.name:get()))

        session.state:watch(function(state)
            print(string.format("    Session %s state: %s", session.name:get(), state))
        end)
    end)
end)

-- Create a debugger (could be done by user or framework)
local debugger1 = sdk:create_debugger()
print("\nCreated debugger1\n")

--Create another debugger
local debugger2 = sdk:create_debugger()
print("\nCreated debugger2\n")

print("\nBoth debuggers are being tracked by the plugin!")
