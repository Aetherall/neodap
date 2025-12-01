-- Example: Using the DAP client with type annotations

local dap_client = require("dap-client")

-- Create a debugpy adapter (Python)
local adapter = dap_client.create_adapter({
  type = "stdio",
  command = "python3",
  args = { "-m", "debugpy.adapter" }
})

local client = adapter.connect()

-- Initialize the debug adapter
-- With overloads, you get full type checking - no need for @type annotation!
client:request("initialize", {
  adapterID = "debugpy",
  clientID = "neovim",
  clientName = "Neovim DAP Client",
  linesStartAt1 = true,
  columnsStartAt1 = true,
  pathFormat = "path",
  supportsRunInTerminalRequest = false,
}, function(err, result)
  if err then
    print("Initialization failed:", err)
    return
  end

  -- result is automatically typed as dap.Capabilities!
  print("Adapter capabilities:", vim.inspect(result))
  print("Supports function breakpoints:", result.supportsFunctionBreakpoints)

  -- Configuration done
  client:request("configurationDone", {}, function(err)
    if err then
      print("Configuration failed:", err)
      return
    end

    -- Launch the program - arguments are type-checked automatically
    client:request("launch", {
      program = "${workspaceFolder}/main.py",
      cwd = vim.fn.getcwd(),
      -- Debugpy-specific args
      justMyCode = false,
    }, function(err)
      if err then
        print("Launch failed:", err)
        return
      end

      print("Program launched successfully")
    end)
  end)
end)

-- Listen for stopped events - body is automatically typed!
client:on("stopped", function(body)
  -- body is dap.StoppedEventBody - no cast needed!
  print(string.format("Stopped: reason=%s, threadId=%d", body.reason, body.threadId or 0))

  -- Get stack trace when stopped
  client:request("stackTrace", {
    threadId = body.threadId or 0,
    startFrame = 0,
    levels = 20,
  }, function(err, result)
    if err then
      print("Stack trace failed:", err)
      return
    end

    -- result is dap.StackTraceResponseBody - fully typed!
    print("Stack frames:")
    for i, frame in ipairs(result.stackFrames) do
      print(string.format("  %d: %s at %s:%d",
        i,
        frame.name,
        frame.source and frame.source.path or "?",
        frame.line))
    end
  end)
end)

-- Listen for output events - body typed automatically
client:on("output", function(body)
  local category = body.category or "console"
  local output = body.output or ""
  print(string.format("[%s] %s", category, output))
end)

-- Listen for terminated event
client:on("terminated", function(body)
  print("Debug session terminated")
  client:close()
end)

-- Set breakpoints - arguments are type-checked
client:request("setBreakpoints", {
  source = {
    path = vim.fn.expand("%:p"),
    name = vim.fn.expand("%:t"),
  },
  breakpoints = {
    { line = 10, condition = "x > 5" },
    { line = 20, logMessage = "Value of y: {y}" },
  },
  sourceModified = false,
}, function(err, result)
  if err then
    print("Failed to set breakpoints:", err)
    return
  end

  -- result is dap.SetBreakpointsResponseBody
  print("Breakpoints set:")
  for i, bp in ipairs(result.breakpoints) do
    if bp.verified then
      print(string.format("  %d: Line %d - verified", i, bp.line or 0))
    else
      print(string.format("  %d: Line %d - not verified: %s", i, bp.line or 0, bp.message or ""))
    end
  end
end)

-- Continue execution - all arguments type-checked!
client:request("continue", {
  threadId = 1,
  singleThread = false,
}, function(err, result)
  if err then
    print("Continue failed:", err)
    return
  end
  -- result is dap.ContinueResponseBody
  print("Continued, all threads continuing:", result.allThreadsContinued)
end)

-- Step operations - clean and type-safe
client:request("next", { threadId = 1 }, function(err)
  if err then print("Next failed:", err) end
end)

client:request("stepIn", {
  threadId = 1,
  granularity = "statement"  -- LSP suggests: "statement" | "line" | "instruction"
}, function(err)
  if err then print("Step in failed:", err) end
end)

client:request("stepOut", { threadId = 1 }, function(err)
  if err then print("Step out failed:", err) end
end)

-- Evaluate expression
client:request("evaluate", {
  expression = "x + y",
  frameId = 0,
  context = "watch",  -- LSP suggests: "watch" | "repl" | "hover" | "clipboard" | "variables"
}, function(err, result)
  if err then
    print("Evaluation failed:", err)
    return
  end
  print(string.format("Result: %s (type: %s)", result.result, result.type or "unknown"))
end)

-- Get variables
client:request("variables", {
  variablesReference = 1,
  filter = "named",  -- LSP suggests: "named" | "indexed"
}, function(err, result)
  if err then
    print("Variables failed:", err)
    return
  end
  print("Variables:")
  for _, var in ipairs(result.variables) do
    print(string.format("  %s = %s", var.name, var.value))
  end
end)

-- Disconnect when done
client:request("disconnect", {
  restart = false,
  terminateDebuggee = true,
  suspendDebuggee = false,
}, function(err)
  if err then
    print("Disconnect failed:", err)
  else
    print("Disconnected successfully")
  end
  client:close()
end)
