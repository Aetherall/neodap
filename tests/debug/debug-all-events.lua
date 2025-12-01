-- Debug test to see ALL events from js-debug
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local dap_client = require("dap-client")

print("=== Debug: All Events from js-debug ===\n")

local adapter = dap_client.create_adapter({
    type = "server",
    command = "js-debug",
    args = { "0" },
    connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        if h and p then
            print(string.format("[SERVER] Listening at %s:%s\n", h, p))
            return tonumber(p), h
        end
        return nil
    end
})

local client = adapter.connect()

-- Log ALL events (raw DAP messages)
local old_on = client.on
client.on = function(self, event_name, handler)
    old_on(self, event_name, function(body)
        print(string.format("[EVENT] %s", event_name))
        print(string.format("  Body: %s\n", vim.inspect(body)))
        handler(body)
    end)
end

-- Minimal handlers
local initialized = false
client:on("initialized", function()
    print("[HANDLER] Sending configurationDone...")
    client:request("configurationDone", vim.empty_dict(), function(err)
        if not err then
            initialized = true
            print("[HANDLER] configurationDone complete\n")
        end
    end)
end)

client:on("terminated", function()
    print("[HANDLER] Session terminated")
end)

-- Initialize
print("[REQUEST] Sending initialize...")
client:request("initialize", {
    adapterID = "js-debug",
    clientID = "test",
    linesStartAt1 = true,
    columnsStartAt1 = true,
    pathFormat = "path",
    supportsStartDebuggingRequest = true, -- Enable child session support
}, function(err, result)
    if err then
        print("✗ Initialize failed:", err)
        return
    end
    print("[RESPONSE] Initialize succeeded\n")

    -- Launch
    print("[REQUEST] Sending launch...")
    local program = vim.fn.fnamemodify("./tests/fixtures/test.js", ":p")
    client:request("launch", {
        type = "pwa-node",
        request = "launch",
        name = "Test",
        program = program,
        cwd = vim.fn.getcwd(),
        stopOnEntry = false,
    }, function(err2)
        if err2 then
            print("✗ Launch failed:", err2)
            return
        end
        print("[RESPONSE] Launch succeeded\n")
    end)
end)

-- Wait  for events
print("Waiting 10s for events...\n")
vim.wait(10000, function() return false end)

print("\nClosing client...")
client:close()
print("Done!")
