local nio = require("nio")
local NvimAsync = require("neodap.tools.async")
local TerminalSnapshot = require("spec.helpers.terminal_snapshot")

return function(describe, it)
  local T = {}

  ---@param name string
  ---@param fn fun()
  function T.Describe(name, fn)
    describe(name, function()
      print("===[ " .. name .. " ]===\n")
      fn()
    end)
  end

  ---@param name string
  ---@param fn async fun()
  function T.It(name, fn)
    it(name, function()
      print("\t>>>[ " .. name .. " ]>>>\n")
      local future = nio.control.future()
      NvimAsync.run(function()
        fn()
        future.set()
      end)
      assert(vim.wait(10000, future.is_set), "Timed out after 10 seconds waiting for " .. name)
    end)
  end

  function T.spy(name)
    name = name or "anonymous"
    local future = nio.control.future()

    ---@param ms number?
    local function wait(ms)
      -- assert(vim.wait(ms or 1000, future.is_set), name)
      local result = future:wait()
      print("=====> Waited for " .. name )
      return result
    end

    ---@param ms number?
    local function wait_longer(ms)
      -- assert(vim.wait(ms or 5000, future.is_set), name)
      future:wait()
    end

    local function trigger(value)
      if not future.is_set() then
        future.set(value or true)
      end
    end

    return {
      set = trigger,
      wait = wait,
      wait_longer = wait_longer,
      trigger = trigger,
      is_set = future.is_set,

    }
  end

  -- Terminal snapshot function
  function T.TerminalSnapshot(name)
    TerminalSnapshot.capture(name)
  end

  -- Region snapshot function
  function T.RegionSnapshot(name, region)
    TerminalSnapshot.capture_region(name, region)
  end

  -- Cleanup snapshots
  function T.CleanupSnapshots()
    TerminalSnapshot.cleanup()
  end

  return T
end
