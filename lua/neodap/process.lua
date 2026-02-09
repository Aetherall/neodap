-- Core process spawning for DAP adapters
--
-- Provides raw process management via vim.system with:
-- - pdeathsig wrapping (Linux) to kill orphaned processes
-- - ProcessHandle interface for DAP communication

local log = require("neodap.logger")

local M = {}

-- Check if setpriv with pdeathsig is available (Linux only)
local has_pdeathsig = vim.fn.has("linux") == 1 and vim.fn.executable("setpriv") == 1

--- Wrap command to die when parent dies (Linux only)
---@param command string
---@param args string[]?
---@return string command
---@return string[] args
local function wrap_pdeathsig(command, args)
  if not has_pdeathsig then
    return command, args or {}
  end
  local new_args = { "--pdeathsig=KILL", command }
  for _, arg in ipairs(args or {}) do
    table.insert(new_args, arg)
  end
  return "setpriv", new_args
end

---@class neodap.process.SpawnOpts
---@field command string Command to execute
---@field args? string[] Command arguments
---@field cwd? string Working directory
---@field env? table<string, string> Environment variables

---Spawn a process with stdio communication
---@param opts neodap.process.SpawnOpts
---@return neodap.ProcessHandle
function M.spawn(opts)
  local data_callbacks = {}
  local stderr_callbacks = {}
  local exit_callbacks = {}
  local exited = false

  local cmd, args = wrap_pdeathsig(opts.command, opts.args)

  log:debug("Spawning process", { command = cmd, args = args, cwd = opts.cwd })

  -- Wrap vim.system in pcall to handle spawn failures gracefully
  local ok, sys_obj = pcall(vim.system, { cmd, unpack(args) }, {
    cwd = opts.cwd,
    env = opts.env,
    stdin = true,
    stdout = function(err, data)
      if data then
        for _, cb in ipairs(data_callbacks) do
          cb(data)
        end
      end
    end,
    stderr = function(err, data)
      if data then
        for _, cb in ipairs(stderr_callbacks) do
          cb(data)
        end
      end
    end,
  }, function(result)
    if not exited then
      exited = true
      vim.schedule(function()
        for _, cb in ipairs(exit_callbacks) do
          cb(result.code or -1)
        end
      end)
    end
  end)

  -- Handle spawn failure - return a "failed" handle that notifies immediately
  if not ok then
    local err_msg = tostring(sys_obj)
    log:error("Failed to spawn process", { command = cmd, error = err_msg })
    vim.schedule(function()
      vim.notify("Failed to spawn: " .. opts.command .. "\n" .. err_msg, vim.log.levels.ERROR)
    end)

    -- Return a handle that immediately reports failure
    return {
      write = function() end,
      on_data = function() end,
      on_stderr = function() end,
      on_exit = function(cb)
        vim.schedule(function() cb(-1) end)
      end,
      kill = function() end,
      spawn_error = err_msg,
    }
  end

  log:debug("Process spawned successfully", { pid = sys_obj.pid })

  return {
    write = function(data)
      if not sys_obj:is_closing() then
        sys_obj:write(data)
      end
    end,
    on_data = function(cb)
      table.insert(data_callbacks, cb)
    end,
    on_stderr = function(cb)
      table.insert(stderr_callbacks, cb)
    end,
    on_exit = function(cb)
      if exited then
        vim.schedule(function() cb(-1) end)
      else
        table.insert(exit_callbacks, cb)
      end
    end,
    kill = function()
      if not sys_obj:is_closing() then
        -- Use vim.uv.kill directly for reliable signal delivery
        -- Note: vim.uv.kill requires lowercase signal names
        pcall(vim.uv.kill, sys_obj.pid, "sigkill")
      end
    end,
  }
end

return M
