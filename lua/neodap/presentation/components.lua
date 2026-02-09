-- Component registrations (base)
--
-- Populates the component registry with standard display components
-- for all built-in entity types. All components produce flat { text, hl }
-- or nil. Tree-specific arrangement (prefix, suffix, truncation, cursor)
-- lives in the layout configuration and render engine.

local M = {}

-- ========================================================================
-- Constants
-- ========================================================================

-- State -> icon + highlight mapping (Session, Thread)
local STATE_ICONS = {
  stopped = { text = "⏸", hl = "DapStopped" },
  running = { text = "▶", hl = "DapRunning" },
  terminated = { text = "⏹", hl = "DapTerminated" },
  exited = { text = "⏹", hl = "DapTerminated" },
}
local DEFAULT_STATE_ICON = { text = "▶", hl = "DapState" }

-- Breakpoint displayState -> icon + highlight
local BP_ICONS = {
  disabled = { text = "○", hl = "DapBreakpointDisabled" },
  hit = { text = "◆", hl = "DapBreakpointHit" },
  adjusted = { text = "◐", hl = "DapBreakpointAdjusted" },
  verified = { text = "◉", hl = "DapBreakpointVerified" },
  unverified = { text = "●", hl = "DapBreakpointUnverified" },
}

-- Frame presentationHint -> highlight
local FRAME_HL = {
  label = "DapFrameLabel",
  subtle = "DapFrameSubtle",
}

-- DAP Source.presentationHint -> highlight
local SOURCE_HL = {
  emphasize = "DapSourceUser",
  normal = "DapSourceNormal",
  deemphasize = "DapSourceInternal",
}

-- Output category -> dot highlight
local CAT_HL = { stderr = "DapStopped", stdout = "DapRunning", console = "DapState" }

-- Output category -> text highlight
local CAT_TEXT_HL = { stderr = "DapOutputStderr", stdout = "DapOutputStdout", console = "DapOutputConsole" }

-- Language-agnostic keyword sets for output tokenization.
-- Covers JS, Python, Go, Lua, C#, Rust, and other common DAP targets.
local BOOL_KEYWORDS = {
  -- JS/TS, Go, Rust, C/C++, Java
  ["true"] = true, ["false"] = true,
  -- Python
  ["True"] = true, ["False"] = true,
}
local NULL_KEYWORDS = {
  -- JS/TS
  ["null"] = true, ["undefined"] = true,
  -- Python
  ["None"] = true,
  -- Go, Lua
  ["nil"] = true,
  -- C/C++
  ["nullptr"] = true,
  -- Numeric edge cases (JS, Python, etc.)
  ["NaN"] = true, ["Infinity"] = true,
  -- Python
  ["inf"] = true, ["nan"] = true,
}

-- Tokenize DAP output preview text into highlighted segments.
-- Works across languages — recognizes quoted strings, numbers, booleans,
-- null-like keywords, property keys (word: or word=), braces, and
-- collapsed markers ({…}, [...]).
local function tokenize_output(text, fallback_hl)
  local segments = {}
  local pos = 1
  local len = #text

  -- Collect a plain text span from `start` to `pos-1`
  local function flush_plain(start)
    if start < pos then
      segments[#segments + 1] = { text = text:sub(start, pos - 1), hl = fallback_hl }
    end
  end

  local plain_start = 1

  while pos <= len do
    local ch = text:byte(pos)

    -- Single-quoted string: '...'
    if ch == 39 then -- '
      flush_plain(plain_start)
      local end_pos = text:find("'", pos + 1, true)
      if end_pos then
        segments[#segments + 1] = { text = text:sub(pos, end_pos), hl = "DapOutputString" }
        pos = end_pos + 1
      else
        segments[#segments + 1] = { text = text:sub(pos), hl = "DapOutputString" }
        pos = len + 1
      end
      plain_start = pos

    -- Double-quoted string: "..."
    elseif ch == 34 then -- "
      flush_plain(plain_start)
      local end_pos = text:find('"', pos + 1, true)
      if end_pos then
        segments[#segments + 1] = { text = text:sub(pos, end_pos), hl = "DapOutputString" }
        pos = end_pos + 1
      else
        segments[#segments + 1] = { text = text:sub(pos), hl = "DapOutputString" }
        pos = len + 1
      end
      plain_start = pos

    -- Collapsed object/array markers: {…} or […] (js-debug, but harmless elsewhere)
    elseif (ch == 123 or ch == 91) and pos + 2 <= len and text:sub(pos + 1, pos + 3) == "\xe2\x80\xa6" then
      -- {… or [… — the … is 3 bytes (U+2026)
      flush_plain(plain_start)
      local close = ch == 123 and 125 or 93 -- } or ]
      local close_pos = pos + 4 -- after …
      if close_pos <= len and text:byte(close_pos) == close then
        segments[#segments + 1] = { text = text:sub(pos, close_pos), hl = "DapOutputCollapsed" }
        pos = close_pos + 1
      else
        segments[#segments + 1] = { text = text:sub(pos, pos + 3), hl = "DapOutputCollapsed" }
        pos = pos + 4
      end
      plain_start = pos

    -- Braces, brackets, parens: { } [ ] ( )
    elseif ch == 123 or ch == 125 or ch == 91 or ch == 93 then
      flush_plain(plain_start)
      segments[#segments + 1] = { text = text:sub(pos, pos), hl = "DapOutputBrace" }
      pos = pos + 1
      plain_start = pos

    -- Identifier-like: property names (word: or word=), booleans, null keywords
    elseif (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch == 95 or ch == 36 then
      local id_end = pos
      while id_end <= len do
        local c = text:byte(id_end)
        if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95 or c == 36 then
          id_end = id_end + 1
        else
          break
        end
      end
      local word = text:sub(pos, id_end - 1)
      local next_ch = id_end <= len and text:byte(id_end) or 0
      -- Property name: word followed by ':' (JS, Python, Go) or '=' (C#, Rust debug)
      if next_ch == 58 or next_ch == 61 then -- : or =
        flush_plain(plain_start)
        segments[#segments + 1] = { text = word, hl = "DapOutputKey" }
        pos = id_end
        plain_start = pos
      elseif BOOL_KEYWORDS[word] then
        flush_plain(plain_start)
        segments[#segments + 1] = { text = word, hl = "DapOutputBoolean" }
        pos = id_end
        plain_start = pos
      elseif NULL_KEYWORDS[word] then
        flush_plain(plain_start)
        segments[#segments + 1] = { text = word, hl = "DapOutputNull" }
        pos = id_end
        plain_start = pos
      else
        pos = id_end
      end

    -- Numbers: -?[0-9]+\.?[0-9]*
    elseif (ch >= 48 and ch <= 57) or (ch == 45 and pos + 1 <= len and text:byte(pos + 1) >= 48 and text:byte(pos + 1) <= 57) then
      -- Skip if preceded by letter/underscore (part of identifier like "item1")
      local prev = pos > 1 and text:byte(pos - 1) or 32
      if (prev >= 65 and prev <= 90) or (prev >= 97 and prev <= 122) or prev == 95 then
        pos = pos + 1
      else
        flush_plain(plain_start)
        local num_end = pos
        if ch == 45 then num_end = num_end + 1 end
        while num_end <= len and text:byte(num_end) >= 48 and text:byte(num_end) <= 57 do
          num_end = num_end + 1
        end
        -- Decimal point
        if num_end <= len and text:byte(num_end) == 46 then
          num_end = num_end + 1
          while num_end <= len and text:byte(num_end) >= 48 and text:byte(num_end) <= 57 do
            num_end = num_end + 1
          end
        end
        -- Scientific notation (1e10, 2.5E-3)
        local e = num_end <= len and text:byte(num_end)
        if e == 101 or e == 69 then -- e or E
          num_end = num_end + 1
          local sign = num_end <= len and text:byte(num_end)
          if sign == 43 or sign == 45 then num_end = num_end + 1 end -- + or -
          while num_end <= len and text:byte(num_end) >= 48 and text:byte(num_end) <= 57 do
            num_end = num_end + 1
          end
        end
        segments[#segments + 1] = { text = text:sub(pos, num_end - 1), hl = "DapOutputNumber" }
        pos = num_end
        plain_start = pos
      end

    else
      pos = pos + 1
    end
  end

  -- Flush remaining plain text
  flush_plain(plain_start)

  return segments
end

-- ========================================================================
-- Shared helpers
-- ========================================================================

---Helper: count text ` (N)` or ` (enabled/total)`
local function count_text(count)
  if not count or count == 0 then return nil end
  return { text = " (" .. tostring(count) .. ")", hl = "DapTreeCount" }
end

-- ========================================================================
-- Registration
-- ========================================================================

---@param debugger table
function M.register(debugger)
  local rc = debugger.register_component

  -- ======================================================================
  -- Session
  -- ======================================================================

  rc(debugger, "icon", "Session", function(session)
    local state = session:displayState()
    return STATE_ICONS[state] or DEFAULT_STATE_ICON
  end)

  rc(debugger, "title", "Session", function(session)
    return { text = session:chainName() or session.name:get() or "Session", hl = "DapSession" }
  end)

  rc(debugger, "state", "Session", function(session)
    local state = session:displayState()
    local icon = STATE_ICONS[state] or DEFAULT_STATE_ICON
    return { text = state, hl = icon.hl }
  end)

  rc(debugger, "root_session_name", "Session", function(session)
    local has_parent = session.parent and session.parent:get()
    local is_leaf = session.leaf and session.leaf:get()
    if not (has_parent and is_leaf) then return nil end
    local root = session:rootAncestor()
    return { text = root and root.name:get() or "?", hl = "DapSession" }
  end)

  rc(debugger, "chain_arrow", "Session", function(session)
    local has_parent = session.parent and session.parent:get()
    local is_leaf = session.leaf and session.leaf:get()
    if not (has_parent and is_leaf) then return nil end
    local depth = 0
    local s = session
    while s.parent and s.parent:get() do depth = depth + 1; s = s.parent:get() end
    return { text = " " .. string.rep(">", depth) .. " ", hl = "DapComment" }
  end)

  rc(debugger, "session_name", "Session", function(session)
    return { text = session.name:get() or "Session", hl = "DapSession" }
  end)

  rc(debugger, "id", "Session", function(session)
    local id = session.sessionId:get()
    if not id then return nil end
    return { text = ":" .. id, hl = "DapComment" }
  end)

  rc(debugger, "session_id", "Session", function(session)
    local id = session.sessionId:get()
    if not id then return nil end
    return { text = id, hl = "DapComment" }
  end)

  rc(debugger, "thread_count", "Session", function(session)
    local count = session.threadCount:get() or 0
    if count == 0 then return nil end
    return { text = tostring(count), hl = "DapComment" }
  end)

  ---Counter showing [index/total] for multi-session debugging
  ---Only shows when there are 2+ stopped sessions
  rc(debugger, "stopped_counter", "Session", function(session)
    -- Count stopped sessions and find this session's index
    local stopped_sessions = {}
    local session_index = 0
    debugger.sessions:each(function(s)
      if s.state:get() == "stopped" then
        table.insert(stopped_sessions, s)
        if s == session then
          session_index = #stopped_sessions
        end
      end
    end)

    local total = #stopped_sessions
    if total <= 1 then return nil end

    local index_str = session_index > 0 and tostring(session_index) or "?"
    return { text = "[" .. index_str .. "/" .. total .. "]", hl = "DapComment" }
  end)

  -- ======================================================================
  -- Thread
  -- ======================================================================

  rc(debugger, "icon", "Thread", function(thread)
    local state = thread:displayState()
    return STATE_ICONS[state] or DEFAULT_STATE_ICON
  end)

  rc(debugger, "title", "Thread", function(thread)
    return { text = thread.name:get() or "Thread", hl = "DapThread" }
  end)

  rc(debugger, "state", "Thread", function(thread)
    local state = thread:displayState()
    local icon = STATE_ICONS[state] or DEFAULT_STATE_ICON
    return { text = state, hl = icon.hl }
  end)

  rc(debugger, "detail", "Thread", function(thread)
    local id = thread.threadId:get()
    if not id then return nil end
    return { text = "id=" .. tostring(id), hl = "DapComment" }
  end)

  rc(debugger, "id", "Thread", function(thread)
    local tid = thread.threadId:get() or 0
    return { text = string.format("Thread %d", tid), hl = "DapComment" }
  end)

  -- ======================================================================
  -- Frame
  -- ======================================================================

  rc(debugger, "index", "Frame", function(frame)
    local idx = frame.index:get() or 0
    return { text = "#" .. tostring(idx), hl = "DapFrameIndex" }
  end)

  rc(debugger, "title", "Frame", function(frame)
    local name = frame.name:get() or "?"
    local hint = frame.presentationHint:get()
    if hint == vim.NIL then hint = nil end
    local focused = frame.focused and frame.focused:get()
    local hl
    if hint and FRAME_HL[hint] then
      hl = FRAME_HL[hint]
    elseif focused then
      hl = "DapFrameFocused"
    else
      hl = "DapFrame"
    end
    return { text = name, hl = hl }
  end)

  rc(debugger, "location", "Frame", function(frame)
    local loc = frame:location()
    if not loc then return nil end
    local path = loc.path
    local filename = path and vim.fn.fnamemodify(path, ":t") or nil
    if not filename then return nil end
    local line = loc.line or 0
    return { text = filename .. ":" .. tostring(line), hl = "DapSource" }
  end)

  rc(debugger, "depth_title", "Frame", function(frame)
    local hint = frame.presentationHint:get()
    if hint == vim.NIL then hint = nil end
    local focused = frame.focused and frame.focused:get()
    local hl
    if hint == "label" then
      hl = "DapFrameLabel"
    elseif hint == "subtle" then
      hl = "DapFrameSubtle"
    elseif focused then
      hl = "DapFrameFocused"
    else
      hl = "DapFrame" .. math.min(frame.index:get() or 0, 4)
    end
    return { text = frame.name:get() or "frame", hl = hl }
  end)

  rc(debugger, "line", "Frame", function(frame)
    return { text = tostring(frame.line:get() or 0), hl = "DapComment" }
  end)

  rc(debugger, "source_name", "Frame", function(frame)
    local hint = frame.presentationHint:get()
    if hint == vim.NIL then hint = nil end
    if hint == "label" then return nil end

    local source = frame.source and frame.source:get()
    if not source then return nil end

    local path = source.path and source.path:get()
    local name = path and path:match("[^/\\]+$") or (source.name and source.name:get())
    if not name then return nil end

    local src_hint = source.presentationHint and source.presentationHint:get()
    if src_hint == vim.NIL then src_hint = nil end

    return { text = name, hl = SOURCE_HL[src_hint] or SOURCE_HL.normal }
  end)

  -- ======================================================================
  -- Scope
  -- ======================================================================

  rc(debugger, "title", "Scope", function(scope)
    return { text = scope.name:get() or "Scope", hl = "DapScope" }
  end)

  -- ======================================================================
  -- Variable
  -- ======================================================================

  rc(debugger, "title", "Variable", function(var)
    return { text = var.name:get() or "?", hl = "DapVarName" }
  end)

  rc(debugger, "type", "Variable", function(var)
    local t = var:displayType()
    if not t then return nil end
    return { text = t, hl = "DapVarType" }
  end)

  rc(debugger, "value", "Variable", function(var)
    local val = var:displayValue():gsub("\n", " ")
    return { text = val, hl = "DapVarValue" }
  end)

  -- ======================================================================
  -- Breakpoint
  -- ======================================================================

  rc(debugger, "icon", "Breakpoint", function(bp)
    local state = bp:displayState()
    return BP_ICONS[state] or BP_ICONS.unverified
  end)

  rc(debugger, "title", "Breakpoint", function(bp)
    local loc = bp:location()
    if loc then
      local filename = vim.fn.fnamemodify(loc.path or "", ":t")
      local line = loc.line or 0
      return { text = filename .. ":" .. tostring(line), hl = "DapSource" }
    end
    local line = bp.line and bp.line:get() or 0
    return { text = "line " .. tostring(line), hl = "DapSource" }
  end)

  rc(debugger, "state", "Breakpoint", function(bp)
    local state = bp:displayState()
    local icon = BP_ICONS[state] or BP_ICONS.unverified
    return { text = state, hl = icon.hl }
  end)

  rc(debugger, "condition", "Breakpoint", function(bp)
    local cond = bp.condition and bp.condition:get()
    if cond and cond ~= "" then
      return { text = cond, hl = "DapCondition" }
    end
    local log = bp.logMessage and bp.logMessage:get()
    if log and log ~= "" then
      return { text = log, hl = "DapLogMessage" }
    end
    return nil
  end)

  rc(debugger, "filename", "Breakpoint", function(bp)
    local loc = bp:location()
    return { text = loc and vim.fn.fnamemodify(loc.path, ":t") or "?", hl = "DapSource" }
  end)

  rc(debugger, "line", "Breakpoint", function(bp)
    return { text = tostring(bp.line:get() or 0), hl = "DapComment" }
  end)

  rc(debugger, "condition_icon", "Breakpoint", function(bp)
    local cond = bp.condition and bp.condition:get()
    if cond and cond ~= "" then
      return { text = "?", hl = "DapCondition" }
    end
    local log = bp.logMessage and bp.logMessage:get()
    if log and log ~= "" then
      return { text = "󰍩", hl = "DapLogMessage" }
    end
    return nil
  end)

  -- ======================================================================
  -- BreakpointBinding
  -- ======================================================================

  rc(debugger, "icon", "BreakpointBinding", function(binding)
    local hit = binding.hit and binding.hit:get()
    local verified = binding:isVerified()
    local actual_line = binding.actualLine and binding.actualLine:get()

    local enabled_override = binding.enabled:get()
    if enabled_override == vim.NIL then enabled_override = nil end
    local has_override = enabled_override ~= nil

    local effective_enabled = binding:getEffectiveEnabled()

    if not effective_enabled then
      return { text = has_override and "◎" or "○", hl = "DapBreakpointDisabled" }
    elseif hit then
      return { text = "◆", hl = "DapBreakpointHit" }
    elseif verified then
      local bp = binding.breakpoint and binding.breakpoint:get()
      local bp_line = bp and bp.line and bp.line:get()
      if actual_line and bp_line and actual_line ~= bp_line then
        return { text = "◐", hl = "DapBreakpointAdjusted" }
      end
      return { text = has_override and "◉" or "●", hl = "DapBreakpointVerified" }
    end
    return { text = has_override and "◉" or "●", hl = "DapBreakpointUnverified" }
  end)

  rc(debugger, "session_name", "BreakpointBinding", function(binding)
    local sb = binding.sourceBinding and binding.sourceBinding:get()
    local session = sb and sb.session and sb.session:get()
    local name = session and session.name and session.name:get()
    if not name then return nil end
    return { text = name, hl = "DapComment" }
  end)

  rc(debugger, "actual_line", "BreakpointBinding", function(binding)
    local line = binding.actualLine and binding.actualLine:get()
    if not line or line <= 0 then return nil end
    return { text = "line " .. line, hl = "DapComment" }
  end)

  rc(debugger, "override_hint", "BreakpointBinding", function(binding)
    if not binding:hasOverride() then return nil end
    return { text = "(override)", hl = "DapComment" }
  end)

  -- ======================================================================
  -- ExceptionFilter
  -- ======================================================================

  rc(debugger, "icon", "ExceptionFilter", function(ef)
    local enabled = ef:isEnabled()
    if enabled then
      return { text = "●", hl = "DapEnabled" }
    else
      return { text = "○", hl = "DapDisabled" }
    end
  end)

  rc(debugger, "filter_id", "ExceptionFilter", function(ef)
    local id = ef.filterId:get()
    if not id then return nil end
    return { text = id, hl = "DapComment" }
  end)

  rc(debugger, "title", "ExceptionFilter", function(ef)
    return { text = ef.label:get() or ef.filterId:get() or "?", hl = "DapFilter" }
  end)

  rc(debugger, "description", "ExceptionFilter", function(ef)
    local desc = ef.description and ef.description:get()
    if desc == vim.NIL then desc = nil end
    if not desc or desc == "" then return nil end
    return { text = desc, hl = "DapComment" }
  end)

  -- ======================================================================
  -- ExceptionFilterBinding
  -- ======================================================================

  rc(debugger, "icon", "ExceptionFilterBinding", function(binding)
    local enabled = binding:getEffectiveEnabled()
    local has_override = binding:hasOverride()
    if has_override then
      if enabled then
        return { text = "◉", hl = "DapEnabled" }
      else
        return { text = "◎", hl = "DapDisabled" }
      end
    else
      if enabled then
        return { text = "●", hl = "DapEnabled" }
      else
        return { text = "○", hl = "DapDisabled" }
      end
    end
  end)

  rc(debugger, "title", "ExceptionFilterBinding", function(binding)
    return { text = binding:displayLabel(), hl = "DapFilter" }
  end)

  rc(debugger, "condition", "ExceptionFilterBinding", function(binding)
    local cond = binding.condition:get()
    if cond == vim.NIL then cond = nil end
    if not cond or cond == "" then return nil end
    return { text = cond, hl = "DapCondition" }
  end)

  rc(debugger, "session_name", "ExceptionFilterBinding", function(binding)
    local session = binding.session and binding.session:get()
    local name = session and session.name:get()
    if not name or name == vim.NIL then name = "unknown session" end
    return { text = name, hl = "DapFilter" }
  end)

  rc(debugger, "override_hint", "ExceptionFilterBinding", function(binding)
    local enabled_override = binding.enabled:get()
    if enabled_override == vim.NIL then enabled_override = nil end
    if enabled_override == nil then return nil end
    return { text = "(override)", hl = "DapComment" }
  end)

  -- ======================================================================
  -- Output
  -- ======================================================================

  rc(debugger, "category", "Output", function(output)
    local cat = output.category and output.category:get()
    if cat == vim.NIL then cat = nil end
    if not CAT_HL[cat] then return nil end
    return { text = "●", hl = CAT_HL[cat] }
  end)

  rc(debugger, "title", "Output", function(output)
    local text = (output.text and output.text:get() or ""):gsub("\n", " "):gsub("%s+", " ")
    local cat = output.category and output.category:get()
    if cat == vim.NIL then cat = nil end
    local hl = CAT_TEXT_HL[cat] or "DapComment"
    -- Apply syntax highlighting for stdout/stderr output (not console echo)
    if cat == "stdout" or cat == "stderr" then
      local segs = tokenize_output(text, hl)
      if #segs > 1 then
        return { segments = segs }
      end
    end
    return { text = text, hl = hl }
  end)

  -- ======================================================================
  -- Source
  -- ======================================================================

  rc(debugger, "title", "Source", function(source)
    return { text = source:displayName(), hl = "DapSource" }
  end)

  -- ======================================================================
  -- Config (groups sessions from same launch)
  -- ======================================================================

  rc(debugger, "title", "Config", function(config)
    return { text = config:displayName(), hl = "DapTreeGroup" }
  end)
  rc(debugger, "state", "Config", function(config)
    local state = config.state:get()
    return STATE_ICONS[state] or DEFAULT_STATE_ICON
  end)
  rc(debugger, "count", "Config", function(config)
    local target_count = config.targetCount and config.targetCount:get() or 0
    return count_text(target_count)
  end)
  rc(debugger, "view_mode", "Config", function(config)
    local mode = config.viewMode and config.viewMode:get() or "targets"
    if mode == "roots" then
      return { text = " [roots]", hl = "Comment" }
    end
    return nil  -- Don't show anything for default targets mode
  end)

  -- ======================================================================
  -- Group types
  -- ======================================================================

  rc(debugger, "title", "Debugger", function()
    return { text = "Debugger", hl = "DapTreeDebugger" }
  end)

  rc(debugger, "title", "Stack", function(stack)
    local idx = stack.index and stack.index:get() or 0
    return { text = string.format("Stack [%d]", idx), hl = "DapTreeStack" }
  end)

  rc(debugger, "title", "Threads", function()
    return { text = "Threads", hl = "DapTreeGroup" }
  end)

  rc(debugger, "title", "Stdio", function()
    return { text = "Output", hl = "DapTreeGroup" }
  end)
  rc(debugger, "count", "Stdio", function(stdio)
    local session = stdio.session and stdio.session:get()
    return count_text(session and session.outputCount and session.outputCount:get() or 0)
  end)

  rc(debugger, "title", "Breakpoints", function()
    return { text = "Breakpoints", hl = "DapTreeGroup" }
  end)
  rc(debugger, "count", "Breakpoints", function(bp_group)
    local d = bp_group.debugger and bp_group.debugger:get()
    return count_text(d and d.breakpointCount and d.breakpointCount:get() or 0)
  end)

  rc(debugger, "title", "Configs", function()
    return { text = "Configs", hl = "DapTreeGroup" }
  end)
  rc(debugger, "count", "Configs", function(configs_group)
    local d = configs_group.debugger and configs_group.debugger:get()
    return count_text(d and d.activeConfigCount and d.activeConfigCount:get() or 0)
  end)

  -- Legacy: Sessions group
  rc(debugger, "title", "Sessions", function()
    return { text = "Sessions", hl = "DapTreeGroup" }
  end)
  rc(debugger, "count", "Sessions", function(sessions)
    local d = sessions.debugger and sessions.debugger:get()
    return count_text(d and d.rootSessionCount and d.rootSessionCount:get() or 0)
  end)

  -- Legacy: Targets group
  rc(debugger, "title", "Targets", function()
    return { text = "Targets", hl = "DapTreeGroup" }
  end)
  rc(debugger, "count", "Targets", function(targets)
    local d = targets.debugger and targets.debugger:get()
    return count_text(d and d.leafSessionCount and d.leafSessionCount:get() or 0)
  end)

  rc(debugger, "title", "ExceptionFilterBindings", function()
    return { text = "Exception Filters", hl = "DapTreeGroup" }
  end)
  rc(debugger, "count", "ExceptionFilterBindings", function(efb_group)
    local count, enabled = 0, 0
    for binding in efb_group.exceptionFilterBindings:iter() do
      count = count + 1
      if binding:getEffectiveEnabled() then enabled = enabled + 1 end
    end
    return count_text(count > 0 and (tostring(enabled) .. "/" .. tostring(count)) or 0)
  end)

  rc(debugger, "title", "ExceptionFilters", function()
    return { text = "Exception Filters", hl = "DapTreeGroup" }
  end)
  rc(debugger, "count", "ExceptionFilters", function(ef_coll)
    local count = ef_coll.exceptionFilterCount and ef_coll.exceptionFilterCount:get() or 0
    if count == 0 then return nil end
    local enabled = ef_coll.enabledExceptionFilterCount and ef_coll.enabledExceptionFilterCount:get() or 0
    return count_text(tostring(enabled) .. "/" .. tostring(count))
  end)

  rc(debugger, "title", "ExceptionFiltersGroup", function()
    return { text = "Exception Filters", hl = "DapTreeGroup" }
  end)
  rc(debugger, "count", "ExceptionFiltersGroup", function(efg)
    local d = efg.debugger and efg.debugger:get()
    if not d then return nil end
    local count = d.exceptionFilterCount and d.exceptionFilterCount:get() or 0
    if count == 0 then return nil end
    local enabled = d.enabledExceptionFilterCount and d.enabledExceptionFilterCount:get() or 0
    return count_text(tostring(enabled) .. "/" .. tostring(count))
  end)
end

return M
