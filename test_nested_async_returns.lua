-- Test return values in nested NvimAsync deferred function calls
local NvimAsync = require("neodap.tools.async")
local nio = require("nio")

-- Test deferred functions that return values
local TestA = NvimAsync.defer(function()
    print("TestA: Starting")

    -- Call another deferred function and get its return value
    local resultB = TestB(10)
    print("TestA: TestB returned:", vim.inspect(resultB))

    -- The return should be the actual value, not a poison value
    local sum = resultB + 5
    print("TestA: Can use return value in math:", sum)

    return "A-complete"
end)

TestB = NvimAsync.defer(function(num)
    print("TestB: Starting with num:", num)

    -- Async operation
    nio.sleep(10)

    -- Call another deferred function
    local resultC = TestC(num * 2)
    print("TestB: TestC returned:", vim.inspect(resultC))

    -- Return a computation based on nested result
    local result = num + resultC
    print("TestB: Returning:", result)
    return result
end)

TestC = NvimAsync.defer(function(value)
    print("TestC: Starting with value:", value)

    -- Another async operation
    nio.sleep(5)

    local result = value * 3
    print("TestC: Returning:", result)
    return result
end)

-- -- Test from sync context (should get poison value)
-- print("\n=== Test 1: Call from sync context ===")
-- local syncResult = TestA()
-- print("Sync context received:", type(syncResult), tostring(syncResult))

-- Test accessing the poison value
-- print("\nTrying to use poison value:")
-- local ok, err = pcall(function()
--     local x = syncResult + 1  -- Should trigger warning
-- end)
-- print("Math operation succeeded:", ok)

-- Test from async context (should get real return values)
-- vim.defer_fn(function()
--     print("\n=== Test 2: Call from async context ===")

--     NvimAsync.run(function()
--         print("In async context now")
--         local asyncResult = TestA()
--         print("Async context received:", vim.inspect(asyncResult))
--         print("Type:", type(asyncResult))
--     end)
-- end, 100)

print("\n=== Testing Nested NvimAsync Calls ===")

NvimAsync.run(function()
    print("In async context now")
    local asyncResult = TestA()
    print("Async context received:", vim.inspect(asyncResult))
    print("Type:", type(asyncResult))
end)

-- Give time for all tests to complete
vim.defer_fn(function()
    print("\n=== All tests completed ===")
end, 3000)
