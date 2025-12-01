-- Test to verify process event startMethod tracking
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local neostate = require("neostate")
local dap_sdk = require("dap-sdk")

print("=== Process Event Start Method Test ===\n")

neostate.void(function()
    local debugger = dap_sdk.Debugger:new()

    -- Get paths before async operations
    local test_program = vim.fn.fnamemodify("./tests/fixtures/test.js", ":p")
    local test_cwd = vim.fn.getcwd()

    print("[1] Creating bootstrap session...")
    local bootstrap = debugger:create_session({
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
            local h, p = chunk:match("Debug server listening at (.*):(%d+)")
            if h and p then
                print(string.format("[connect] js-debug listening at %s:%s", h, p))
                return tonumber(p), h
            end
            return nil
        end
    })
    bootstrap.name:set("Bootstrap")

    -- Watch for process event on bootstrap session
    print("[2] Watching for process events...")
    bootstrap.start_method:watch(function(method)
        if method then
            print(string.format("[BOOTSTRAP] process event: startMethod=%s", method))
            print(string.format("[BOOTSTRAP] is_auto_attached=%s",
                tostring(bootstrap.is_auto_attached:get())))
            print(string.format("[BOOTSTRAP] process_id=%s",
                tostring(bootstrap.process_id:get())))
        end
    end)

    -- Watch for child sessions
    local child_session = nil
    bootstrap.children:subscribe(function()
        for session in bootstrap:children():iter() do
            if not child_session then
                child_session = session
                print(string.format("\n[CHILD] New child session created: %s", session.name:get()))

                -- Watch child's process event
                session.start_method:watch(function(method)
                    if method then
                        print(string.format("[CHILD] process event: startMethod=%s", method))
                        print(string.format("[CHILD] is_auto_attached=%s",
                            tostring(session.is_auto_attached:get())))
                        print(string.format("[CHILD] process_id=%s",
                            tostring(session.process_id:get())))
                    end
                end)
            end
        end
    end)

    print("[3] Initializing bootstrap...")
    local err = bootstrap:initialize({
        clientID = "test",
        adapterID = "js-debug",
        pathFormat = "path",
        linesStartAt1 = true,
        columnsStartAt1 = true,
    })

    if err then
        print("✗ Initialize failed:", err)
        bootstrap:dispose()
        return
    end
    print("✓ Initialized\n")

    print("[4] Launching program...")
    err = bootstrap:launch({
        type = "pwa-node",
        request = "launch",
        name = "Test",
        program = test_program,
        cwd = test_cwd,
        stopOnEntry = false,
    })

    if err then
        print("✗ Launch failed:", err)
        bootstrap:dispose()
        return
    end
    print("✓ Launched\n")

    -- Wait for events to propagate
    print("[5] Waiting 5s for process events...")
    vim.wait(5000, function() return false end)

    print("\n=== Summary ===")
    print(string.format("Bootstrap session:"))
    print(string.format("  - startMethod: %s", tostring(bootstrap.start_method:get())))
    print(string.format("  - is_auto_attached: %s", tostring(bootstrap.is_auto_attached:get())))
    print(string.format("  - Expected: 'launch' and false"))

    if child_session then
        print(string.format("\nChild session:"))
        print(string.format("  - startMethod: %s", tostring(child_session.start_method:get())))
        print(string.format("  - is_auto_attached: %s", tostring(child_session.is_auto_attached:get())))
        print(string.format("  - Expected: 'attachForSuspendedLaunch' and true"))

        -- Verify expectations
        if bootstrap.start_method:get() == "launch" and not bootstrap.is_auto_attached:get() then
            print("\n✓ Bootstrap session correctly identified as user-initiated!")
        else
            print("\n✗ Bootstrap session incorrectly classified")
        end

        if child_session.start_method:get() == "attachForSuspendedLaunch" and
            child_session.is_auto_attached:get() then
            print("✓ Child session correctly identified as auto-attached!")
        else
            print("✗ Child session incorrectly classified")
        end
    else
        print("\n⚠ No child session was created (this might be expected)")
    end

    print("\n[6] Disposing...")
    bootstrap:dispose()
    print("Done!")
end)()

print("\nWaiting 2s for cleanup...")
vim.wait(2000, function() return false end)
print("Test complete")
