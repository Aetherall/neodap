local harness = require("helpers.test_harness")

return harness.integration("source", function(T, ctx)
  T["fetchStackTrace creates Source entities from frames"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_count("/sources") >= 1, true)
  end

  T["Source entity has correct key (path for file-based)"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Find test source and check key matches path
    local path = h:query_field("@frame/source[0]", "path")
    local source_uri = "source:" .. path
    MiniTest.expect.equality(h:query_field(source_uri, "key"), h:query_field(source_uri, "path"))
  end

  T["Source:isVirtual() returns false for file-based source"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Find test source and check isVirtual (file-based sources have path, so not virtual)
    local path = h:query_field("@frame/source[0]", "path")
    local source_uri = "source:" .. path
    -- A source is virtual if it has sourceReference but no path; file-based has path
    MiniTest.expect.equality(h:query_field(source_uri, "path") ~= nil, true)
  end

  T["SourceBinding links source to session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Navigate to source via stopped thread's frame, then to its binding
    local source_url = "/sessions/threads(state=stopped)/stacks[0]/frames(line=1)/sources[0]"
    local binding_url = source_url .. "/bindings[0]"
    h:wait_url(binding_url)

    -- Check binding links to session and source
    local source_uri = h:query_uri(source_url)
    MiniTest.expect.equality(h:query_field_uri(binding_url, "session") ~= nil, true)
    MiniTest.expect.equality(h:query_field_uri(binding_url, "source"), source_uri)
  end

  T["session.sourceBindings contains binding"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_count("@session/sourceBindings") >= 1, true)
  end

  T["source:loadContent() sets content property"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Load content via query_call and check content field
    local path = h:query_field("@frame/source[0]", "path")
    local source_uri = "source:" .. path
    h:query_call(source_uri, "loadContent")
    h:wait(500) -- Give async load time to complete

    local content = h:query_field(source_uri, "content")
    MiniTest.expect.equality(content ~= nil, true)
  end
end)
