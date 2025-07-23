-- Comprehensive test for nested NvimAsync deferred function calls
local NvimAsync = require("neodap.tools.async")
local nio = require("nio")

-- Flag to track completion
local test_complete = false

-- Create test functions using defer
local TestA = NvimAsync.defer(function()
    print("TestA: Starting in coroutine", coroutine.running())
    local task = nio.current_task()
    print("TestA: Task exists:", task ~= nil)
    
    -- Call another deferred function
    local result = TestB("from A")
    print("TestA: TestB returned:", result)
    
    print("TestA: Completed")
end)

TestB = NvimAsync.defer(function(msg)
    print("TestB: Starting with message:", msg)
    print("TestB: In same coroutine:", coroutine.running())
    local task = nio.current_task()
    print("TestB: Task exists:", task ~= nil)
    
    -- Try an async operation
    print("TestB: Sleeping 50ms...")
    nio.sleep(50)
    print("TestB: Woke up!")
    
    -- Call yet another deferred function
    local result = TestC("from B")
    print("TestB: TestC returned:", result)
    
    print("TestB: Completed")
    return "B done"
end)

TestC = NvimAsync.defer(function(msg)
    print("TestC: Starting with message:", msg)
    print("TestC: In same coroutine:", coroutine.running())
    local task = nio.current_task()
    print("TestC: Task exists:", task ~= nil)
    
    -- Another async operation
    print("TestC: Sleeping 25ms...")
    nio.sleep(25)
    print("TestC: Woke up!")
    
    print("TestC: Completed")
    test_complete = true
    return "C done"
end)

-- Run the test
print("=== Testing Nested NvimAsync Calls ===")
TestA()

-- Check completion after delay
vim.defer_fn(function()
    if test_complete then
        print("=== SUCCESS: All nested calls completed ===")
    else
        print("=== FAILURE: Test did not complete ===")
    end
end, 200)