-- Tests for multi-root workspace compounds
--
-- Gap #1: Multi-root workspace compounds (fixture exists, zero tests)
--
-- These tests verify:
-- 1. Compound launches configs from different workspace folders
-- 2. stopAll cascades across multi-root compound
-- 3. Config tracks sessions from different folders

local MiniTest = require("mini.test")
local harness = require("helpers.test_harness")

return harness.integration("multi-root compound", function(T, ctx)

  T["compound launches configs from different workspace folders"] = function()
    local h = ctx.create()
    h:fixture("multi-root-workspace")

    h:cmd("DapLaunch Debug Both Apps")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Should have 1 compound Config
    MiniTest.expect.equality(h:query_count("/configs"), 1)
    MiniTest.expect.equality(h:query_field("/configs[0]", "isCompound"), true)
    MiniTest.expect.equality(h:query_field("/configs[0]", "targetCount"), 2)
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")
  end

  T["stopAll cascades across multi-root compound"] = function()
    local h = ctx.create()
    h:fixture("multi-root-workspace")

    h:cmd("DapLaunch Debug Both Apps")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    local session_count = h:query_count("/sessions")

    -- Terminate one session -- stopAll should cascade to all
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")

    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)

    -- All sessions should be terminated
    MiniTest.expect.equality(h:query_count("/sessions(state=terminated)"), session_count)
  end

  T["non-stopAll keeps other sessions running"] = function()
    local h = ctx.create()
    h:fixture("multi-root-workspace")

    h:cmd("DapLaunch Debug Both (no stopAll)")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Terminate one session
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    -- Config should still be active (other session still running)
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")
    MiniTest.expect.equality(h:query_is_nil("/sessions(state=stopped)[0]"), false)
  end

  T["Config terminates when all multi-root sessions end"] = function()
    local h = ctx.create()
    h:fixture("multi-root-workspace")

    h:cmd("DapLaunch Debug Both (no stopAll)")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Terminate first
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    -- Terminate second
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")

    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)
  end

end)
