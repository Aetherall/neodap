local nio = require("nio")
local NvimAsync = require("neodap.tools.async")
local TerminalSnapshot = require("testing.terminal_snapshot")

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

  local lastStepTimestamp = 0


  ---@param fn fun(api: Api, manager: Manager)
  function T.Scenario(fn)
    local filename = debug.getinfo(2, "S").source:match("([^/]+)%.lua$")
    it(filename, function()
      local future = nio.control.future()
      local Api = require('neodap.api.Api')
      local Manager = require('neodap.session.manager')
      local manager = Manager.create()
      local api = Api.register(manager)
      NvimAsync.run(function()
        fn(api, manager)
        future.set()
      end)
      local is_debugger = os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1"
      if not is_debugger then
        assert(vim.wait(20000, future.is_set), "Timed out after 10 seconds waiting for scenario: " .. filename)
      else
        -- For debugging, we wait 5 minutes to allow manual inspection
        assert(vim.wait(300000, future.is_set), "Timed out after 5 minutes waiting for scenario: " .. filename)
      end
    end)
  end

  function T.spy(name)
    name = name or "anonymous"
    local future = nio.control.future()

    ---@param ms number?
    local function wait(ms)
      -- assert(vim.wait(ms or 1000, future.is_set), name)
      local result = future:wait()
      print("=====> Waited for " .. name)
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
    nio.sleep(500) -- Give time for terminal to update
    TerminalSnapshot.capture(name)
    lastStepTimestamp = os.time()
  end

  function T.cmd(command)
    nio.sleep(20) -- Allow time for command to execute
    vim.cmd(command)
    nio.sleep(20) -- Allow time for command to execute
    lastStepTimestamp = os.time()
  end

  -- Region snapshot function
  function T.RegionSnapshot(name, region)
    TerminalSnapshot.capture_region(name, region)
  end

  -- Cleanup snapshots
  function T.CleanupSnapshots()
    TerminalSnapshot.cleanup()
  end

  function T.sleep(ms)
    nio.sleep(ms or 1000)
    lastStepTimestamp = os.time()
  end

  function T.moveTo(line, column)
    vim.api.nvim_win_set_cursor(0, { line or 1, column or 0 })
    nio.sleep(100)
  end

  return T
end
