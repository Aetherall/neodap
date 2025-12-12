-- TreeSitter-based string highlighter for DAP variable values
-- Parses arbitrary strings (e.g., function bodies, class definitions, object previews)
-- using TreeSitter and returns {text, hl} segments for the render engine.
--
-- Caches parser and query objects per language for performance.
-- Falls back gracefully when a TreeSitter parser is not installed.

local M = {}
local log = require("neodap.logger")

-- Per-language cache: { parser = ..., query = ... } or false (unavailable)
local cache = {}

---Get or create cached parser + highlights query for a language.
---Returns nil if the parser is not available.
---@param lang string TreeSitter language name (e.g., "javascript")
---@return function? parser_fn, table? query
local function get_parser_and_query(lang)
  if cache[lang] == false then return nil, nil end
  if cache[lang] then return cache[lang].parser_fn, cache[lang].query end

  -- Try to get the highlights query (this also validates the parser is installed)
  local ok_q, query = pcall(vim.treesitter.query.get, lang, "highlights")
  if not ok_q or not query then
    log:debug("ts_highlight: no highlights query for lang", { lang = lang, err = tostring(query) })
    cache[lang] = false
    return nil, nil
  end

  log:info("ts_highlight: initialized for lang", { lang = lang })

  -- Store a factory function for string parsers (they can't be reused across different strings)
  cache[lang] = {
    parser_fn = function(text)
      return vim.treesitter.get_string_parser(text, lang)
    end,
    query = query,
  }
  return cache[lang].parser_fn, query
end

---Highlight a string using TreeSitter, returning render-engine-compatible segments.
---@param text string The text to highlight
---@param lang string TreeSitter language name (e.g., "javascript")
---@param fallback_hl string Highlight group for unhighlighted portions
---@return table[] segments Array of { text = string, hl = string }
function M.highlight(text, lang, fallback_hl)
  if not text or text == "" then
    return { { text = text or "", hl = fallback_hl } }
  end

  local parser_fn, query = get_parser_and_query(lang)
  if not parser_fn or not query then
    return { { text = text, hl = fallback_hl } }
  end

  -- Handle ƒ prefix (js-debug function indicator) — not valid JS
  local prefix_seg
  local parse_text = text
  if text:byte(1) == 0xC6 and text:byte(2) == 0x92 then
    -- ƒ is 2-byte UTF-8: 0xC6 0x92
    prefix_seg = { text = "ƒ", hl = "@function" }
    parse_text = text:sub(3) -- strip ƒ for parsing
    if parse_text:sub(1, 1) == " " then
      prefix_seg.text = "ƒ "
      parse_text = parse_text:sub(2)
    end
  end

  if parse_text == "" then
    if prefix_seg then return { prefix_seg } end
    return { { text = text, hl = fallback_hl } }
  end

  -- Parse the text
  local ok, parser = pcall(parser_fn, parse_text)
  if not ok or not parser then
    log:debug("ts_highlight: parser creation failed", { err = tostring(parser) })
    return { { text = text, hl = fallback_hl } }
  end

  local ok2, trees = pcall(function() return parser:parse() end)
  if not ok2 or not trees or not trees[1] then
    log:debug("ts_highlight: parse failed", { err = tostring(trees) })
    return { { text = text, hl = fallback_hl } }
  end

  local root = trees[1]:root()

  -- Collect all captures as (start_col, end_col, hl_group) on the single line
  local captures = {}
  local ok3, err3 = pcall(function()
    for capture_id, node in query:iter_captures(root, parse_text) do
      local sr, sc, er, ec = node:range()
      if sr == 0 then
        local capture_name = "@" .. query.captures[capture_id]
        captures[#captures + 1] = { sc = sc, ec = (er == 0) and ec or #parse_text, hl = capture_name }
      end
    end
  end)

  if not ok3 then
    log:debug("ts_highlight: iter_captures failed", { err = tostring(err3) })
    return { { text = text, hl = fallback_hl } }
  end

  if #captures == 0 then
    -- No captures — return with prefix if present, else fallback
    if prefix_seg then
      return { prefix_seg, { text = parse_text, hl = fallback_hl } }
    end
    return { { text = text, hl = fallback_hl } }
  end

  -- Sort by start position, then by end position descending (innermost/last wins for overlaps)
  table.sort(captures, function(a, b)
    if a.sc ~= b.sc then return a.sc < b.sc end
    return a.ec > b.ec
  end)

  -- Build a highlight map: for each byte position, store the highlight group
  -- Later captures overwrite earlier ones (innermost wins)
  local len = #parse_text
  local hl_map = {}
  for _, cap in ipairs(captures) do
    for pos = cap.sc, cap.ec - 1 do
      if pos < len then
        hl_map[pos] = cap.hl
      end
    end
  end

  -- Walk left-to-right, grouping consecutive bytes with the same highlight
  local segments = {}
  if prefix_seg then segments[#segments + 1] = prefix_seg end

  local pos = 0
  while pos < len do
    local hl = hl_map[pos] or fallback_hl
    local start = pos
    while pos < len and (hl_map[pos] or fallback_hl) == hl do
      pos = pos + 1
    end
    segments[#segments + 1] = { text = parse_text:sub(start + 1, pos), hl = hl }
  end

  return segments
end

return M
