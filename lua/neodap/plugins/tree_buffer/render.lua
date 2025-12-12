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

-- Variable type classification
-- Maps type strings from debug adapters to icon categories.
-- Covers: Python, JavaScript/TypeScript, Go, Rust, C/C++, Java, C#, Lua
local VAR_TYPE_KEYWORDS = {
  string   = { "string", "str", "char", "text", "bytes", "bytearray" },
  number   = { "int", "float", "double", "number", "decimal", "long", "short",
               "byte", "bigint", "complex", "uint", "usize", "isize" },
  boolean  = { "bool", "boolean" },
  array    = { "list", "array", "tuple", "set", "vec", "slice", "sequence",
               "frozenset", "deque", "queue", "stack" },
  object   = { "dict", "map", "object", "table", "hash", "struct", "class",
               "record", "namespace", "module", "type", "enum", "interface",
               "instance", "userdata" },
  ["function"] = { "function", "func", "method", "lambda", "closure",
                   "callable", "builtin_function_or_method", "coroutine",
                   "generator" },
  null     = { "none", "nil", "null", "undefined", "void", "nonetype" },
}

-- Pre-build a reverse lookup: keyword -> category
local _var_type_lookup = {}
for category, keywords in pairs(VAR_TYPE_KEYWORDS) do
  for _, kw in ipairs(keywords) do
    _var_type_lookup[kw] = category
  end
end

--- Classify a variable type string into an icon category.
--- Returns nil if no match (falls back to generic Variable icon).
---@param type_str string? The variable's type (e.g., "int", "str", "list[int]")
---@return string? category One of: string, number, boolean, array, object, function, null
local function classify_var_type(type_str)
  if not type_str or type_str == "" then return nil end
  local lower = type_str:lower()
  -- 1. Try exact match first (fast path for common types)
  if _var_type_lookup[lower] then return _var_type_lookup[lower] end
  -- 2. Try word-boundary match for compound types like "list[int]", "Dict[str, Any]"
  --    Match the first recognized word
  for word in lower:gmatch("[%a_]+") do
    if _var_type_lookup[word] then return _var_type_lookup[word] end
  end
  return nil
end

-- Default tree layouts per entity type
-- Slots can be strings (plain name) or tables with options:
--   prefix    string   Text to prepend (rendered as decoration)
--   suffix    string   Text to append (rendered as decoration)
--   truncate  number   Max text length (adds "..." if exceeded)
--   cursor    boolean  Mark segment as cursor anchor
--   align     string   "right" to render as right-aligned virtual text
--   hl        string   Override the component's highlight group
--   pad_left  number   Spaces to insert before this slot
--   pad_right number   Spaces to insert after this slot
local TREE_LAYOUTS = {
  -- Entity types
  Session  = { "root_session_name", "chain_arrow", { "session_name", cursor = true },
               { "icon", align = "right", pad_left = 1 },
               { "id", align = "right", pad_left = 1 } },
  Thread   = { "id", { "title", prefix = ": ", cursor = true },
               { "icon", align = "right", pad_left = 1 } },
  Frame    = { { "depth_title", cursor = true },
               { "location", align = "right" } },
  Scope    = { { "title", cursor = true } },
  Variable = { { "title", cursor = true },
               { "value", prefix = " = ", truncate = 50 },
               { "type", align = "right", hl = "DapComment" } },
  Breakpoint = { { "icon", suffix = " " }, { "filename", cursor = true },
                 { "line", prefix = ":" },
                 { "condition_icon", align = "right", pad_left = 1, suffix = " " },
                 { "condition", align = "right", truncate = 30 } },
  BreakpointBinding = { { "icon", cursor = true },
                        { "session_name", prefix = " ", truncate = 30 },
                        { "actual_line", align = "right", prefix = " → " },
                        { "override_hint", align = "right" } },
  ExceptionFilter = { { "icon", suffix = " " }, { "title", cursor = true },
                      { "description", align = "right", prefix = " " } },
  ExceptionFilterBinding = { { "icon", suffix = " " }, { "session_name", cursor = true },
                             { "condition", align = "right", prefix = " if " },
                             { "override_hint", align = "right" } },
  Output = { { "category", suffix = " " }, { "title", cursor = true }, "repeat_badge" },
  -- Config (groups sessions from same launch action)
  Config = { { "state", suffix = " " }, { "title", cursor = true },
             { "count", align = "right" }, { "view_mode", align = "right" } },
  -- Group types
  Debugger = { { "title", cursor = true } },
  Stack    = { { "title", cursor = true } },
  Threads  = { { "title", cursor = true } },
  Stdio    = { { "title", cursor = true }, { "count", align = "right" } },
  Breakpoints = { { "title", cursor = true }, { "count", align = "right" } },
  Configs  = { { "title", cursor = true }, { "count", align = "right" } },
  Sessions = { { "title", cursor = true }, { "count", align = "right" } },
  Targets  = { { "title", cursor = true }, { "count", align = "right" } },
  ExceptionFilterBindings = { { "title", cursor = true }, { "count", align = "right" } },
  ExceptionFilters = { { "title", cursor = true }, { "count", align = "right" } },
  ExceptionFiltersGroup = { { "title", cursor = true }, { "count", align = "right" } },
}

local function render_item(item, icons, guide_hl, is_last, active_guides, get_prop, db, debugger, layouts, icon_highlights, var_type_icons)
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

  -- Variable type icons: replace generic  with type-specific icon
  local used_var_icon = false
  if etype == "Variable" and var_type_icons then
    local entity = db:get(item.id)
    if entity then
      local var_type = entity.displayType and entity:displayType() or nil
      local category = classify_var_type(var_type)
      if category and var_type_icons[category] then
        add(var_type_icons[category].icon .. " ", var_type_icons[category].hl)
        used_var_icon = true
      end
    end
  end

  if not used_var_icon and icons[etype] and icons[etype] ~= "" then
    local type_icon_hl = (icon_highlights and icon_highlights[etype]) or "DapTreeIcon"
    add(icons[etype] .. " ", type_icon_hl)
  end

  local effective = (layouts and layouts[etype]) or TREE_LAYOUTS[etype]
  if not effective then
    add_cursor(etype .. " #" .. tostring(item.id or "?"))
    return { type = "render_array", render_array = arr }
  end

  local right_arr = {}
  local function add_right(text, hl) table.insert(right_arr, { text, hl }) end

  local entity = db:get(item.id)
  if entity and debugger then
    for _, seg in ipairs(debugger:render(entity, effective)) do
      local hl = seg.decoration and "DapTreePunctuation" or seg.hl
      if seg.right_align then
        add_right(seg.text, hl)
      elseif seg.cursor then
        add_cursor(seg.text, hl)
      else
        add(seg.text, hl)
      end
    end
  else
    add_cursor(etype, "DapTreeState")
  end

  return { type = "render_array", render_array = arr, right_array = #right_arr > 0 and right_arr or nil }
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

  -- Build right-aligned virtual text chunks: { {text, hl}, ... }
  local right_virt = nil
  if data.right_array then
    right_virt = {}
    for _, seg in ipairs(data.right_array) do
      right_virt[#right_virt + 1] = { seg[1] or "", seg[2] }
    end
  end

  return table.concat(parts), hls, cursor_col, right_virt
end

return {
  build_guides = build_guides,
  compute_guides = compute_guides,
  render_item = render_item,
  process_array = process_array,
  classify_var_type = classify_var_type,
  TREE_LAYOUTS = TREE_LAYOUTS,
}
