---Comprehensive example showing reactive DAP SDK usage
---Demonstrates:
--- - Multi-session debugging
--- - Global breakpoint management with per-session bindings
--- - Reactive thread state tracking
--- - Stack history (current + stale)
--- - Deep variable hierarchy with lazy loading
--- - Automatic cleanup with disposables

package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local neostate = require("neostate")
local dap_sdk = require("dap-sdk")

-- Enable reactive tracing for debugging
neostate.setup({ trace = true })

-- Create root debugger instance
local debugger = dap_sdk.create()

---Example 1: Global Breakpoints with Cross-Session Bindings
print("\n=== Example 1: Global Breakpoints ===")

-- Add global breakpoint (will bind to all sessions that load this file)
local bp1 = debugger:add_breakpoint(
  { path = "/path/to/app.py" },
  42,
  { condition = "x > 10" }
)

-- Watch verification across ALL sessions
bp1.bindings:subscribe(function(binding)
  print(string.format(
    "Breakpoint bound to session '%s'",
    binding.session.name:get()
  ))

  binding.verified:watch(function(verified)
    print(string.format(
      "  Session '%s': verified=%s line=%s",
      binding.session.name:get(),
      verified,
      binding.actualLine:get() or "pending"
    ))
  end)
end)

---Example 2: Multi-Session Debugging with Parent-Child Sessions
print("\n=== Example 2: Multi-Session Setup ===")

-- Create parent session (debugpy for Python)
local parent_session = debugger:create_session({
  type = "stdio",
  command = "python3",
  args = { "-m", "debugpy.adapter" }
})

parent_session.name:set("Python Main")

-- Watch for child sessions (e.g., multiprocessing spawns)
parent_session.children:subscribe(function(child)
  print(string.format("Child session spawned: %s", child.name:get()))

  -- Child inherits breakpoints automatically!
  child.bindings:each(function(binding)
    print(string.format(
      "  Child inherited breakpoint at line %d",
      binding.breakpoint.line
    ))
  end)
end)

-- Create another independent session (JavaScript)
local js_session = debugger:create_session({
  type = "server",
  command = "js-debug",
  args = { "0" },
  connect_condition = function(chunk)
    local h, p = chunk:match("Debug server listening at (.*):(%d+)")
    return tonumber(p), h
  end
})

js_session.name:set("JavaScript App")

---Example 3: Reactive Thread State Tracking
print("\n=== Example 3: Thread State Tracking ===")

-- React to threads across ALL sessions
debugger.sessions:each(function(session)
  print(string.format("Watching session: %s", session.name:get()))

  session.threads:subscribe(function(thread)
    print(string.format("  New thread %d: %s", thread.id, thread.name:get()))

    -- Watch thread state changes
    thread.state:watch(function(state)
      if state == "stopped" then
        local reason = thread.stopReason:get()
        print(string.format(
          "    Thread %d stopped: %s",
          thread.id,
          reason
        ))

        -- Automatically fetch stack when stopped
        thread:stack():watch(function(stack)
          if stack then
            print(string.format(
              "      Stack trace (%d frames, reason: %s)",
              #vim.iter(stack.frames:iter()):totable(),
              stack.reason
            ))

            -- Show top 3 frames
            local count = 0
            for frame in stack.frames:iter() do
              if count >= 3 then break end
              print(string.format(
                "        #%d %s at %s:%d",
                count,
                frame.name,
                frame.source.path or "?",
                frame.source.line
              ))
              count = count + 1
            end
          end
        end)
      elseif state == "running" then
        print(string.format("    Thread %d resumed", thread.id))
      end
    end)

    -- Keep stack history
    thread.stale_stacks:subscribe(function(stale_stack)
      print(string.format(
        "    Archived stack: %s (%d frames)",
        stale_stack.reason,
        #vim.iter(stale_stack.frames:iter()):totable()
      ))
    end)
  end)
end)

---Example 4: Deep Variable Inspection with Lazy Loading
print("\n=== Example 4: Variable Inspection ===")

-- When a thread stops, inspect variables
local function inspect_variables(thread)
  local stack = thread:stack():get()
  if not stack then return end

  -- Get top frame
  local frame = vim.iter(stack.frames:iter()):nth(1)
  if not frame then return end

  print(string.format("Inspecting frame: %s", frame.name))

  -- Lazy load scopes
  frame:scopes():watch(function(scopes)
    if not scopes then return end

    for scope in scopes:iter() do
      print(string.format("  Scope: %s (expensive=%s)", scope.name, scope.expensive))

      -- Lazy load variables
      scope:variables():watch(function(variables)
        if not variables then return end

        for variable in variables:iter() do
          print(string.format(
            "    %s: %s = %s",
            variable.type:get() or "?",
            variable.name,
            variable.value:get()
          ))

          -- If variable has children, we can lazy load them
          if variable.variablesReference > 0 then
            print(string.format("      (expandable, ref=%d)", variable.variablesReference))

            -- Example: expand first level
            variable:variables():watch(function(child_vars)
              if not child_vars then return end

              for child in child_vars:iter() do
                print(string.format(
                  "        %s = %s",
                  child.name,
                  child.value:get()
                ))
              end
            end)
          end
        end
      end)
    end
  end)
end

---Example 5: Unified Output Stream Across Sessions
print("\n=== Example 5: Output Streaming ===")

-- Collect outputs from all sessions with metadata
debugger.sessions:each(function(session)
  session.outputs:subscribe(function(output)
    local level = vim.log.levels.INFO
    if output.category == "stderr" then
      level = vim.log.levels.ERROR
    elseif output.category == "telemetry" then
      level = vim.log.levels.DEBUG
    end

    vim.schedule(function()
      vim.notify(
        string.format("[%s] %s", session.name:get(), output.output),
        level
      )
    end)
  end)
end)

---Example 6: Breakpoint Modification Syncs to All Sessions
print("\n=== Example 6: Breakpoint Sync ===")

-- Modify breakpoint condition - automatically syncs to all bindings
vim.defer_fn(function()
  bp1.condition:set("x > 20 and y < 5")
  -- This triggers setBreakpoints in ALL sessions that have this file loaded!
end, 2000)

---Example 7: Session Lifecycle and Cleanup
print("\n=== Example 7: Lifecycle Management ===")

-- Initialize and launch parent session
-- Initialize and launch parent session
neostate.void(function()
  local err = parent_session:initialize({
    adapterID = "debugpy",
    clientID = "neovim",
    linesStartAt1 = true,
    columnsStartAt1 = true,
    pathFormat = "path",
  })

  if err then
    print("Initialize failed:", err)
    return
  end

  print("Parent session initialized")

  -- Register source files (enables breakpoint binding)
  parent_session:register_source("/path/to/app.py")
  parent_session:register_source("/path/to/utils.py")

  local err = parent_session:launch({
    request = "launch",
    program = "/path/to/app.py",
    console = "internalConsole",
  })

  if err then
    print("Launch failed:", err)
    return
  end

  print("Parent session launched")
end)()

-- When session terminates, everything cleans up automatically
parent_session:on_dispose(function()
  print("Parent session disposed - all threads, stacks, frames auto-cleaned!")
end)

---Example 8: Programmatic Stepping with State Tracking
print("\n=== Example 8: Stepping ===")

local function step_through_function(thread)
  print(string.format("Stepping through thread %d", thread.id))

  -- Step into
  thread:step_into("statement", function(err)
    if err then
      print("Step into failed:", err)
      return
    end

    -- Wait for stopped event (state will update reactively)
    thread.state:watch(function(state)
      if state == "stopped" then
        -- Inspect current location
        local stack = thread:stack():get()
        if stack then
          local frame = vim.iter(stack.frames:iter()):nth(1)
          if frame then
            print(string.format(
              "Stepped to: %s at %s:%d",
              frame.name,
              frame.source.path or "?",
              frame.source.line
            ))

            -- Step over next
            vim.defer_fn(function()
              thread:step_over("line")
            end, 1000)
          end
        end
      end
    end)
  end)
end

---Example 9: Evaluate Expressions in Frame Context
print("\n=== Example 9: Expression Evaluation ===")

local function evaluate_in_frame(frame, expression)
  frame:evaluate(expression, "repl", function(err, result)
    if err then
      print(string.format("Evaluation failed: %s", err))
      return
    end

    print(string.format(
      "Evaluated '%s' = %s (type: %s)",
      expression,
      result.result,
      result.type or "?"
    ))

    -- If result has children, we can expand
    if result.variablesReference > 0 then
      print("  (result is expandable)")
    end
  end)
end

---Example 10: Modify Variable Values
print("\n=== Example 10: Variable Modification ===")

local function modify_variable(variable, new_value)
  print(string.format("Setting %s = %s", variable.name, new_value))

  variable:set_value(new_value, function(err, value, type)
    if err then
      print(string.format("  Failed: %s", err))
      return
    end

    print(string.format("  Success: %s = %s", variable.name, value))

    -- value Signal is automatically updated reactively!
    -- Any UI watching variable.value:get() will see the change
  end)
end

---Cleanup: Dispose entire debugger
print("\n=== Cleanup ===")

-- When done debugging:
-- debugger:dispose()
-- This will:
-- 1. Dispose all sessions (parent and children)
-- 2. Close all DAP connections
-- 3. Dispose all breakpoints and bindings
-- 4. Dispose all threads
-- 5. Dispose all stacks (current and stale)
-- 6. Dispose all frames, scopes, variables
-- 7. Clear all reactive subscriptions
-- Everything cleaned up in LIFO order!

print("\n=== SDK Ready ===")
print("All reactive watchers are active.")
print("When sessions start and threads stop, output will appear above.")
print("Use debugger:dispose() to clean up everything.")
