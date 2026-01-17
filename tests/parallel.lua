-- Parallel test runner for MiniTest
-- Usage: nvim --headless -u tests/init.lua -c "luafile tests/parallel.lua" [-- options]
--   -j N      Number of parallel workers (default: CPU count)
--   -t MS     Per-test timeout in milliseconds (default: 10000)
--   -f FILE   Run only tests matching FILE pattern
--   -v        Verbose output (show all test output, not just failures)

local uv = vim.uv or vim.loop

-- Cache env vars upfront (can't access vim.env in async callbacks)
local ENV = {
  DEBUGPY_PATH = vim.env.DEBUGPY_PATH,
  JSDBG_PATH = vim.env.JSDBG_PATH,
}

-- Check if setpriv with pdeathsig is available (Linux only)
-- This ensures child processes die when parent nvim dies unexpectedly
local has_pdeathsig = vim.fn.has("linux") == 1 and vim.fn.executable("setpriv") == 1

-- Parse command line arguments from vim.v.argv
local function parse_args()
  -- Default concurrency to number of CPUs
  local default_concurrency = tonumber(vim.uv.available_parallelism and vim.uv.available_parallelism()) or 4

  local args = {
    concurrency = default_concurrency,
    filter_file = nil,
    verbose = false,
    timeout = 10000,  -- Per-test timeout in ms (10s default)
  }

  -- Find arguments after "--"
  local argv = vim.v.argv
  local in_args = false
  local i = 1

  while i <= #argv do
    local a = argv[i]
    if a == "--" then
      in_args = true
    elseif in_args then
      if a == "-j" then
        i = i + 1
        args.concurrency = tonumber(argv[i]) or args.concurrency
      elseif a == "-f" then
        i = i + 1
        args.filter_file = argv[i]
      elseif a == "-t" then
        i = i + 1
        args.timeout = tonumber(argv[i]) or args.timeout
      elseif a == "-v" then
        args.verbose = true
      end
    end
    i = i + 1
  end

  return args
end

-- Discover test files
local function discover_files(filter_file)
  local files = vim.fn.globpath("tests", "**/*.lua", false, true)
  local result = {}
  for _, f in ipairs(files) do
    if not f:match("init%.lua") and not f:match("helpers/") and not f:match("parallel%.lua") then
      if not filter_file or f:match(filter_file) then
        table.insert(result, f)
      end
    end
  end
  return result
end

-- Collect all test cases
local function collect_cases(files)
  local cases = MiniTest.collect({
    find_files = function() return files end,
  })

  local result = {}
  for _, case in ipairs(cases) do
    table.insert(result, {
      desc = case.desc,
      id = table.concat(case.desc, " / "),
      file = case.desc[1],
    })
  end
  return result
end

-- Build command to run a single test
local function build_test_command(test, timeout)
  local desc_lua = vim.inspect(test.desc)
  local filter_fn = string.format([[
    function(c)
      local target = %s
      if #c.desc ~= #target then return false end
      for i, v in ipairs(target) do
        if c.desc[i] ~= v then return false end
      end
      return true
    end
  ]], desc_lua)

  local lua_code = string.format([[
    MiniTest.run({
      collect = {
        find_files = function() return {%q} end,
        filter_cases = %s,
      },
    })
  ]], test.file, filter_fn)

  -- Build command, wrapped with setpriv on Linux to die when parent dies
  local cmd
  if has_pdeathsig then
    cmd = {
      "setpriv", "--pdeathsig=KILL",
      "nvim", "--headless",
      "-u", "tests/init.lua",
      "-c", "lua " .. lua_code:gsub("\n", " "),
      "-c", "qa!",
    }
  else
    cmd = {
      "nvim", "--headless",
      "-u", "tests/init.lua",
      "-c", "lua " .. lua_code:gsub("\n", " "),
      "-c", "qa!",
    }
  end

  return {
    cmd = cmd,
    env = {
      NEODAP_TEST_TIMEOUT = tostring(timeout),
      DEBUGPY_PATH = ENV.DEBUGPY_PATH,
      JSDBG_PATH = ENV.JSDBG_PATH,
    },
  }
end

-- Run tests in parallel with limited concurrency
local function run_parallel(tests, concurrency, verbose, timeout)
  local results = {}
  local running = 0
  local index = 1
  local completed = 0
  local total = #tests
  local failed = 0
  local passed = 0

  -- Progress timer - print status every 5 seconds
  local progress_timer = uv.new_timer()
  progress_timer:start(5000, 5000, function()
    vim.schedule(function()
      io.write(string.format("[%d/%d] tests ran\n", completed, total))
      io.flush()
    end)
  end)

  -- Print failure immediately
  local function report_failure(test_id)
    io.write(string.format("[%d/%d](%d) Failing: %s\n", completed, total, failed, test_id))
    io.flush()
  end

  -- Start a test
  local function start_next()
    if index > total then return false end

    local test = tests[index]
    index = index + 1
    running = running + 1

    local stdout_chunks = {}
    local stderr_chunks = {}

    local spec = build_test_command(test, timeout)
    local handle
    local timed_out = false
    local watchdog_timer = uv.new_timer()

    handle = vim.system(spec.cmd, {
      text = true,
      env = spec.env,
      stdout = function(_, data)
        if data then table.insert(stdout_chunks, data) end
      end,
      stderr = function(_, data)
        if data then table.insert(stderr_chunks, data) end
      end,
    }, function(obj)
      -- Stop the watchdog timer
      if watchdog_timer then
        watchdog_timer:stop()
        watchdog_timer:close()
        watchdog_timer = nil
      end

      running = running - 1
      completed = completed + 1

      local result = {
        test = test,
        code = timed_out and 124 or obj.code,
        stdout = table.concat(stdout_chunks),
        stderr = table.concat(stderr_chunks) .. (timed_out and "\n[TIMEOUT: test killed after " .. timeout .. "ms]\n" or ""),
      }
      table.insert(results, result)

      if result.code == 0 then
        passed = passed + 1
      else
        failed = failed + 1
        report_failure(test.id)
      end

      -- Start next test if available (direct call, we're already async)
      start_next()
    end)

    -- Start per-test watchdog timer
    watchdog_timer:start(timeout + 1000, 0, function()
      timed_out = true
      if handle then
        handle:kill("sigkill")
      end
    end)

    return true
  end

  -- Start initial batch
  for _ = 1, concurrency do
    if not start_next() then break end
  end

  -- Wait for all to complete
  while completed < total do
    vim.wait(100, function() return false end)
  end

  -- Stop progress timer
  progress_timer:stop()
  progress_timer:close()

  return results, passed, failed
end

-- Strip ANSI escape codes
local function strip_ansi(text)
  return text:gsub("\027%[[%d;]*m", "")
end

-- Filter and truncate text
local function truncate_lines(text, max_lines)
  -- Strip ANSI codes first
  text = strip_ansi(text)

  local lines = {}
  local filtered = 0
  for line in text:gmatch("[^\n]+") do  -- [^\n]+ skips empty lines
    -- Skip empty tilde lines (e.g., "04|~") and color grid lines (e.g., "01|00111...")
    -- Skip MiniTest boilerplate lines
    if line:match("^%s*%d%d|~%s*$")
      or line:match("^%s*%d%d|%d%d%d%d%d")
      or line:match("^Total number of cases:")
      or line:match("^Total number of groups:")
      or line:match("^Fails %(%d+%) and Notes %(%d+%)")
      or line:match("^tests/[^:]+: [ox]$")
    then
      filtered = filtered + 1
    elseif #lines < max_lines then
      table.insert(lines, line)
    end
  end
  local result = table.concat(lines, "\n")
  if filtered > 0 then
    result = result .. string.format("\n... (%d verbose lines filtered)", filtered)
  end
  return result
end

-- Print results
local function print_results(results, verbose)
  local failures = {}

  for _, r in ipairs(results) do
    if r.code ~= 0 then
      table.insert(failures, r)
    elseif verbose then
      print("\n" .. string.rep("-", 60))
      print("PASS: " .. r.test.id)
      if #r.stdout > 0 then print(r.stdout) end
    end
  end

  if #failures > 0 then
    print("\n" .. string.rep("=", 60))
    print("FAILURES DETAILS:")
    print(string.rep("=", 60))

    for _, r in ipairs(failures) do
      print("\n" .. string.rep("-", 60))
      print("FAIL: " .. r.test.id)
      print(string.rep("-", 60))
      -- Truncate stdout to 30 lines to avoid huge screenshot diffs
      if #r.stdout > 0 then print(truncate_lines(r.stdout, 30)) end
      if #r.stderr > 0 then
        print("STDERR:")
        print(truncate_lines(r.stderr, 10))
      end
    end
  end
end

-- Clean up old per-PID test directories to prevent unbounded growth
local function cleanup_test_dirs()
  local root = ".tests"
  local current_pid = tostring(vim.fn.getpid())
  local handle = uv.fs_scandir(root)
  if not handle then return end

  while true do
    local name, type = uv.fs_scandir_next(handle)
    if not name then break end
    if type == "directory" then
      -- Remove numeric directories (PIDs from tests/init.lua)
      local is_pid_dir = name:match("^%d+$") and name ~= current_pid
      -- Remove neodap_test_* directories (PIDs from fixtures.lua)
      local is_fixture_dir = name:match("^neodap_test_%d+$") and name ~= ("neodap_test_" .. current_pid)
      if is_pid_dir or is_fixture_dir then
        vim.fn.delete(root .. "/" .. name, "rf")
      end
    end
  end
end

-- Main
local function main()
  local args = parse_args()

  -- Clean up stale PID directories from previous runs
  cleanup_test_dirs()

  -- Orchestrator watchdog: total timeout based on test count and per-test timeout
  -- Will be set after we know how many tests there are
  local watchdog

  io.write("Discovering test files...\n")
  local files = discover_files(args.filter_file)
  io.write(string.format("Found %d test files\n", #files))

  io.write("Collecting test cases...\n")
  local tests = collect_cases(files)
  io.write(string.format("Found %d test cases\n", #tests))

  -- Set orchestrator watchdog: (tests / concurrency) * timeout + 30s buffer
  local total_timeout = math.ceil(#tests / args.concurrency) * args.timeout + 30000
  watchdog = uv.new_timer()
  watchdog:start(total_timeout, 0, function()
    io.stderr:write(string.format("\n\nORCHESTRATOR TIMEOUT after %ds\n", total_timeout / 1000))
    os.exit(124)
  end)

  io.write(string.format("Running with %d parallel workers (timeout: %ds per test)...\n\n", args.concurrency, args.timeout / 1000))

  local results, passed, failed = run_parallel(tests, args.concurrency, args.verbose, args.timeout)

  print_results(results, args.verbose)

  print(string.rep("=", 60))
  print(string.format("TOTAL: %d passed, %d failed, %d total", passed, failed, #results))
  print(string.rep("=", 60))

  os.exit(failed > 0 and 1 or 0)
end

main()
