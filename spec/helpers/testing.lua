local nio = require("nio")

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
      nio.run(function()
        fn()
        future.set()
      end)
      assert(vim.wait(10000, future.is_set), "Should pass")
    end)
  end

  function T.spy(name)
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

  return T
end
