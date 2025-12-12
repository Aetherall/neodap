-- Integration tests for the process supervisor
--
-- Tests the full application flow: DapLaunch -> supervisor spawns processes ->
-- DAP sessions connect -> DapDisconnect/DapTerminate -> supervisor kills process tree.
--
-- These tests are JavaScript-only because the supervisor is only used for
-- server-type adapters (js-debug). Python uses stdio and bypasses the supervisor.

local MiniTest = require("mini.test")
local harness = require("helpers.test_harness")

local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()
local adapter = harness.adapters.javascript

T["supervisor"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/init.lua", "--headless" })
    end,
    post_case = function()
      -- Don't call cleanup() — the tests manage their own lifecycle.
      -- Just kill the child neovim (which kills supervisor via pdeathsig).
      child.stop()
    end,
  },
})

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function create_harness()
  local h = harness.new(child, adapter)
  h:setup_neodap()
  return h
end

--- Check if a process is alive (not dead, not zombie) from the child neovim
local function process_alive(h, pid)
  return h:get(string.format([[
    (function()
      local f = io.open("/proc/%d/stat", "r")
      if not f then return false end
      local stat = f:read("*a")
      f:close()
      local state = stat:match("^%%d+ %%b() (%%S)")
      -- Zombie or dead = not alive
      if state == "Z" or state == "X" or state == "x" then return false end
      return true
    end)()
  ]], pid))
end

--- Get all supervisor rundirs from the child's /tmp/neodap/ directory
local function get_rundirs(h)
  return h:get([[
    (function()
      local nvim_pid = vim.uv.os_getpid()
      local base = "/tmp/neodap/" .. nvim_pid
      local handle = vim.uv.fs_scandir(base)
      if not handle then return {} end
      local dirs = {}
      while true do
        local name = vim.uv.fs_scandir_next(handle)
        if not name then break end
        table.insert(dirs, base .. "/" .. name)
      end
      table.sort(dirs)
      return dirs
    end)()
  ]])
end

--- List config directories in a rundir (excludes "configs" and "pid" etc)
local function get_config_dirs(h, rundir)
  return h:get(string.format([[
    (function()
      local dirs = {}
      local handle = vim.uv.fs_scandir(%q)
      if not handle then return dirs end
      while true do
        local name, type = vim.uv.fs_scandir_next(handle)
        if not name then break end
        if type == "directory" and name ~= "configs" then
          table.insert(dirs, name)
        end
      end
      return dirs
    end)()
  ]], rundir))
end

--- Read a PID from a supervisor file
local function read_pid_file(h, path)
  return h:get(string.format([[
    (function()
      local f = io.open(%q, "r")
      if not f then return nil end
      local content = f:read("*a")
      f:close()
      return tonumber(content)
    end)()
  ]], path))
end

--- Wait for a process to die or become a zombie (poll with timeout).
--- A zombie (state='Z') counts as dead since it can't do anything.
local function wait_process_dead(h, pid, timeout_ms)
  timeout_ms = timeout_ms or 5000
  return h:get(string.format([[
    (function()
      local deadline = vim.uv.now() + %d
      while vim.uv.now() < deadline do
        -- Check /proc/<pid>/stat — if it doesn't exist, process is fully gone
        local f = io.open("/proc/%d/stat", "r")
        if not f then return true end
        local stat = f:read("*a")
        f:close()
        -- Parse state from /proc/pid/stat: "pid (comm) state ..."
        local state = stat:match("^%%d+ %%b() (%%S)")
        -- Zombie ('Z') or dead — counts as dead for our purposes
        if state == "Z" or state == "X" or state == "x" then return true end
        vim.wait(100, function() return false end, 10)
      end
      return false
    end)()
  ]], timeout_ms, pid))
end

--- Collect all descendant PIDs of a process
local function collect_descendants(h, root_pid)
  return h:get(string.format([[
    (function()
      local descendants = {}
      local queue = { %d }
      while #queue > 0 do
        local pid = table.remove(queue, 1)
        local path = string.format("/proc/%%d/task/%%d/children", pid, pid)
        local f = io.open(path, "r")
        if f then
          local content = f:read("*a")
          f:close()
          for child_pid in content:gmatch("%%d+") do
            local cpid = tonumber(child_pid)
            if cpid then
              table.insert(descendants, cpid)
              table.insert(queue, cpid)
            end
          end
        end
      end
      return descendants
    end)()
  ]], root_pid))
end

--- Check that supervisor files exist in a config directory
local function check_supervisor_files(h, dir)
  return h:get(string.format([[
    (function()
      local function exists(path)
        return vim.uv.fs_stat(path) ~= nil
      end
      return {
        pid = exists(%q .. "/pid"),
        stdout = exists(%q .. "/stdout"),
        adapter_pid = exists(%q .. "/adapter.pid"),
      }
    end)()
  ]], dir, dir, dir))
end

--- Read /proc/<pid>/stat and return parsed session ID
local function get_session_id(h, pid)
  return h:get(string.format([[
    (function()
      local f = io.open("/proc/%d/stat", "r")
      if not f then return nil end
      local stat = f:read("*a")
      f:close()
      local rest = stat:match("^%%d+ %%b() (.+)$")
      if not rest then return nil end
      local fields = {}
      for field in rest:gmatch("%%S+") do
        table.insert(fields, field)
      end
      -- fields[1]=state, [2]=ppid, [3]=pgrp, [4]=session
      return tonumber(fields[4])
    end)()
  ]], pid))
end

--- Read /proc/<pid>/stat and return parent PID
local function get_ppid(h, pid)
  return h:get(string.format([[
    (function()
      local f = io.open("/proc/%d/stat", "r")
      if not f then return nil end
      local stat = f:read("*a")
      f:close()
      local rest = stat:match("^%%d+ %%b() (.+)$")
      if not rest then return nil end
      local fields = {}
      for field in rest:gmatch("%%S+") do
        table.insert(fields, field)
      end
      return tonumber(fields[2])
    end)()
  ]], pid))
end

--- Collect all shim + adapter PIDs from a rundir
local function collect_all_pids(h, rundir)
  local config_dirs = get_config_dirs(h, rundir)
  local pids = {}
  for _, name in ipairs(config_dirs) do
    local dir = rundir .. "/" .. name
    local shim_pid = read_pid_file(h, dir .. "/pid")
    if shim_pid then table.insert(pids, shim_pid) end
    local adapter_pid = read_pid_file(h, dir .. "/adapter.pid")
    if adapter_pid then table.insert(pids, adapter_pid) end
  end
  return pids
end

-------------------------------------------------------------------------------
-- Single config: launch -> supervisor files -> disconnect -> processes dead
-------------------------------------------------------------------------------

T["supervisor"]["single config launch creates supervisor rundir and files"] = function()
  local h = create_harness()
  h:fixture("simple-vars")
  h:cmd("DapLaunch Debug stop")

  -- js-debug creates root + child session; wait for child to stop
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")

  -- Supervisor should have created a rundir with files
  local rundirs = get_rundirs(h)
  MiniTest.expect.equality(#rundirs > 0, true)

  -- Find config directories
  local rundir = rundirs[1]
  local config_dirs = get_config_dirs(h, rundir)
  MiniTest.expect.equality(#config_dirs > 0, true)

  -- Check supervisor files exist
  local config_dir = rundir .. "/" .. config_dirs[1]
  local files = check_supervisor_files(h, config_dir)
  MiniTest.expect.equality(files.pid, true)
  MiniTest.expect.equality(files.stdout, true)
  MiniTest.expect.equality(files.adapter_pid, true)

  -- Shim process should be alive
  local shim_pid = read_pid_file(h, config_dir .. "/pid")
  MiniTest.expect.equality(shim_pid ~= nil, true)
  MiniTest.expect.equality(process_alive(h, shim_pid), true)

  -- Adapter process should be alive
  local adapter_pid = read_pid_file(h, config_dir .. "/adapter.pid")
  MiniTest.expect.equality(adapter_pid ~= nil, true)
  MiniTest.expect.equality(process_alive(h, adapter_pid), true)
end

T["supervisor"]["disconnect gracefully stops shim and adapter"] = function()
  local h = create_harness()
  h:fixture("simple-vars")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Get PIDs before disconnect
  local rundirs = get_rundirs(h)
  local rundir = rundirs[1]
  local config_dirs = get_config_dirs(h, rundir)
  local config_dir = rundir .. "/" .. config_dirs[1]
  local shim_pid = read_pid_file(h, config_dir .. "/pid")
  local adapter_pid = read_pid_file(h, config_dir .. "/adapter.pid")

  -- Disconnect — graceful: SIGTERMs shim, which forwards to adapter via trap
  h:cmd("DapDisconnect")
  h:wait_terminated()

  -- Shim and adapter should be dead (SIGTERM cascaded through trap)
  MiniTest.expect.equality(wait_process_dead(h, shim_pid, 6000), true)
  MiniTest.expect.equality(wait_process_dead(h, adapter_pid, 6000), true)
end

T["supervisor"]["terminate kills entire process tree"] = function()
  local h = create_harness()
  h:fixture("simple-vars")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Get PIDs and all descendants before terminate
  local rundirs = get_rundirs(h)
  local rundir = rundirs[1]
  local config_dirs = get_config_dirs(h, rundir)
  local config_dir = rundir .. "/" .. config_dirs[1]
  local shim_pid = read_pid_file(h, config_dir .. "/pid")
  local all_descendants = collect_descendants(h, shim_pid)

  -- Terminate — aggressive: stop_tree() walks all descendants, SIGKILL escalation
  h:cmd("DapTerminate")
  h:wait_terminated()

  -- Shim and ALL descendants should be dead
  MiniTest.expect.equality(wait_process_dead(h, shim_pid, 6000), true)
  for _, pid in ipairs(all_descendants) do
    MiniTest.expect.equality(wait_process_dead(h, pid, 6000), true)
  end
end

T["supervisor"]["shim is session leader with adapter as child"] = function()
  local h = create_harness()
  h:fixture("simple-vars")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")

  local rundirs = get_rundirs(h)
  local rundir = rundirs[1]
  local config_dirs = get_config_dirs(h, rundir)
  local config_dir = rundir .. "/" .. config_dirs[1]
  local shim_pid = read_pid_file(h, config_dir .. "/pid")
  local adapter_pid = read_pid_file(h, config_dir .. "/adapter.pid")

  -- Shim should be a session leader (PID == SID)
  local shim_sid = get_session_id(h, shim_pid)
  MiniTest.expect.equality(shim_sid, shim_pid)

  -- Adapter should be a direct child of the shim
  local adapter_ppid = get_ppid(h, adapter_pid)
  MiniTest.expect.equality(adapter_ppid, shim_pid)

  -- Shim should have descendants (adapter + adapter's children)
  local descendants = collect_descendants(h, shim_pid)
  MiniTest.expect.equality(#descendants >= 1, true)
end

-------------------------------------------------------------------------------
-- Compound: launch -> all adapters connect -> disconnect -> all processes dead
-------------------------------------------------------------------------------

T["supervisor"]["compound launch creates process tree for all configs"] = function()
  local h = create_harness()
  h:fixture("multi-session")
  h:cmd("DapLaunch Both Programs")

  -- Wait for both sessions to stop (each config → root + child = 4 sessions total)
  h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
  h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

  -- Compound rundir should exist
  local rundirs = get_rundirs(h)
  MiniTest.expect.equality(#rundirs > 0, true)

  local rundir = rundirs[#rundirs]

  -- Should have a "configs" dir with shell scripts
  local has_configs = h:get(string.format([[vim.uv.fs_stat(%q) ~= nil]], rundir .. "/configs"))
  MiniTest.expect.equality(has_configs, true)

  -- Should have config directories for each config
  local config_dirs = get_config_dirs(h, rundir)
  MiniTest.expect.equality(#config_dirs >= 2, true)

  -- Each config dir should have supervisor files and alive processes
  for _, name in ipairs(config_dirs) do
    local config_dir = rundir .. "/" .. name
    local files = check_supervisor_files(h, config_dir)
    MiniTest.expect.equality(files.pid, true)
    MiniTest.expect.equality(files.stdout, true)

    local shim_pid = read_pid_file(h, config_dir .. "/pid")
    MiniTest.expect.equality(process_alive(h, shim_pid), true)
  end

  -- Compound shim should own all config shims as descendants
  local compound_pid = read_pid_file(h, rundir .. "/pid")
  MiniTest.expect.equality(compound_pid ~= nil, true)

  local descendants = collect_descendants(h, compound_pid)
  for _, name in ipairs(config_dirs) do
    local config_dir = rundir .. "/" .. name
    local config_pid = read_pid_file(h, config_dir .. "/pid")
    local found = false
    for _, desc in ipairs(descendants) do
      if desc == config_pid then found = true; break end
    end
    MiniTest.expect.equality(found, true)
  end
end

T["supervisor"]["compound disconnect gracefully stops shims and adapters"] = function()
  local h = create_harness()
  h:fixture("multi-session")
  h:cmd("DapLaunch Both Programs")

  local stopped = "/sessions(state=stopped)[%d]/threads/stacks[0]/frames[0]"
  h:wait_and_focus(
    { stopped:format(0), stopped:format(1) },
    stopped:format(0),
    harness.TIMEOUT.LONG
  )

  -- Collect all shim + adapter PIDs before disconnect
  local rundirs = get_rundirs(h)
  local rundir = rundirs[#rundirs]
  local all_pids = collect_all_pids(h, rundir)
  MiniTest.expect.equality(#all_pids >= 4, true) -- 2 shims + 2 adapters

  -- Disconnect the focused session
  h:cmd("DapDisconnect")

  -- Cleanup remaining sessions
  h:cleanup()

  -- All shim and adapter processes should be dead (graceful SIGTERM cascade)
  for _, pid in ipairs(all_pids) do
    MiniTest.expect.equality(wait_process_dead(h, pid, 6000), true)
  end
end

T["supervisor"]["compound stopAll disconnect gracefully stops all shims"] = function()
  local h = create_harness()
  h:fixture("multi-session")
  h:cmd("DapLaunch Both Programs (stopAll)")

  local stopped = "/sessions(state=stopped)[%d]/threads/stacks[0]/frames[0]"
  h:wait_and_focus(
    { stopped:format(0), stopped:format(1) },
    stopped:format(0),
    harness.TIMEOUT.LONG
  )

  -- Collect all PIDs before disconnect
  local rundirs = get_rundirs(h)
  local rundir = rundirs[#rundirs]
  local all_pids = collect_all_pids(h, rundir)
  MiniTest.expect.equality(#all_pids >= 4, true)

  -- Verify all alive before disconnect
  for _, pid in ipairs(all_pids) do
    MiniTest.expect.equality(process_alive(h, pid), true)
  end

  -- Disconnect the focused session — stopAll should disconnect the entire compound
  h:cmd("DapDisconnect")

  -- All shim and adapter processes should die (SIGTERM cascade through compound shim)
  for _, pid in ipairs(all_pids) do
    MiniTest.expect.equality(wait_process_dead(h, pid, 8000), true)
  end
end

return T
