-- Entity rendering for tree buffer

-- Truncation limits for display
local LIMITS = {
  value = 50,      -- Variable values
  short = 30,      -- Conditions, log messages, binding messages
  output = 60,     -- Output text
}

---Truncate text with ellipsis
---@param text string
---@param limit number
---@return string
local function truncate(text, limit)
  if #text > limit then
    return text:sub(1, limit - 3) .. "..."
  end
  return text
end

local function build_guides(depth, is_last, active_guides, icons, guide_hl)
  local segs = {}
  for d = 1, depth - 1 do
    if active_guides[d] then
      table.insert(segs, { icons.vertical .. " ", guide_hl.vertical })
    else
      table.insert(segs, { "  ", nil })
    end
  end
  if depth > 0 then
    local char = is_last and icons.corner or icons.junction
    local hl = is_last and guide_hl.corner or guide_hl.junction
    table.insert(segs, { char .. icons.horizontal, hl })
  end
  return segs
end

local function compute_guides(items)
  local n, result, has_future = #items, {}, {}
  for i = n, 1, -1 do
    local depth = items[i].depth or 0
    local is_last = not has_future[depth]
    local active = {}
    for d = 1, depth - 1 do active[d] = has_future[d] or false end
    result[i] = { is_last = is_last, active_guides = active }
    has_future[depth] = true
    for d = depth + 1, depth + 50 do
      if has_future[d] then has_future[d] = nil else break end
    end
  end
  return result
end

-- Entity type renderers (table dispatch)
local renderers = {}

function renderers.Debugger(_, add_cursor)
  add_cursor("Debugger", "DapTreeDebugger")
end

-- State icons: stopped=pause, running=play, terminated/exited=stop
local STATE_ICONS = {
  stopped = { icon = " ⏸", hl = "DapTreeStopped" },
  running = { icon = " ▶", hl = "DapTreeRunning" },
  terminated = { icon = " ⏹", hl = "DapTreeState" },
  exited = { icon = " ⏹", hl = "DapTreeState" },
}
local DEFAULT_STATE = { icon = " ▶", hl = "DapTreeState" }

function renderers.Session(item, add_cursor, add, get)
  add_cursor(get(item, "name", "Session"), "DapTreeSession")
  local state = get(item, "state", "unknown")
  local s = STATE_ICONS[state] or DEFAULT_STATE
  add(s.icon, s.hl)
end

function renderers.Thread(item, add_cursor, add, get)
  local tid = get(item, "threadId", 0)
  add(string.format("Thread %d", tid), "DapTreeCount")
  add(": ", "DapTreePunctuation")
  add_cursor(get(item, "name", "Thread"), "DapTreeThread")
  local state = get(item, "state", "unknown")
  local s = STATE_ICONS[state] or DEFAULT_STATE
  add(s.icon, s.hl)
end

function renderers.Stack(item, add_cursor, _, get)
  add_cursor(string.format("Stack [%d]", get(item, "index", 0)), "DapTreeStack")
end

function renderers.Frame(item, add_cursor, add, get)
  add_cursor(get(item, "name", "frame"), "DapTreeFrame")
  add(":", "DapTreePunctuation")
  add(tostring(get(item, "line", 0)), "DapTreeLineNum")
end

function renderers.Scope(item, add_cursor, _, get)
  add_cursor(get(item, "name", "Scope"), "DapTreeScope")
end

function renderers.Variable(item, add_cursor, add, get)
  add_cursor(get(item, "name", "?"), "DapTreeVariable")
  local vtype = get(item, "varType", "")
  if vtype ~= "" then add(": ", "DapTreePunctuation"); add(vtype, "DapTreeType") end
  add(" = ", "DapTreePunctuation")
  local val = tostring(get(item, "value", "")):gsub("\n", " ")
  add(truncate(val, LIMITS.value), "DapTreeValue")
end

function renderers.Breakpoint(item, add_cursor, add, get, db)
  local entity = db:get(item.id)
  -- Determine breakpoint icon based on state (matches breakpoint_signs.lua)
  local icon, icon_hl = "●", "DapTreeState"  -- unbound default
  if entity then
    local enabled = entity.enabled and entity.enabled:get()
    if enabled == false then
      icon, icon_hl = "○", "DapTreePunctuation"  -- disabled
    elseif entity.hitBinding and entity.hitBinding:get() then
      icon, icon_hl = "◆", "DapTreeStopped"  -- hit
    elseif entity.verifiedBinding and entity.verifiedBinding:get() then
      local binding = entity.verifiedBinding:get()
      local bp_line = entity.line and entity.line:get()
      local actual_line = binding.actualLine and binding.actualLine:get()
      if actual_line and bp_line and actual_line ~= bp_line then
        icon, icon_hl = "◐", "DapTreeState"  -- adjusted
      else
        icon, icon_hl = "◉", "DapTreeRunning"  -- bound
      end
    end
  end
  add(icon .. " ", icon_hl)
  local loc = entity and entity:location()
  local filename = loc and vim.fn.fnamemodify(loc.path, ":t") or "?"
  add_cursor(filename, "DapTreeSource")
  add(":", "DapTreePunctuation")
  add(tostring(get(item, "line", 0)), "DapTreeLineNum")
  local log = get(item, "logMessage", "")
  local cond = get(item, "condition", "")
  if log ~= "" then
    add(" ", nil); add("󰍩 ", "DapTreeOutput")
    add(truncate(log, LIMITS.short), "DapTreeOutput")
  elseif cond ~= "" then
    add(" ", nil); add("? ", "DapTreeExpression")
    add(truncate(cond, LIMITS.short), "DapTreeExpression")
  end
end

function renderers.BreakpointBinding(item, add_cursor, add, get, db)
  -- Determine icon based on state (matches breakpoint_signs.lua)
  local icon, icon_hl = "●", "DapTreeState"  -- unbound/pending default
  local hit = get(item, "hit", false)
  local verified = get(item, "verified", false)
  local actual_line = get(item, "actualLine", nil)

  if hit then
    icon, icon_hl = "◆", "DapTreeStopped"  -- hit
  elseif verified then
    -- Check if line was adjusted
    local entity = db:get(item.id)
    local bp = entity and entity.breakpoint and entity.breakpoint:get()
    local bp_line = bp and bp.line and bp.line:get()
    if actual_line and bp_line and actual_line ~= bp_line then
      icon, icon_hl = "◐", "DapTreeState"  -- adjusted
    else
      icon, icon_hl = "◉", "DapTreeRunning"  -- bound/verified
    end
  end
  add_cursor(icon, icon_hl)

  -- Show session name to distinguish bindings
  local node = item.node
  if node then
    local sb = node.sourceBinding and node.sourceBinding:get()
    local session = sb and sb.session and sb.session:get()
    local name = session and session.name and session.name:get()
    if name then
      add(" ", nil)
      add(truncate(name, LIMITS.short), "DapTreeState")
    end
  end
  local line = actual_line
  if line and line > 0 then add(" → ", "DapTreePunctuation"); add("line " .. line, "DapTreeLineNum") end
end

function renderers.Stdio(_, add_cursor) add_cursor("Output", "DapTreeGroup") end
function renderers.Threads(_, add_cursor) add_cursor("Threads", "DapTreeGroup") end
function renderers.Breakpoints(item, add_cursor, add, _, db)
  add_cursor("Breakpoints", "DapTreeGroup")
  local entity = db:get(item.id)
  if entity then
    local debugger = entity.debugger and entity.debugger:get()
    local count = debugger and debugger.breakpointCount and debugger.breakpointCount:get() or 0
    if count > 0 then
      add(" (", "DapTreePunctuation")
      add(tostring(count), "DapTreeCount")
      add(")", "DapTreePunctuation")
    end
  end
end
function renderers.Sessions(item, add_cursor, add, _, db)
  add_cursor("Sessions", "DapTreeGroup")
  local entity = db:get(item.id)
  if entity then
    local debugger = entity.debugger and entity.debugger:get()
    local count = debugger and debugger.rootSessionCount and debugger.rootSessionCount:get() or 0
    if count > 0 then
      add(" (", "DapTreePunctuation")
      add(tostring(count), "DapTreeCount")
      add(")", "DapTreePunctuation")
    end
  end
end
function renderers.Targets(item, add_cursor, add, _, db)
  add_cursor("Targets", "DapTreeGroup")
  local entity = db:get(item.id)
  if entity then
    local debugger = entity.debugger and entity.debugger:get()
    local count = debugger and debugger.leafSessionCount and debugger.leafSessionCount:get() or 0
    if count > 0 then
      add(" (", "DapTreePunctuation")
      add(tostring(count), "DapTreeCount")
      add(")", "DapTreePunctuation")
    end
  end
end

function renderers.Output(item, add_cursor, add, get)
  local cat = get(item, "category", "")
  local cat_map = { stderr = { "[err] ", "DapTreeStopped" }, stdout = { "[out] ", "DapTreeRunning" }, console = { "[dbg] ", "DapTreeState" } }
  if cat_map[cat] then add(cat_map[cat][1], cat_map[cat][2]) end
  local text = get(item, "text", ""):gsub("\n", " "):gsub("%s+", " ")
  add_cursor(truncate(text, LIMITS.output), "DapTreeOutput")
end

local function render_item(item, icons, guide_hl, is_last, active_guides, get_prop, db)
  local arr = {}
  local function add(text, hl, ext) table.insert(arr, { text, hl, ext }) end
  local function add_cursor(text, hl) add(text, hl, { { id = "cursor", opts = {} } }) end

  for _, seg in ipairs(build_guides(item.depth or 0, is_last, active_guides, icons, guide_hl)) do
    add(seg[1], seg[2])
  end

  local icon = item.expanded and icons.expanded or icons.collapsed
  local icon_hl = item.expanded and guide_hl.expanded or guide_hl.collapsed
  add(icon .. " ", icon_hl)

  local etype = get_prop(item, "type", "Unknown")
  if icons[etype] and icons[etype] ~= "" then add(icons[etype] .. " ", "DapTreeIcon") end

  local renderer = renderers[etype]
  if renderer then
    renderer(item, add_cursor, add, get_prop, db)
  else
    add_cursor(etype .. " #" .. tostring(item.id or "?"))
  end

  return { type = "render_array", render_array = arr }
end

local function process_array(data, line_idx)
  local parts, hls, col, cursor_col = {}, {}, 0, nil
  for _, seg in ipairs(data.render_array) do
    local txt = seg[1] or ""
    table.insert(parts, txt)
    if seg[2] then table.insert(hls, { line = line_idx, group = seg[2], col_start = col, col_end = col + #txt }) end
    if seg[3] then for _, ext in ipairs(seg[3]) do if ext.id == "cursor" then cursor_col = col end end end
    col = col + #txt
  end
  return table.concat(parts), hls, cursor_col
end

return {
  build_guides = build_guides,
  compute_guides = compute_guides,
  render_item = render_item,
  process_array = process_array,
}
