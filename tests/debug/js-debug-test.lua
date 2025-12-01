-- Test js-debug stack frame access and scope exploration with bootstrap/child session pattern
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local neostate = require("neostate")
local dap_sdk = require("dap-sdk")

print("=== JS-Debug Stack Frame and Scope Test ===\n")

-- Run in async context
neostate.void(function()
    -- Create debugger
    local debugger = dap_sdk.Debugger:new()

    -- Create bootstrap session for js-debug
    print("Creating bootstrap session...")
    local bootstrap_session = debugger:create_session({
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
            local h, p = chunk:match("Debug server listening at (.*):(%d+)")
            return tonumber(p), h
        end
    })
    bootstrap_session.name:set("JS-Debug Bootstrap")

    -- Track child session
    local child_session = nil
    local stopped_event_received = false

    -- Watch for child sessions
    bootstrap_session.children:subscribe(function()
        print(string.format("[CHILDREN] Bootstrap has %d children", #bootstrap_session.children._items))
        for session in bootstrap_session:children():iter() do
            if not child_session then
                child_session = session
                print(string.format("[CHILD] Got child session: %s", session.name:get()))

                -- Watch child session state
                session.state:watch(function(state)
                    print(string.format("[CHILD STATE] %s", state))
                    if state == "stopped" then
                        stopped_event_received = true
                    end
                end)
            end
        end
    end)

    -- Initialize bootstrap session
    print("Initializing bootstrap session...")
    local err = bootstrap_session:initialize({
        clientID = "neovim",
        clientName = "Neovim DAP Client",
        adapterID = "js-debug",
        pathFormat = "path",
        linesStartAt1 = true,
        columnsStartAt1 = true,
        supportsVariableType = true,
        supportsVariablePaging = true,
        supportsRunInTerminalRequest = false,
    })

    if err then
        print("Initialize failed: " .. err)
        bootstrap_session:dispose()
        return
    end
    print("✓ Bootstrap initialized\n")

    -- Launch the test program (which will create a child session)
    print("Launching test.js...")
    err = bootstrap_session:launch({
        type = "pwa-node",
        request = "launch",
        name = "Test",
        program = vim.fn.fnamemodify("./tests/fixtures/test.js", ":p"),
        cwd = vim.fn.getcwd(),
        stopOnEntry = false,
    })

    if err then
        print("Launch failed: " .. err)
        bootstrap_session:dispose()
        return
    end
    print("✓ Launched\n")

    -- Wait for child session to be created and stop at debugger statement
    print("Waiting for child session and breakpoint (timeout: 15s)...")
    local wait_result = vim.wait(15000, function()
        return child_session ~= nil and stopped_event_received
    end, 100)

    if not wait_result then
        print("✗ Timeout waiting")
        print(string.format("  Child session: %s", child_session and "exists" or "nil"))
        print(string.format("  Stopped event: %s", tostring(stopped_event_received)))
        if child_session then
            print(string.format("  Child state: %s", child_session.state:get()))
            print(string.format("  Child threads: %d", #child_session.threads._items))
        end
        bootstrap_session:dispose()
        return
    end

    print("✓ Hit breakpoint in child session\n")

    -- Find the stopped thread in child session
    local test_thread = nil
    for thread in child_session.threads:iter() do
        if thread.state:get() == "stopped" then
            test_thread = thread
            break
        end
    end

    if not test_thread then
        print("✗ No stopped thread found in child session")
        bootstrap_session:dispose()
        return
    end

    print(string.format("Found stopped thread: %d\n", test_thread.id))

    -- Test stack frame access
    print("=== Testing Stack Frame Access ===")
    local stack = test_thread:stack()
    if not stack then
        print("✗ Failed to get stack")
        bootstrap_session:dispose()
        return
    end
    print(string.format("✓ Got stack with %d frames", #stack.frames._items))

    local top_frame = stack:top()
    if not top_frame then
        print("✗ Failed to get top frame")
        bootstrap_session:dispose()
        return
    end
    print(string.format("✓ Top frame: %s (line %d)", top_frame.name, top_frame.line))

    -- Test scope exploration
    print("\n=== Testing Scope Exploration ===")
    local scopes = top_frame:scopes()
    if not scopes then
        print("✗ Failed to get scopes")
        bootstrap_session:dispose()
        return
    end
    print(string.format("✓ Got %d scopes", #scopes._items))

    -- Print scopes
    for scope in scopes:iter() do
        print(string.format("  - %s (expensive: %s)", scope.name, tostring(scope.expensive)))
    end

    -- Test variable access
    print("\n=== Testing Variable Access ===")
    for scope in scopes:iter() do
        if scope.name == "Local" or scope.name == "Locals" then
            print(string.format("\nExploring '%s' scope variables:", scope.name))
            local variables = scope:variables()
            if not variables then
                print("✗ Failed to get variables")
                bootstrap_session:dispose()
                return
            end
            print(string.format("✓ Got %d variables", #variables._items))

            -- Print top-level variables
            for var in variables:iter() do
                if var.variablesReference > 0 then
                    print(string.format("  - %s: %s (expandable)", var.name, var.value))

                    -- Expand nested variables for 'user' object
                    if var.name == "user" then
                        print("\n    Expanding 'user' object:")
                        local nested_vars = var:variables()
                        if nested_vars then
                            for nested_var in nested_vars:iter() do
                                if nested_var.variablesReference > 0 then
                                    print(string.format("      - %s: %s (expandable)", nested_var.name, nested_var.value))

                                    -- Expand 'address' if present
                                    if nested_var.name == "address" then
                                        print("\n        Expanding 'address' object:")
                                        local address_vars = nested_var:variables()
                                        if address_vars then
                                            for addr_var in address_vars:iter() do
                                                print(string.format("          - %s: %s", addr_var.name, addr_var.value))
                                            end
                                        end
                                    end
                                else
                                    print(string.format("      - %s: %s", nested_var.name, nested_var.value))
                                end
                            end
                        end
                    end
                else
                    print(string.format("  - %s: %s", var.name, var.value))
                end
            end

            break
        end
    end

    print("\n=== Test Complete ===")
    print("All tests passed! ✓")

    -- Continue execution and cleanup
    child_session:continue()
    vim.defer_fn(function()
        bootstrap_session:dispose()
    end, 1000)
end)()
