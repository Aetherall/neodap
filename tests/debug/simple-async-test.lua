-- Simple async test for debugging
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local neostate = require("neostate")
local dap_sdk = require("dap-sdk")
local Session = require("dap-sdk.session")

print("=== Simple Async Test ===\n")

neostate.void(function()
    print("Inside neostate.void - coroutine is:", coroutine.running())

    local debugger = dap_sdk.Debugger:new()
    print("Created debugger")

    local session = Session.Session:new(debugger, {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
            print("[connect_condition] Got chunk:", chunk:sub(1, 100))
            local h, p = chunk:match("Debug server listening at (.*):(%d+)")
            if h and p then
                print("[connect_condition] Matched! host:", h, "port:", p)
                return tonumber(p), h
            end
            return nil
        end
    })
    print("Created session:", session)

    print("About to call initialize...")
    local err, result = session:initialize({
        clientID = "test",
        clientName = "Test",
        adapterID = "js-debug",
        pathFormat = "path",
        linesStartAt1 = true,
        columnsStartAt1 = true,
    })

    print("Initialize returned - err:", err, "result:", result)

    if err then
        print("ERROR:", err)
    else
        print("SUCCESS!")
    end

    session:dispose()
    print("Done!")
end)()

print("Waiting...")
vim.wait(5000, function() return false end)
print("Test complete")
