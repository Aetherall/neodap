-- Test error handling in NvimAsync
local NvimAsync = require("neodap.tools.async")
local nio = require("nio")

-- Test function that errors after vim API call
local TestErrorAfterAPI = NvimAsync.defer(function()
    print("TestErrorAfterAPI: Starting")
    
    -- Vim API call
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"Error test"})
    print("Created buffer:", buf)
    
    -- Async operation
    nio.sleep(10)
    
    -- Intentional error
    error("Intentional error after async operation")
    
    -- This should not execute
    print("This should not print")
    vim.api.nvim_buf_delete(buf, {force = true})
end)

-- Test function that calls erroring function
local TestNestedError = NvimAsync.defer(function()
    print("\nTestNestedError: Starting")
    
    -- Try to call function that will error
    local ok, err = pcall(function()
        TestErrorAfterAPI()
    end)
    
    print("pcall result:", ok, err)
    
    -- Continue execution
    print("TestNestedError: Continuing after error")
    
    -- More async operations
    nio.sleep(10)
    
    print("TestNestedError: Completed successfully")
    return "nested-error-handled"
end)

-- Test cleanup after error
local TestCleanupAfterError = NvimAsync.defer(function()
    print("\nTestCleanupAfterError: Starting")
    
    local buffers_created = {}
    
    -- Create some resources
    for i = 1, 3 do
        local buf = vim.api.nvim_create_buf(false, true)
        table.insert(buffers_created, buf)
        print("Created buffer", i, ":", buf)
    end
    
    -- Async operation
    nio.sleep(10)
    
    -- Check if we're still in async context after sleep
    local task = nio.current_task()
    print("Still have task after sleep?", task ~= nil)
    
    -- Clean up (this should work even if previous functions errored)
    for _, buf in ipairs(buffers_created) do
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, {force = true})
            print("Cleaned up buffer:", buf)
        end
    end
    
    return "cleanup-complete"
end)

-- Run tests
print("=== Testing Error Handling in NvimAsync ===")

-- Set panic mode for testing
local original_panic = os.getenv("NEODAP_PANIC")
vim.env.NEODAP_PANIC = "false"  -- Ensure graceful error handling

NvimAsync.run(function()
    print("\n--- Test 1: Error after API call ---")
    local result1 = TestErrorAfterAPI()
    print("Result 1:", result1)  -- Should be nil due to error
    
    print("\n--- Test 2: Nested error handling ---")
    local result2 = TestNestedError()
    print("Result 2:", result2)
    
    print("\n--- Test 3: Cleanup after errors ---")
    local result3 = TestCleanupAfterError()
    print("Result 3:", result3)
    
    print("\n=== Error handling tests completed ===")
end)

-- Restore panic mode
vim.defer_fn(function()
    if original_panic then
        vim.env.NEODAP_PANIC = original_panic
    end
    print("\n=== Test script finished ===")
end, 300)