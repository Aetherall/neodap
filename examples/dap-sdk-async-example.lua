-- Example of using the DAP SDK with async overrides
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local neostate = require("neostate")
local dap_sdk = require("dap-sdk")
local Session = require("dap-sdk.session")

-- Mock DAP server that responds to requests
local function create_mock_adapter()
  local listeners = {}

  return {
    connect = function()
      return {
        request = function(self, command, args, callback)
          -- Simulate async delay
          vim.defer_fn(function()
            if command == "initialize" then
              callback(nil, { supportsConfigurationDoneRequest = true })
            elseif command == "launch" then
              callback(nil, nil)
            elseif command == "stackTrace" then
              callback(nil, {
                stackFrames = {
                  { id = 1, name = "main", line = 10, column = 1, source = { path = "/tmp/test.lua" } }
                },
                totalFrames = 1
              })
            else
              callback("Unknown command: " .. command, nil)
            end
          end, 100)
        end,
        on = function(self, event, handler)
          listeners[event] = handler
        end,
        close = function() end,
        is_closing = function() return false end
      }
    end
  }
end

-- Override create_adapter for testing
local dap_client = require("dap-client")
dap_client.create_adapter = function(opts)
  return create_mock_adapter()
end

-- Run async code
neostate.void(function()
  print("Creating session...")
  local debugger = dap_sdk.Debugger:new()
  local session = Session.Session:new(debugger, { type = "mock" })

  print("Initializing...")
  local err = session:initialize({ adapterID = "mock" })
  if err then
    print("Initialize failed: " .. err)
    return
  end
  print("Initialized!")

  print("Launching...")
  err = session:launch({ program = "test.lua" })
  if err then
    print("Launch failed: " .. err)
    return
  end
  print("Launched!")

  -- Simulate thread started event to trigger stack trace fetch
  -- In a real scenario, this would happen via DAP events
  -- Here we manually trigger the logic for demonstration if we had a thread

  print("Async example finished successfully!")
end)()
