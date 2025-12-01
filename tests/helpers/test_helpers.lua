-- Test helpers for verified async testing
-- This module provides a wrapper that ensures tests run to completion

local async = require("plenary.async.tests")
local neostate = require("neostate")

local M = {}

--- Verified async test wrapper
--- Tests run in neostate.void() context and must return true
--- If a test doesn't complete within timeout or doesn't return true, it fails
---
--- @param name string Test name
--- @param fn function Test function that must return true
--- @param timeout_ms? number Timeout in milliseconds (default: 30000)
--- @return function Wrapped test function
function M.verified_it(name, fn, timeout_ms)
    timeout_ms = timeout_ms or 30000

    -- Don't use void() or async.it() - both are incompatible with neostate Promises
    -- Instead, run the test function directly in a coroutine that we manually manage
    return it(name, function()
        local completed = false
        local test_error = nil
        local test_result = nil

        -- Create our own coroutine to run the test
        local co = coroutine.create(function()
            local ok, result = pcall(fn)
            if not ok then
                test_error = result
            else
                test_result = result
            end
            completed = true
        end)

        -- Start the coroutine
        local ok, err = coroutine.resume(co)
        if not ok and not completed then
            error("Test failed to start: " .. tostring(err))
        end

        -- Wait for test to complete (Promise system will resume the coroutine)
        local success = vim.wait(timeout_ms, function()
            return completed
        end, 100)

        if not success then
            error(string.format("Test '%s' timed out after %dms", name, timeout_ms))
        end

        if test_error then
            error(test_error)
        end

        if test_result ~= true then
            error(string.format(
                "Test did not return true (got: %s). Tests must return true at completion.",
                tostring(test_result)
            ))
        end
    end)
end

return M
