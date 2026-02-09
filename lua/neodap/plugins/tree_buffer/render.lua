-- Entity rendering for tree buffer
--
-- Generic layout engine: dispatches to registered components via TREE_LAYOUTS.
-- All type-specific rendering lives in components.lua.
-- Layout slots support prefix, suffix, truncate, and cursor options.

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

-- Default tree layouts per entity type
-- Slots can be strings (plain name) or tables { name, prefix=, suffix=, truncate=, cursor= }
local TREE_LAYOUTS = {
  -- Entity types
  Session  = { "root_session_name", "chain_arrow", { "session_name", cursor = true },
               { "icon", prefix = " " }, { "id", prefix = " " } },
  Thread   = { "id", { "title", prefix = ": ", cursor = true }, { "icon", prefix = " " } },
  Frame    = { { "depth_title", cursor = true }, { "line", prefix = ":" },
               { "source_name", prefix = "  " } },
  Scope    = { { "title", cursor = true } },
  Variable = { { "title", cursor = true }, { "type", prefix = ": " },
               { "value", prefix = " = ", truncate = 50 } },
  Breakpoint = { { "icon", suffix = " " }, { "filename", cursor = true },
                 { "line", prefix = ":" }, { "condition_icon", prefix = " ", suffix = " " },
                 { "condition", truncate = 30 } },
  BreakpointBinding = { { "icon", cursor = true },
                        { "session_name", prefix = " ", truncate = 30 },
                        { "actual_line", prefix = " → " }, "override_hint" },
  ExceptionFilter = { { "icon", suffix = " " }, { "title", cursor = true },
                      { "description", prefix = " - " } },
  ExceptionFilterBinding = { { "icon", suffix = " " }, { "session_name", cursor = true },
                             { "condition", prefix = " if " }, "override_hint" },
  Output = { { "category", suffix = " " }, { "title", cursor = true } },
  -- Config (groups sessions from same launch action)
  Config = { { "state", suffix = " " }, { "title", cursor = true }, "count", "view_mode" },
  -- Group types
  Debugger = { { "title", cursor = true } },
  Stack    = { { "title", cursor = true } },
  Threads  = { { "title", cursor = true } },
  Stdio    = { { "title", cursor = true }, "count" },
  Breakpoints = { { "title", cursor = true }, "count" },
  Configs  = { { "title", cursor = true }, "count" },
  Sessions = { { "title", cursor = true }, "count" },
  Targets  = { { "title", cursor = true }, "count" },
  ExceptionFilterBindings = { { "title", cursor = true }, "count" },
  ExceptionFilters = { { "title", cursor = true }, "count" },
  ExceptionFiltersGroup = { { "title", cursor = true }, "count" },
}

local function render_item(item, icons, guide_hl, is_last, active_guides, get_prop, db, debugger, layouts)
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

  local effective = (layouts and layouts[etype]) or TREE_LAYOUTS[etype]
  if not effective then
    add_cursor(etype .. " #" .. tostring(item.id or "?"))
    return { type = "render_array", render_array = arr }
  end

  local entity = db:get(item.id)
  if entity and debugger then
    for _, seg in ipairs(debugger:render(entity, effective)) do
      local hl = seg.decoration and "DapTreePunctuation" or seg.hl
      if seg.cursor then
        add_cursor(seg.text, hl)
      else
        add(seg.text, hl)
      end
    end
  else
    add_cursor(etype, "DapTreeState")
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
  TREE_LAYOUTS = TREE_LAYOUTS,
}
