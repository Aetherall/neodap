-- Simplified bootstrap test
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local neostate = require("neostate")
local dap_sdk = require("dap-sdk")

print("=== Bootstrap Test ===\n")

neostate.void(function()
    local debugger = dap_sdk.Debugger:new()

    print("[1] Creating bootstrap session...")
    local bootstrap = debugger:create_session({
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
            print("[connect]", chunk:sub(1, 60))
            local h, p = chunk:match("Debug server listening at (.*):(%d+)")
            if h and p then
                print("[connect] Matched:", p, h)
                return tonumber(p), h
            end
            return nil
        end
    })
    print("[2] Created, name:", bootstrap.name:get())

    -- Get paths before async operations (to avoid fast event context issue)
    local test_program = vim.fn.fnamemodify("./tests/fixtures/test.js", ":p")
    local test_cwd = vim.fn.getcwd()

    -- Watch children
    local child_count = 0
    bootstrap.children:subscribe(function()
        child_count = child_count + 1
        print(string.format("[3] Child event #%d - %d children", child_count, #bootstrap.children._items))
    end)

    print("[4] Initializing...")
    local err = bootstrap:initialize({
        clientID = "test",
        adapterID = "js-debug",
        pathFormat = "path",
        linesStartAt1 = true,
        columnsStartAt1 = true,
    })
    print("[5] Initialize returned, err:", err)

    print("[6] Launching...")
    err = bootstrap:launch({
        type = "pwa-node",
        request = "launch",
        name = "Test",
        program = test_program,
        cwd = test_cwd,
        stopOnEntry = false,
    })
    print("[7] Launch returned, err:", err)

    print("[8] Waiting for children...")
    vim.wait(5000, function() return #bootstrap.children._items > 0 end, 100)
    print(string.format("[9] Children: %d", #bootstrap.children._items))

    bootstrap:dispose()
    print("[10] Done!")
end)()

vim.wait(2000, function() return false end)
print("Complete")
