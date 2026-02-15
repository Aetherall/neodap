-- Process supervisor for neodap
--
-- Manages debug adapter processes through shell shims that own process groups.
-- The OS process tree mirrors the configuration hierarchy:
--
--   nvim
--   └── compound-shim (fullstack-local)     ← process group leader
--       ├── config-shim (API-all)           ← process group leader
--       │   └── js-debug → pnpm → node
--       ├── config-shim (fb:start-dev)
--       │   └── js-debug → firebase
--       └── config-shim (web:rsbuild)
--           └── js-debug → rsbuild
--
-- Communication is filesystem-based (the tmpdir is the interface):
--   <rundir>/<name>/pid       shim PID (= PGID)
--   <rundir>/<name>/stdout    adapter stdout (nvim watches, parses port)
--   <rundir>/<name>/stderr    adapter stderr
--   <rundir>/<name>/exit      exit code (written when adapter dies)
--
-- Control is signal-based:
--   kill -TERM -<pgid>        stop a config (kills entire process group)
--   kill -TERM -<compound>    stop compound (kills everything)

local log = require("neodap.logger")
local uv = vim.uv

local M = {}

-- Counter for unique run IDs
local run_counter = 0

---Create a unique run directory under /tmp/neodap/
---@return string rundir
local function create_rundir()
  run_counter = run_counter + 1
  local base = string.format("/tmp/neodap/%d/%d", uv.os_getpid(), run_counter)
  vim.fn.mkdir(base, "p")
  return base
end

-- Shell script template for config shims.
-- Arguments: $1 = name, $2 = rundir, rest = adapter command
-- The shim:
--   1. Names itself in /proc/self/comm (visible in pstree/ps)
--   2. Writes its PID to the rundir (PID = PGID since we spawn with setsid)
--   3. Spawns the adapter with stdout/stderr redirected to files
--   4. Waits for the adapter to exit
--   5. Writes exit code to the rundir
-- sh -c 'script' $0=$name $1=$dir $2..=command
local CONFIG_SHIM = [[
dir="$1"; shift
printf '%s' "$0" > /proc/self/comm 2>/dev/null
mkdir -p "$dir"
printf '%s' "$$" > "$dir/pid"
"$@" >"$dir/stdout" 2>"$dir/stderr" &
child=$!
printf '%s' "$child" > "$dir/adapter.pid"
trap 'kill -TERM "$child" 2>/dev/null' TERM INT HUP
wait "$child" 2>/dev/null
printf '%s' "$?" > "$dir/exit"
]]

-- Shell script template for compound shims.
-- Arguments: $1 = name, $2 = rundir
-- Config shim scripts are pre-written to $rundir/configs/*.sh
-- The compound shim:
--   1. Names itself
--   2. Writes PID
--   3. Runs each config script as a background job
--   4. Waits for all
-- sh -c 'script' $0=$name $1=$dir
local COMPOUND_SHIM = [[
dir="$1"; shift
printf '%s' "$0" > /proc/self/comm 2>/dev/null
printf '%s' "$$" > "$dir/pid"
pids=""
for script in "$dir"/configs/*.sh; do
  if [ -f "$script" ]; then
    sh "$script" &
    pids="$pids $!"
  fi
done
trap 'kill -TERM $pids 2>/dev/null' TERM INT HUP
wait
printf '%s' "$?" > "$dir/exit"
]]

---@class neodap.supervisor.ConfigHandle
---@field name string Config name
---@field pid number Shim PID (= PGID)
---@field rundir string Path to this config's run directory
---@field stop fun() Send SIGTERM to process group
---@field kill fun() Send SIGKILL to process group
---@field on_stdout fun(cb: fun(data: string)) Watch for adapter stdout data
---@field on_exit fun(cb: fun(code: number)) Watch for adapter exit

---@class neodap.supervisor.CompoundHandle
---@field name string Compound name
---@field pid number Compound shim PID (= PGID)
---@field rundir string Path to compound's run directory
---@field configs table<string, neodap.supervisor.ConfigHandle>
---@field stop fun() Send SIGTERM to compound process group
---@field kill fun() Send SIGKILL to compound process group

---Convert a key=value env table to the string list format uv.spawn expects.
---@param env_table table<string, string>
---@return string[]
local function env_to_list(env_table)
  local list = {}
  for k, v in pairs(env_table) do
    table.insert(list, k .. "=" .. v)
  end
  return list
end

---Spawn a shell shim via detached (new session/process group) + setpriv (pdeathsig).
---@param script string Shell script body
---@param args string[] Arguments to pass to the script
---@param env? table<string, string> Environment variables
---@param cwd? string Working directory
---@return number pid
---@return userdata handle uv_process_t
local function spawn_shim(script, args, env, cwd)
  -- Build command: setpriv --pdeathsig=SIGTERM sh -c <script> <args...>
  -- We use vim.uv.spawn with detached=true so the child gets its own session
  -- (setsid). setpriv sets pdeathsig AFTER the fork so it survives.
  -- Result: child is session leader + process group leader + has pdeathsig.
  local cmd_args = { "--pdeathsig=SIGTERM", "sh", "-c", script }
  for _, arg in ipairs(args) do
    table.insert(cmd_args, arg)
  end

  local exit_callbacks = {}
  local handle, pid = uv.spawn("setpriv", {
    args = cmd_args,
    cwd = cwd,
    env = env and env_to_list(env) or nil,
    detached = true,
    stdio = { nil, nil, nil },
  }, function(code, signal)
    log:debug("Shim exited", { pid = pid, code = code, signal = signal })
    vim.schedule(function()
      for _, cb in ipairs(exit_callbacks) do
        cb(code, signal)
      end
    end)
  end)

  if not handle then
    error("Failed to spawn shim: " .. tostring(pid))
  end

  log:info("Shim spawned", { pid = pid, args = args })
  return pid, handle, exit_callbacks
end

---Watch a file for new data using polling.
---fs_event is unreliable for files written by other processes on some systems,
---so we use a timer-based poll that reads new bytes since last check.
---@param path string File path to watch
---@param callback fun(data: string) Called with new data chunks
---@param interval? number Poll interval in ms (default: 50)
---@return fun() stop Stop watching
local function watch_file(path, callback, interval)
  interval = interval or 50
  local offset = 0
  local timer = uv.new_timer()

  timer:start(0, interval, function()
    -- Read from current offset
    uv.fs_open(path, "r", 438, function(err, fd)
      if err or not fd then return end

      uv.fs_fstat(fd, function(stat_err, stat)
        if stat_err or not stat or stat.size <= offset then
          uv.fs_close(fd)
          return
        end

        local to_read = stat.size - offset
        uv.fs_read(fd, to_read, offset, function(read_err, data)
          uv.fs_close(fd)
          if read_err or not data or #data == 0 then return end
          offset = offset + #data
          vim.schedule(function()
            callback(data)
          end)
        end)
      end)
    end)
  end)

  return function()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
end

---Wait for a file to appear, then read its contents.
---@param path string File path
---@param callback fun(content: string)
---@param timeout? number Timeout in ms (default: 30000)
---@return fun() cancel
local function wait_for_file(path, callback, timeout)
  timeout = timeout or 30000
  local timer = uv.new_timer()
  local timed_out = false

  local timeout_timer = uv.new_timer()
  timeout_timer:start(timeout, 0, function()
    timed_out = true
    timer:stop()
    timer:close()
    timeout_timer:stop()
    timeout_timer:close()
    vim.schedule(function()
      log:error("Timeout waiting for file", { path = path })
    end)
  end)

  timer:start(0, 50, function()
    if timed_out then return end
    uv.fs_stat(path, function(err, stat)
      if err or not stat then return end
      uv.fs_open(path, "r", 438, function(open_err, fd)
        if open_err or not fd then return end
        uv.fs_read(fd, stat.size, 0, function(read_err, data)
          uv.fs_close(fd)
          if read_err or not data then return end
          timer:stop()
          timer:close()
          timeout_timer:stop()
          timeout_timer:close()
          vim.schedule(function()
            callback(data)
          end)
        end)
      end)
    end)
  end)

  return function()
    if not timed_out and timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if timeout_timer and not timeout_timer:is_closing() then
      timeout_timer:stop()
      timeout_timer:close()
    end
  end
end

---Send SIGTERM to a process group.
---@param pgid number Process group ID (= shim PID)
local function kill_group(pgid, signal)
  signal = signal or "sigterm"
  -- Negative PID = send to process group
  local ok, err = pcall(uv.kill, -pgid, signal)
  if not ok then
    log:debug("kill_group failed (likely already dead)", { pgid = pgid, error = err })
  end
end

---Launch a single config through a shell shim.
---@param opts { name: string, command: string, args?: string[], env?: table, cwd?: string, connect_condition?: fun(chunk: string): number?, string? }
---@param callback fun(err?: string, handle?: neodap.supervisor.ConfigHandle, port?: number, host?: string)
function M.launch_config(opts, callback)
  local rundir = create_rundir()
  local config_dir = rundir .. "/" .. opts.name
  vim.fn.mkdir(config_dir, "p")

  -- Build shim arguments: name, dir, command, args...
  local shim_args = { opts.name, config_dir, opts.command }
  for _, arg in ipairs(opts.args or {}) do
    table.insert(shim_args, arg)
  end

  local pid, uv_handle = spawn_shim(CONFIG_SHIM, shim_args, opts.env, opts.cwd)
  local stdout_watchers = {}
  local exit_watchers = {}
  local stop_watch_stdout = nil
  local stop_watch_exit = nil

  ---@type neodap.supervisor.ConfigHandle
  local handle = {
    name = opts.name,
    pid = pid,
    rundir = config_dir,
    port = nil,  ---@type number?
    host = nil,  ---@type string?
    stop = function()
      kill_group(pid, "sigterm")
    end,
    kill = function()
      kill_group(pid, "sigkill")
    end,
    on_stdout = function(cb)
      table.insert(stdout_watchers, cb)
    end,
    on_exit = function(cb)
      table.insert(exit_watchers, cb)
    end,
  }

  -- Watch adapter stdout for data (connect_condition parsing, logging)
  stop_watch_stdout = watch_file(config_dir .. "/stdout", function(data)
    for _, cb in ipairs(stdout_watchers) do
      cb(data)
    end
  end)

  -- Watch for exit file
  stop_watch_exit = wait_for_file(config_dir .. "/exit", function(content)
    local code = tonumber(content) or -1
    if stop_watch_stdout then stop_watch_stdout() end
    for _, cb in ipairs(exit_watchers) do
      cb(code)
    end
  end)

  -- If connect_condition is provided, watch stdout for port announcement
  if opts.connect_condition then
    local connected = false
    handle.on_stdout(function(data)
      if connected then return end
      local port, host = opts.connect_condition(data)
      if port then
        connected = true
        handle.port = port
        handle.host = host
        callback(nil, handle, port, host)
      end
    end)

    -- If adapter exits before port is found, that's an error
    handle.on_exit(function(code)
      if not connected then
        callback("Adapter exited before port was detected (code " .. code .. ")")
      end
    end)
  else
    -- No connect_condition — handle is ready immediately
    callback(nil, handle)
  end

  return handle
end

---Shell-escape a string for embedding in a shell script.
---@param s string
---@return string
local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

---@class neodap.supervisor.CompoundConfigSpec
---@field name string Config name (shows in pstree)
---@field command string Adapter command
---@field args? string[] Adapter arguments
---@field connect_condition? fun(chunk: string): number?, string? Port detection function

---Launch a compound configuration through nested shell shims.
---The compound shim is the process group leader; all config shims run as its children.
---@param opts { name: string, configs: neodap.supervisor.CompoundConfigSpec[] }
---@param on_config_ready fun(name: string, handle: neodap.supervisor.ConfigHandle, port?: number, host?: string) Called per config when adapter is ready
---@param on_config_error? fun(name: string, err: string) Called per config on error
---@return neodap.supervisor.CompoundHandle
function M.launch_compound(opts, on_config_ready, on_config_error)
  local rundir = create_rundir()
  local configs_dir = rundir .. "/configs"
  vim.fn.mkdir(configs_dir, "p")

  -- Write a config shim script for each config
  for i, cfg in ipairs(opts.configs) do
    local config_dir = rundir .. "/" .. cfg.name
    vim.fn.mkdir(config_dir, "p")

    -- Build shell arguments: $0=name, $1=dir, $2..=command
    local escaped_args = { shell_escape(cfg.name), shell_escape(config_dir), shell_escape(cfg.command) }
    for _, arg in ipairs(cfg.args or {}) do
      table.insert(escaped_args, shell_escape(arg))
    end

    -- CONFIG_SHIM uses: $0=name (from sh -c), $1=dir, $2..=command
    -- In the wrapper script, set $0 via the sh -c convention
    local script = string.format(
      "#!/bin/sh\nexec sh -c %s %s\n",
      shell_escape(CONFIG_SHIM),
      table.concat(escaped_args, " ")
    )

    local script_path = string.format("%s/%02d-%s.sh", configs_dir, i, cfg.name)
    local f = io.open(script_path, "w")
    if f then
      f:write(script)
      f:close()
    end
  end

  -- Spawn compound shim
  local pid, _, exit_cbs = spawn_shim(COMPOUND_SHIM, { opts.name, rundir }, nil, nil)

  ---@type table<string, neodap.supervisor.ConfigHandle>
  local config_handles = {}

  -- Set up watchers for each config
  for _, cfg in ipairs(opts.configs) do
    local config_dir = rundir .. "/" .. cfg.name
    local stdout_watchers = {}
    local exit_watchers = {}

    local cfg_handle = {
      name = cfg.name,
      pid = nil, ---@type number?
      port = nil, ---@type number?
      host = nil, ---@type string?
      rundir = config_dir,
      stop = function()
        -- Kill config shim by PID (sends SIGTERM, trap kills its child)
        local pid_file = config_dir .. "/pid"
        local f_pid = io.open(pid_file, "r")
        if f_pid then
          local cfg_pid = tonumber(f_pid:read("*a"))
          f_pid:close()
          if cfg_pid then pcall(vim.uv.kill, cfg_pid, "sigterm") end
        end
      end,
      kill = function()
        local pid_file = config_dir .. "/pid"
        local f_pid = io.open(pid_file, "r")
        if f_pid then
          local cfg_pid = tonumber(f_pid:read("*a"))
          f_pid:close()
          if cfg_pid then pcall(vim.uv.kill, cfg_pid, "sigkill") end
        end
      end,
      on_stdout = function(cb)
        table.insert(stdout_watchers, cb)
      end,
      on_exit = function(cb)
        table.insert(exit_watchers, cb)
      end,
    }

    -- Watch stdout
    local stop_stdout = watch_file(config_dir .. "/stdout", function(data)
      for _, cb in ipairs(stdout_watchers) do
        cb(data)
      end
    end)

    -- Watch exit
    wait_for_file(config_dir .. "/exit", function(content)
      local code = tonumber(content) or -1
      if stop_stdout then stop_stdout() end
      for _, cb in ipairs(exit_watchers) do
        cb(code)
      end
    end)

    -- Read PID when it appears
    wait_for_file(config_dir .. "/pid", function(content)
      cfg_handle.pid = tonumber(content)
    end)

    -- Port detection via connect_condition
    if cfg.connect_condition then
      local connected = false
      cfg_handle.on_stdout(function(data)
        if connected then return end
        local port, host = cfg.connect_condition(data)
        if port then
          connected = true
          cfg_handle.port = port
          cfg_handle.host = host
          on_config_ready(cfg.name, cfg_handle, port, host)
        end
      end)
      cfg_handle.on_exit(function(code)
        if not connected and on_config_error then
          on_config_error(cfg.name, "Adapter exited before port was detected (code " .. code .. ")")
        end
      end)
    else
      -- No connect_condition — ready immediately (once pid appears)
      wait_for_file(config_dir .. "/pid", function()
        on_config_ready(cfg.name, cfg_handle)
      end)
    end

    config_handles[cfg.name] = cfg_handle
  end

  ---@type neodap.supervisor.CompoundHandle
  local compound_handle = {
    name = opts.name,
    pid = pid,
    rundir = rundir,
    configs = config_handles,
    stop = function()
      kill_group(pid, "sigterm")
    end,
    kill = function()
      kill_group(pid, "sigkill")
    end,
    on_exit = function(cb)
      table.insert(exit_cbs, cb)
    end,
  }

  return compound_handle
end

return M
