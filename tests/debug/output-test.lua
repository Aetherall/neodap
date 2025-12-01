-- Test to verify output capture in child sessions
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local debugger = require('neodap')
local auto_focus = require('neodap.plugins.auto-focus-leaf')

local auto_focus = require('neodap.plugins.auto-focus-leaf')

-- Install plugin
auto_focus(debugger)

-- Register pwa-node adapter (maps to js-debug server)
debugger:register_adapter("pwa-node", {
    type = "server",
    command = "js-debug",
    args = { "0" },
    connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        if h and p then
            return tonumber(p), h
        end
        return nil
    end
})

print("=== Output Capture Test ===\n")

local test_program = vim.fn.fnamemodify("./tests/fixtures/log-test.js", ":p")
local test_cwd = vim.fn.getcwd()
local expected_outputs = {
    ["Hello from child process!"] = false,
    ["This is an error message"] = false,
    ["Delayed message"] = false,
}

-- Helper to check if we found everything
local function check_completion()
    local all_found = true
    for msg, found in pairs(expected_outputs) do
        if not found then
            all_found = false
            break
        end
    end
    return all_found
end

-- Subscribe to sessions to find the child
debugger.sessions:subscribe(function(session)
    print(string.format("[SESSION] Created: %s", session.name:get()))

    -- Subscribe to outputs for EVERY session (bootstrap or child)
    session.outputs:subscribe(function(output)
        -- Clean up output string (remove newlines)
        local msg = output.output:gsub("[\r\n]+$", "")

        -- Check if it's one of our expected messages
        for expected, found in pairs(expected_outputs) do
            if not found and msg:find(expected, 1, true) then
                expected_outputs[expected] = true
                print(string.format("✓ Found output in [%s]: %s", session.name:get(), msg))
            end
        end
    end)
end)

print("[1] Creating bootstrap session...")
local bootstrap = debugger:create_session({
    type = "server",
    command = "js-debug",
    args = { "0" },
    connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        if h and p then
            return tonumber(p), h
        end
        return nil
    end
})
bootstrap.name:set("Bootstrap")

print("[2] Initializing...")
bootstrap:initialize({
    clientID = "test",
    adapterID = "js-debug",
    pathFormat = "path",
    linesStartAt1 = true,
    columnsStartAt1 = true,
})

print("[3] Launching...")
bootstrap:launch({
    type = "pwa-node",
    request = "launch",
    name = "Log Test",
    program = test_program,
    cwd = test_cwd,
    stopOnEntry = false,
})

-- Wait for outputs
print("[4] Waiting for outputs...")
local wait_result = vim.wait(10000, function()
    return check_completion()
end, 100)

print("\n=== Results ===")
if wait_result then
    print("✓ All expected outputs found!")
else
    print("✗ Timed out waiting for outputs")
    for msg, found in pairs(expected_outputs) do
        print(string.format("  - '%s': %s", msg, found and "FOUND" or "MISSING"))
    end
end

print("\nCleaning up...")
bootstrap:dispose()
print("Done!")

if not wait_result then
    os.exit(1)
end
