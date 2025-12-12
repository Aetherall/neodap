--[[
  Lua Function Profiler v2

  Three profiling modes:
  1. Sampling   - Low overhead (~2-5%), samples call stack periodically
  2. Manual     - Zero overhead when disabled, explicit enter/leave calls
  3. Hooks      - Full instrumentation (high overhead, complete data)

  Output formats:
  - report()     - Human-readable table
  - flamegraph() - Collapsed stacks for visualization (speedscope, etc.)
  - tree()       - Hierarchical call tree

  Usage:
    local profiler = dofile('profiler.lua')

    -- Sampling mode (recommended for production profiling)
    profiler.start_sampling(10000)  -- Sample every 10k instructions
    -- ... code ...
    profiler.stop()
    profiler.flamegraph()

    -- Manual mode (for specific hot paths)
    profiler.enable()
    profiler.enter("my_operation")
    -- ... code ...
    profiler.leave()
    profiler.report()

    -- Hook mode (complete but slow)
    profiler.start_hooks()
    -- ... code ...
    profiler.stop()
    profiler.report()
--]]

local profiler = {}

--============================================================================
-- STATE
--============================================================================

local enabled = false
local mode = nil  -- "sampling", "manual", "hooks"

-- Timing
local get_time = os.clock

-- Manual mode state
local manual_stack = {}      -- Current stack of {name, start_time}
local manual_stats = {}      -- name -> {calls, total_time, self_time, children_time}

-- Sampling mode state
local sample_count = 0
local stack_samples = {}     -- "func1;func2;func3" -> count

-- Hook mode state
local hook_stack = {}
local hook_stats = {}        -- func_id -> {calls, total_time, self_time, ...}

-- Call tree for hierarchical view
local call_tree = {}         -- parent_id -> child_id -> count

--============================================================================
-- UTILITIES
--============================================================================

local function format_time(seconds)
  if seconds < 0.000001 then
    return string.format("%7.2f ns", seconds * 1000000000)
  elseif seconds < 0.001 then
    return string.format("%7.2f µs", seconds * 1000000)
  elseif seconds < 1 then
    return string.format("%7.2f ms", seconds * 1000)
  else
    return string.format("%7.2f s ", seconds)
  end
end

-- Cache for source lines (avoid re-reading files)
local source_cache = {}

-- Read a specific line from a source file
local function get_source_line(source, line_num)
  if not source then return nil end
  if source:match("^%[") then return nil end  -- Skip [C], [string], etc.

  -- Strip @ prefix if present (Lua uses @filename for file sources)
  local filepath = source:match("^@(.+)") or source

  if not source_cache[filepath] then
    local lines = {}
    local f = io.open(filepath, "r")
    if f then
      for line in f:lines() do
        lines[#lines + 1] = line
      end
      f:close()
    end
    source_cache[filepath] = lines
  end

  return source_cache[filepath][line_num]
end

-- Extract class:method or module.func name from source line
local function extract_qualified_name(source, line_num, fallback_name)
  local line = get_source_line(source, line_num)
  if not line then return fallback_name end

  -- Match patterns like:
  --   function neo.View:bar(...)   -> View:bar
  --   function Foo:bar(...)        -> Foo:bar
  --   function Foo.bar(...)        -> Foo:bar
  --   Foo.bar = function(...)      -> Foo:bar
  --   local function bar(...)      -> bar

  -- Try "function ...Class:method" - find the last identifier before : and the method after
  local class, method = line:match("function%s+.+%.([%w_]+):([%w_]+)")
  if class and method then
    return class .. ":" .. method
  end

  -- Try "function Class:method" without module prefix
  class, method = line:match("function%s+([%w_]+):([%w_]+)")
  if class and method then
    return class .. ":" .. method
  end

  -- Try "function ...Class.method" (dot instead of colon)
  class, method = line:match("function%s+.+%.([%w_]+)%.([%w_]+)%s*%(")
  if class and method then
    return class .. ":" .. method
  end

  -- Try "function Class.method" without module prefix
  class, method = line:match("function%s+([%w_]+)%.([%w_]+)%s*%(")
  if class and method then
    return class .. ":" .. method
  end

  -- Try "Class.method = function"
  class, method = line:match("([%w_]+)%.([%w_]+)%s*=%s*function")
  if class and method then
    return class .. ":" .. method
  end

  -- Try "local function name"
  local local_func = line:match("local%s+function%s+([%w_]+)")
  if local_func then
    return local_func
  end

  -- Try standalone "function name"
  local standalone = line:match("^%s*function%s+([%w_]+)%s*%(")
  if standalone then
    return standalone
  end

  return fallback_name
end

-- Get clean function name from debug info
local function get_func_name(info)
  if info.name and info.name ~= "" then
    return info.name
  elseif info.what == "main" then
    return "[main]"
  elseif info.what == "C" then
    return "[C]"
  else
    return "[anon]"
  end
end

-- Get full function identifier with qualified name
local function get_func_id(info)
  local source = info.short_src or "?"
  local filename = source:match("([^/\\]+)$") or source
  local line_num = info.linedefined or 0

  -- Try to get qualified name (Class:method) from source
  local base_name = get_func_name(info)
  local qualified_name = extract_qualified_name(info.source, line_num, base_name)

  return string.format("%s:%d:%s", filename, line_num, qualified_name)
end

-- Capture current call stack as a string "func1;func2;func3"
local function capture_stack(max_depth)
  max_depth = max_depth or 20
  local stack = {}

  for level = 2, max_depth + 2 do
    local info = debug.getinfo(level, "nSl")
    if not info then break end

    -- Skip profiler internals
    local source = info.short_src or ""
    local dominated = source:match("profiler%.lua$")

    -- Skip C functions unless they have names
    local skip_c = info.what == "C" and not info.name

    if not dominated and not skip_c then
      local name = get_func_name(info)
      if info.currentline and info.currentline > 0 then
        name = name .. ":" .. info.currentline
      end

      table.insert(stack, 1, name)  -- Prepend (bottom of stack first)
    end
  end

  return table.concat(stack, ";")
end

--============================================================================
-- SAMPLING MODE
-- Low overhead: samples the call stack every N VM instructions
--============================================================================

local function sampling_hook()
  if not enabled then return end

  local stack_str = capture_stack(30)
  if stack_str ~= "" then
    sample_count = sample_count + 1
    stack_samples[stack_str] = (stack_samples[stack_str] or 0) + 1
  end
end

function profiler.start_sampling(interval)
  interval = interval or 10000  -- Default: every 10k instructions

  profiler.reset()
  mode = "sampling"
  enabled = true

  -- Hook on instruction count (lower overhead than call/return)
  debug.sethook(sampling_hook, "", interval)
end

--============================================================================
-- MANUAL MODE
-- Zero overhead when disabled, explicit instrumentation
--============================================================================

function profiler.enable()
  profiler.reset()
  mode = "manual"
  enabled = true
end

function profiler.disable()
  enabled = false
end

function profiler.enter(name)
  if not enabled then return end

  table.insert(manual_stack, {
    name = name,
    start_time = get_time(),
    children_time = 0,
  })
end

function profiler.leave()
  if not enabled or #manual_stack == 0 then return end

  local frame = table.remove(manual_stack)
  local elapsed = get_time() - frame.start_time
  local self_time = elapsed - frame.children_time

  -- Update stats
  local stats = manual_stats[frame.name]
  if not stats then
    stats = { calls = 0, total_time = 0, self_time = 0 }
    manual_stats[frame.name] = stats
  end

  stats.calls = stats.calls + 1
  stats.total_time = stats.total_time + elapsed
  stats.self_time = stats.self_time + self_time

  -- Add to parent's children time
  if #manual_stack > 0 then
    manual_stack[#manual_stack].children_time =
      manual_stack[#manual_stack].children_time + elapsed
  end

  -- Record in call tree
  if #manual_stack > 0 then
    local parent = manual_stack[#manual_stack].name
    call_tree[parent] = call_tree[parent] or {}
    call_tree[parent][frame.name] = (call_tree[parent][frame.name] or 0) + 1
  end

  -- Also record collapsed stack for flamegraph
  local stack_parts = {}
  for _, f in ipairs(manual_stack) do
    table.insert(stack_parts, f.name)
  end
  table.insert(stack_parts, frame.name)
  local stack_str = table.concat(stack_parts, ";")
  stack_samples[stack_str] = (stack_samples[stack_str] or 0) + 1
  sample_count = sample_count + 1
end

-- Convenience: wrap a function with enter/leave
function profiler.wrap(name, fn)
  return function(...)
    profiler.enter(name)
    local results = {fn(...)}
    profiler.leave()
    return table.unpack(results)
  end
end

-- Convenience: measure a function N times
function profiler.measure(name, fn, iterations)
  iterations = iterations or 1

  local start = get_time()
  for _ = 1, iterations do
    fn()
  end
  local elapsed = get_time() - start

  print(string.format("%s: %s total, %s per call (%d iterations)",
    name,
    format_time(elapsed),
    format_time(elapsed / iterations),
    iterations))

  return elapsed
end

--============================================================================
-- HOOK MODE
-- Complete instrumentation (high overhead)
--============================================================================

local function hook_handler(event)
  if not enabled then return end

  local now = get_time()

  if event == "call" or event == "tail call" then
    local info = debug.getinfo(2, "nSlf")
    if not info then return end

    -- Skip C functions - their time will be attributed to the parent Lua function
    if info.what == "C" then return end

    local func_id = get_func_id(info)

    if not hook_stats[func_id] then
      hook_stats[func_id] = {
        calls = 0,
        total_time = 0,
        self_time = 0,
        name = get_func_name(info),
        source = info.short_src or "?",
        line = info.linedefined or 0,
      }
    end

    table.insert(hook_stack, {
      func_id = func_id,
      start_time = now,
      children_time = 0,
    })

  elseif event == "return" then
    if #hook_stack == 0 then return end

    local info = debug.getinfo(2, "nSlf")
    if not info then return end

    -- Skip C functions
    if info.what == "C" then return end

    local func_id = get_func_id(info)

    -- Find matching frame
    local found_idx = nil
    for i = #hook_stack, 1, -1 do
      if hook_stack[i].func_id == func_id then
        found_idx = i
        break
      end
    end

    if found_idx then
      local frame = hook_stack[found_idx]

      -- Remove frame and orphans
      for i = #hook_stack, found_idx, -1 do
        table.remove(hook_stack, i)
      end

      local elapsed = now - frame.start_time
      local self_time = elapsed - frame.children_time

      local stats = hook_stats[func_id]
      if stats then
        stats.calls = stats.calls + 1
        stats.total_time = stats.total_time + elapsed
        stats.self_time = stats.self_time + self_time
      end

      -- Add to parent's children time
      if #hook_stack > 0 then
        hook_stack[#hook_stack].children_time =
          hook_stack[#hook_stack].children_time + elapsed
      end

      -- Record call relationship
      if #hook_stack > 0 then
        local parent_id = hook_stack[#hook_stack].func_id
        call_tree[parent_id] = call_tree[parent_id] or {}
        call_tree[parent_id][func_id] = (call_tree[parent_id][func_id] or 0) + 1
      end
    end
  end
end

function profiler.start_hooks(opts)
  opts = opts or {}

  profiler.reset()
  mode = "hooks"
  enabled = true

  debug.sethook(hook_handler, "cr")
end

-- Aliases for backward compatibility
profiler.start = profiler.start_hooks

--============================================================================
-- STOP / RESET
--============================================================================

function profiler.stop()
  debug.sethook()
  enabled = false
end

function profiler.reset()
  enabled = false
  mode = nil
  manual_stack = {}
  manual_stats = {}
  sample_count = 0
  stack_samples = {}
  hook_stack = {}
  hook_stats = {}
  call_tree = {}
end

--============================================================================
-- REPORTS
--============================================================================

-- Get unified stats regardless of mode
local function get_stats()
  if mode == "manual" then
    return manual_stats
  elseif mode == "hooks" then
    return hook_stats
  else
    return {}
  end
end

-- Human-readable report
function profiler.report(sort_by, limit)
  sort_by = sort_by or "self"
  limit = limit or 30

  local stats = get_stats()

  -- Convert to array
  local entries = {}
  for name, s in pairs(stats) do
    table.insert(entries, { name = name, stats = s })
  end

  if #entries == 0 then
    print("\nNo profiling data collected.")
    if mode == "sampling" then
      print(string.format("Sampling mode: %d samples collected", sample_count))
      print("Use profiler.flamegraph() to see sampling results.")
    end
    return
  end

  -- Sort
  local sort_fn
  if sort_by == "calls" then
    sort_fn = function(a, b) return a.stats.calls > b.stats.calls end
  elseif sort_by == "total" then
    sort_fn = function(a, b) return a.stats.total_time > b.stats.total_time end
  elseif sort_by == "avg" then
    sort_fn = function(a, b)
      return (a.stats.total_time / a.stats.calls) > (b.stats.total_time / b.stats.calls)
    end
  else -- "self"
    sort_fn = function(a, b) return a.stats.self_time > b.stats.self_time end
  end
  table.sort(entries, sort_fn)

  -- Calculate total
  local total_self = 0
  for _, e in ipairs(entries) do
    total_self = total_self + e.stats.self_time
  end

  -- Print
  print("")
  print(string.rep("=", 95))
  print(string.format("PROFILER REPORT (sorted by %s, top %d)", sort_by, limit))
  print(string.rep("=", 95))
  print(string.format("%-40s %10s %12s %12s %12s  %%",
    "Function", "Calls", "Total", "Self", "Avg"))
  print(string.rep("-", 95))

  for i, entry in ipairs(entries) do
    if i > limit then break end

    local s = entry.stats
    local avg = s.total_time / s.calls
    local pct = total_self > 0 and (s.self_time / total_self * 100) or 0

    local name = entry.name
    if #name > 39 then
      name = "..." .. name:sub(-36)
    end

    print(string.format("%-40s %10d %12s %12s %12s %5.1f%%",
      name, s.calls, format_time(s.total_time), format_time(s.self_time),
      format_time(avg), pct))
  end

  print(string.rep("-", 95))
  print(string.format("%-40s %10s %12s", "TOTAL", "", format_time(total_self)))
  print(string.rep("=", 95))
end

-- Flamegraph output (collapsed stacks format)
-- Can be visualized with: https://speedscope.app or flamegraph.pl
function profiler.flamegraph(filename)
  if sample_count == 0 then
    print("No samples collected.")
    return
  end

  -- Sort by count descending
  local sorted = {}
  for stack, count in pairs(stack_samples) do
    table.insert(sorted, { stack = stack, count = count })
  end
  table.sort(sorted, function(a, b) return a.count > b.count end)

  local output = {}
  for _, entry in ipairs(sorted) do
    table.insert(output, string.format("%s %d", entry.stack, entry.count))
  end

  local content = table.concat(output, "\n")

  if filename then
    local f = io.open(filename, "w")
    if f then
      f:write(content)
      f:close()
      print(string.format("Flamegraph data written to: %s", filename))
      print("Visualize at: https://speedscope.app (use 'collapsed stacks' format)")
    end
  else
    print("")
    print(string.rep("=", 70))
    print(string.format("FLAMEGRAPH DATA (%d samples, %d unique stacks)",
      sample_count, #sorted))
    print(string.rep("=", 70))
    print("Format: stack;path count")
    print("Visualize at: https://speedscope.app")
    print(string.rep("-", 70))

    -- Show top 20
    for i, entry in ipairs(sorted) do
      if i > 20 then
        print(string.format("... and %d more stacks", #sorted - 20))
        break
      end
      print(string.format("%5d  %s", entry.count, entry.stack))
    end

    print(string.rep("=", 70))
  end

  return content
end

-- Hierarchical call tree
function profiler.tree(root_pattern, max_depth)
  max_depth = max_depth or 4

  local stats = get_stats()

  if next(call_tree) == nil then
    print("\nNo call tree data. Use hooks or manual mode.")
    return
  end

  print("")
  print(string.rep("=", 80))
  print("CALL TREE")
  print(string.rep("=", 80))

  -- Find roots (functions with no parents, or matching pattern)
  local roots = {}
  local has_parent = {}

  for parent, children in pairs(call_tree) do
    for child in pairs(children) do
      has_parent[child] = true
    end
  end

  for name in pairs(stats) do
    if not has_parent[name] then
      if not root_pattern or name:match(root_pattern) then
        table.insert(roots, name)
      end
    end
  end

  -- Sort roots by self time
  table.sort(roots, function(a, b)
    local sa, sb = stats[a], stats[b]
    return (sa and sa.self_time or 0) > (sb and sb.self_time or 0)
  end)

  -- Print tree recursively
  local function print_node(name, depth, prefix)
    if depth > max_depth then return end

    local s = stats[name]
    local time_str = s and format_time(s.self_time) or "?"
    local calls_str = s and tostring(s.calls) or "?"

    print(string.format("%s%s  [%s, %s calls]", prefix, name, time_str, calls_str))

    local children = call_tree[name]
    if children then
      -- Sort children by call count
      local sorted_children = {}
      for child, count in pairs(children) do
        table.insert(sorted_children, { name = child, count = count })
      end
      table.sort(sorted_children, function(a, b) return a.count > b.count end)

      for i, child in ipairs(sorted_children) do
        local is_last = (i == #sorted_children)
        local new_prefix = prefix .. (is_last and "    " or "│   ")
        local branch = is_last and "└── " or "├── "
        print_node(child.name, depth + 1, prefix .. branch)
      end
    end
  end

  for i, root in ipairs(roots) do
    if i > 10 then
      print(string.format("\n... and %d more roots", #roots - 10))
      break
    end
    print_node(root, 0, "")
    print("")
  end

  print(string.rep("=", 80))
end

--============================================================================
-- CONVENIENCE
--============================================================================

-- Profile a single function call
function profiler.profile(fn, mode_type)
  mode_type = mode_type or "hooks"

  profiler.reset()

  if mode_type == "sampling" then
    profiler.start_sampling(1000)
  else
    profiler.start_hooks()
  end

  local results = {fn()}
  profiler.stop()

  return table.unpack(results)
end

-- Quick timing without profiling overhead
function profiler.time(name, fn)
  local start = get_time()
  local results = {fn()}
  local elapsed = get_time() - start
  print(string.format("%s: %s", name, format_time(elapsed)))
  return table.unpack(results)
end

return profiler
