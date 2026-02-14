-- Shared restart utility for entities with state signals
local log = require("neodap.logger")

---Terminate a target and call `on_done` once its state reaches "terminated".
---If already terminated, calls `on_done` synchronously.
---Includes a 10s safety timeout to avoid hanging forever.
---@param target table Entity with a `state` signal and a `:terminate()` method
---@param on_done fun() Callback to run after termination (guarded against double-call)
local function terminate_then(target, on_done)
  local done = false
  local function run_once()
    if done then return end
    done = true
    on_done()
  end

  if target.state:get() == "terminated" then
    run_once()
    return
  end

  local unsub
  unsub = target.state:use(function(state)
    if state ~= "terminated" then return end
    vim.schedule(function()
      if unsub then unsub() end
    end)
    run_once()
  end)

  vim.defer_fn(function()
    if done then return end
    log:warn("terminate_then: timed out after 10s, forcing callback")
    if unsub then unsub() end
    run_once()
  end, 10000)

  pcall(function() target:terminate() end)
end

return terminate_then
