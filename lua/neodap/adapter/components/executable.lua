local Class = require("neodap.tools.class")
local uv = vim.uv
local nio = require("nio")

---@class ExecutableProps
---@field cmd string
---@field args table
---@field cwd string
---@field stdout uv_pipe_t
---@field stderr uv_pipe_t
---@field process nio.process.Process?
---@field usage nio.control.Semaphore

---@class Executable: ExecutableProps
---@field new Constructor<ExecutableProps>
local Executable = Class()


---@class ExecutableStartOptions
---@field cmd string
---@field args table
---@field cwd string

---@param opts ExecutableStartOptions
function Executable.spawn(opts)
  local instance = Executable:new({
    cmd = opts.cmd,
    args = opts.args,
    cwd = opts.cwd,
    stdout = assert(uv.new_pipe(false), "Must be able to create pipe"),
    stderr = assert(uv.new_pipe(false), "Must be able to create pipe"),
    usage = 0,
  })

  instance.process = nio.process.run({
    cmd = instance.cmd,
    args = instance.args,
    cwd = instance.cwd,
    stdout = instance.stdout,
    stderr = instance.stderr,
  })

  if not instance.process then
    instance.stdout:close()
    instance.stderr:close()
    print("Failed to spawn process")
    return nil
  end

  -- print("Process spawned with PID: " .. tostring(instance.process.pid))

  ---@async
  nio.run(function()
    local result = instance.process.result(true)
    -- print("Process exited with code: " .. tostring(result))
  end)

  instance.stdout:read_start(function(err, chunk)
    assert(not err, err)
    if chunk then
      -- print("stdout: " .. chunk)
    end
  end)

  instance.stderr:read_start(function(err, chunk)
    assert(not err, err)
    if chunk then
      print("stderr: " .. chunk)
    end
  end)

  return instance
end

function Executable:close()
  if self.process then
    self.process:close()
    self.process = nil
  end

  if self.stdout then
    if not self.stdout:is_closing() then
      self.stdout:close()
    end
    self.stdout = nil
  end

  if self.stderr then
    if not self.stderr:is_closing() then
      self.stderr:close()
    end
    self.stderr = nil
  end

  -- print("Executable closed")
end

return Executable
