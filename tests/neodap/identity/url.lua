local MiniTest = require("mini.test")
local url = require("neodap.identity.url")

local T = MiniTest.new_set()

--------------------------------------------------------------------------------
-- URL Parsing
--------------------------------------------------------------------------------

T["parse"] = MiniTest.new_set()

T["parse"]["absolute path"] = function()
  local result = url.parse("/sessions")
  MiniTest.expect.equality(result.context, nil)
  MiniTest.expect.equality(result.uri, nil)
  MiniTest.expect.equality(#result.segments, 1)
  MiniTest.expect.equality(result.segments[1].edge, "sessions")
end

T["parse"]["absolute path with key"] = function()
  local result = url.parse("/sessions:xotat")
  MiniTest.expect.equality(#result.segments, 1)
  MiniTest.expect.equality(result.segments[1].edge, "sessions")
  MiniTest.expect.equality(result.segments[1].key, "xotat")
end

T["parse"]["absolute path with numeric key"] = function()
  local result = url.parse("/threads:1")
  MiniTest.expect.equality(result.segments[1].edge, "threads")
  MiniTest.expect.equality(result.segments[1].key, 1)
end

T["parse"]["multi-segment path"] = function()
  local result = url.parse("/sessions/xotat/threads/1")
  MiniTest.expect.equality(#result.segments, 4)
  MiniTest.expect.equality(result.segments[1].edge, "sessions")
  MiniTest.expect.equality(result.segments[2].edge, "xotat")
  MiniTest.expect.equality(result.segments[3].edge, "threads")
  MiniTest.expect.equality(result.segments[4].edge, "1")
end

T["parse"]["path with key syntax"] = function()
  local result = url.parse("/sessions:xotat/threads:1")
  MiniTest.expect.equality(#result.segments, 2)
  MiniTest.expect.equality(result.segments[1].edge, "sessions")
  MiniTest.expect.equality(result.segments[1].key, "xotat")
  MiniTest.expect.equality(result.segments[2].edge, "threads")
  MiniTest.expect.equality(result.segments[2].key, 1)
end

T["parse"]["path with filter"] = function()
  local result = url.parse("/threads(state=stopped)")
  MiniTest.expect.equality(#result.segments, 1)
  MiniTest.expect.equality(result.segments[1].edge, "threads")
  MiniTest.expect.equality(result.segments[1].filter.state, "stopped")
end

T["parse"]["path with boolean filter"] = function()
  local result = url.parse("/breakpoints(enabled=true)")
  MiniTest.expect.equality(result.segments[1].filter.enabled, true)
end

T["parse"]["path with index"] = function()
  local result = url.parse("/sessions[0]")
  MiniTest.expect.equality(result.segments[1].edge, "sessions")
  MiniTest.expect.equality(result.segments[1].index, 0)
end

T["parse"]["path with key and index"] = function()
  local result = url.parse("/sessions:xotat/threads[0]")
  MiniTest.expect.equality(result.segments[1].key, "xotat")
  MiniTest.expect.equality(result.segments[2].edge, "threads")
  MiniTest.expect.equality(result.segments[2].index, 0)
end

--------------------------------------------------------------------------------
-- Contextual Parsing
--------------------------------------------------------------------------------

T["parse"]["context only"] = function()
  local result = url.parse("@frame")
  MiniTest.expect.equality(result.context, "@frame")
  MiniTest.expect.equality(#result.segments, 0)
end

T["parse"]["context with path"] = function()
  local result = url.parse("@frame/scopes")
  MiniTest.expect.equality(result.context, "@frame")
  MiniTest.expect.equality(#result.segments, 1)
  MiniTest.expect.equality(result.segments[1].edge, "scopes")
end

T["parse"]["context with multi-segment path"] = function()
  local result = url.parse("@session/threads/stacks")
  MiniTest.expect.equality(result.context, "@session")
  MiniTest.expect.equality(#result.segments, 2)
  MiniTest.expect.equality(result.segments[1].edge, "threads")
  MiniTest.expect.equality(result.segments[2].edge, "stacks")
end

T["parse"]["debugger context with path"] = function()
  local result = url.parse("@debugger/sessions")
  MiniTest.expect.equality(result.context, "@debugger")
  MiniTest.expect.equality(#result.segments, 1)
  MiniTest.expect.equality(result.segments[1].edge, "sessions")
end

--------------------------------------------------------------------------------
-- URI + Path Parsing
--------------------------------------------------------------------------------

T["parse"]["URI only"] = function()
  local result = url.parse("frame:xotat:42")
  MiniTest.expect.equality(result.uri, "frame:xotat:42")
  MiniTest.expect.equality(result.context, nil)
  MiniTest.expect.equality(#result.segments, 0)
end

T["parse"]["URI with path"] = function()
  local result = url.parse("frame:xotat:42/scopes")
  MiniTest.expect.equality(result.uri, "frame:xotat:42")
  MiniTest.expect.equality(#result.segments, 1)
  MiniTest.expect.equality(result.segments[1].edge, "scopes")
end

T["parse"]["URI with multi-segment path"] = function()
  local result = url.parse("session:xotat/threads:1/stacks")
  MiniTest.expect.equality(result.uri, "session:xotat")
  MiniTest.expect.equality(#result.segments, 2)
  MiniTest.expect.equality(result.segments[1].edge, "threads")
  MiniTest.expect.equality(result.segments[1].key, 1)
  MiniTest.expect.equality(result.segments[2].edge, "stacks")
end

--------------------------------------------------------------------------------
-- Edge Cases
--------------------------------------------------------------------------------

T["parse"]["empty string returns nil"] = function()
  MiniTest.expect.equality(url.parse(""), nil)
end

T["parse"]["nil returns nil"] = function()
  MiniTest.expect.equality(url.parse(nil), nil)
end

--------------------------------------------------------------------------------
-- View Query Building
--------------------------------------------------------------------------------

T["build_view_query"] = MiniTest.new_set()

T["build_view_query"]["single segment"] = function()
  local parsed = url.parse("/sessions")
  local query = url.build_view_query(parsed.segments)

  MiniTest.expect.equality(query.type, "Debugger")
  MiniTest.expect.equality(query.inline, nil)
  MiniTest.expect.equality(query.eager, nil)
  MiniTest.expect.equality(query.edges.sessions ~= nil, true)
  -- Final edge: eager = true, no inline
  MiniTest.expect.equality(query.edges.sessions.inline, nil)
  MiniTest.expect.equality(query.edges.sessions.eager, true)
end

T["build_view_query"]["two segments - first edge is inline/eager"] = function()
  local parsed = url.parse("/sessions/threads")
  local query = url.build_view_query(parsed.segments)

  -- Root cannot have inline/eager
  MiniTest.expect.equality(query.type, "Debugger")
  MiniTest.expect.equality(query.inline, nil)
  MiniTest.expect.equality(query.eager, nil)

  -- First edge (sessions) is intermediate, so inline/eager
  MiniTest.expect.equality(query.edges.sessions.inline, true)
  MiniTest.expect.equality(query.edges.sessions.eager, true)

  -- Final edge (threads) has eager but not inline
  MiniTest.expect.equality(query.edges.sessions.edges.threads.inline, nil)
  MiniTest.expect.equality(query.edges.sessions.edges.threads.eager, true)
end

T["build_view_query"]["index on final segment"] = function()
  local parsed = url.parse("/sessions/threads[0]")
  local query = url.build_view_query(parsed.segments)

  MiniTest.expect.equality(query.edges.sessions.edges.threads.take, 1)
  MiniTest.expect.equality(query.edges.sessions.edges.threads.skip, nil)
end

T["build_view_query"]["index > 0 adds skip"] = function()
  local parsed = url.parse("/sessions/threads[2]")
  local query = url.build_view_query(parsed.segments)

  MiniTest.expect.equality(query.edges.sessions.edges.threads.take, 1)
  MiniTest.expect.equality(query.edges.sessions.edges.threads.skip, 2)
end

T["build_view_query"]["filter on segment"] = function()
  local parsed = url.parse("/sessions/threads(state=stopped)")
  local query = url.build_view_query(parsed.segments)

  local filters = query.edges.sessions.edges.threads.filters
  MiniTest.expect.equality(#filters, 1)
  MiniTest.expect.equality(filters[1].field, "state")
  MiniTest.expect.equality(filters[1].value, "stopped")
end

T["build_view_query"]["key on segment becomes filter"] = function()
  local parsed = url.parse("/sessions:xotat/threads")
  local query = url.build_view_query(parsed.segments)

  local filters = query.edges.sessions.filters
  MiniTest.expect.equality(#filters, 1)
  MiniTest.expect.equality(filters[1].field, "sessionId")
  MiniTest.expect.equality(filters[1].value, "xotat")
end

T["build_view_query"]["index on intermediate segment"] = function()
  local parsed = url.parse("/sessions/threads[0]/stack/frames")
  local query = url.build_view_query(parsed.segments)

  -- Intermediate threads has take=1
  MiniTest.expect.equality(query.edges.sessions.edges.threads.take, 1)
  MiniTest.expect.equality(query.edges.sessions.edges.threads.inline, true)
  MiniTest.expect.equality(query.edges.sessions.edges.threads.eager, true)

  -- "stack" is now a direct edge (neograph exposes rollups as edges)
  local stack = query.edges.sessions.edges.threads.edges.stack
  MiniTest.expect.equality(stack.inline, true)
  MiniTest.expect.equality(stack.eager, true)

  -- Final frames has no take (unless specified)
  local frames = stack.edges.frames
  MiniTest.expect.equality(frames.take, nil)
  MiniTest.expect.equality(frames.inline, nil)
end

T["build_view_query"]["deep path all intermediates inline/eager"] = function()
  local parsed = url.parse("/sessions/threads/stack/frames")
  local query = url.build_view_query(parsed.segments)

  -- Root cannot have inline/eager
  MiniTest.expect.equality(query.inline, nil)
  MiniTest.expect.equality(query.eager, nil)

  -- sessions (intermediate)
  MiniTest.expect.equality(query.edges.sessions.inline, true)
  MiniTest.expect.equality(query.edges.sessions.eager, true)

  -- threads (intermediate)
  MiniTest.expect.equality(query.edges.sessions.edges.threads.inline, true)
  MiniTest.expect.equality(query.edges.sessions.edges.threads.eager, true)

  -- "stack" is now a direct edge (neograph exposes rollups as edges)
  local stack = query.edges.sessions.edges.threads.edges.stack
  MiniTest.expect.equality(stack.inline, true)
  MiniTest.expect.equality(stack.eager, true)

  -- frames (final) - has eager but not inline
  local frames = stack.edges.frames
  MiniTest.expect.equality(frames.inline, nil)
  MiniTest.expect.equality(frames.eager, true)
end

T["build_view_query"]["complex filter and index"] = function()
  local parsed = url.parse("/sessions/threads(state=stopped)[0]/stack/frames[0]")
  local query = url.build_view_query(parsed.segments)

  -- threads: filter + take + inline/eager
  local threads = query.edges.sessions.edges.threads
  MiniTest.expect.equality(threads.inline, true)
  MiniTest.expect.equality(threads.eager, true)
  MiniTest.expect.equality(threads.take, 1)
  MiniTest.expect.equality(threads.filters[1].field, "state")
  MiniTest.expect.equality(threads.filters[1].value, "stopped")

  -- "stack" is now a direct edge (neograph exposes rollups as edges)
  local stack = threads.edges.stack
  MiniTest.expect.equality(stack.inline, true)
  MiniTest.expect.equality(stack.eager, true)

  -- frames: just take (final segment)
  local frames = stack.edges.frames
  MiniTest.expect.equality(frames.take, 1)
  MiniTest.expect.equality(frames.inline, nil)
end

T["build_view_query"]["deep path with plural stacks edge"] = function()
  -- Note: "stacks" (plural) is a direct edge, not the "stack" rollup
  local parsed = url.parse("/sessions/threads/stacks/frames")
  local query = url.build_view_query(parsed.segments)

  -- Root
  MiniTest.expect.equality(query.type, "Debugger")

  -- sessions (intermediate)
  MiniTest.expect.equality(query.edges.sessions.inline, true)
  MiniTest.expect.equality(query.edges.sessions.eager, true)

  -- threads (intermediate)
  MiniTest.expect.equality(query.edges.sessions.edges.threads.inline, true)
  MiniTest.expect.equality(query.edges.sessions.edges.threads.eager, true)

  -- stacks (direct edge, intermediate) - NOT the rollup
  local stacks = query.edges.sessions.edges.threads.edges.stacks
  MiniTest.expect.no_equality(stacks, nil)
  MiniTest.expect.equality(stacks.inline, true)
  MiniTest.expect.equality(stacks.eager, true)

  -- frames (final)
  local frames = stacks.edges.frames
  MiniTest.expect.no_equality(frames, nil)
  MiniTest.expect.equality(frames.inline, nil)
  MiniTest.expect.equality(frames.eager, true)
end

return T
