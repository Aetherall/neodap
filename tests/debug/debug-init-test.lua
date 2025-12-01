-- Debug test to see what's happening with initialize
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local neostate = require("neostate")
local dap_sdk = require("dap-sdk")
local Session = require("dap-sdk.session")

print("=== Debug Test ===\n")

neostate.void(function()
    print("[1] Inside void, coroutine:", coroutine.running())

    local debugger = dap_sdk.Debugger:new()
    print("[2] Created debugger")

    local session = Session.Session:new(debugger, {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
            print("[connect] chunk:", chunk:sub(1, 60))
            local h, p = chunk:match("Debug server listening at (.*):(%d+)")
            if h and p then
                print("[connect] Matched! Returning:", p, h)
                return tonumber(p), h
            end
            return nil
        end
    })
    print("[3] Created session")

    print("[4] About to call initialize...")
    print("[4a] Client object:", session.client)
    print("[4b] Client request method:", session.client.request)

    local err, result = session:initialize({
        clientID = "test",
        adapterID = "js-debug",
        pathFormat = "path",
        linesStartAt1 = true,
        columnsStartAt1 = true,
    })

    print("[5] Initialize returned!")
    print("    err:", err)
    print("    result:", result and "table" or "nil")

    session:dispose()
    print("[6] Done!")
end)()

print("Waiting 5s...")
vim.wait(5000, function() return false end)
print("Complete")
