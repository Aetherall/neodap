-- Test vim API calls between async operations in NvimAsync
local NvimAsync = require("neodap.tools.async")
local nio = require("nio")

-- Test functions that mix vim API calls with async operations
local TestVimAPI = NvimAsync.defer(function()
    print("TestVimAPI: Starting")
    
    -- Vim API call before async
    local bufnr = vim.api.nvim_create_buf(false, true)
    print("Created buffer:", bufnr)
    
    -- Set some buffer content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"Line 1", "Line 2", "Line 3"})
    print("Set buffer lines")
    
    -- Async operation
    print("Sleeping 50ms...")
    nio.sleep(50)
    print("Woke up!")
    
    -- More vim API calls after async
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    print("Buffer lines after sleep:", vim.inspect(lines))
    
    -- Modify buffer
    vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, {"Modified Line 2"})
    
    -- Another async operation
    nio.sleep(25)
    
    -- Final vim API call
    local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    print("Final buffer lines:", vim.inspect(final_lines))
    
    -- Clean up
    vim.api.nvim_buf_delete(bufnr, {force = true})
    print("Deleted buffer")
    
    return final_lines
end)

local TestNestedVimAPI = NvimAsync.defer(function()
    print("\nTestNestedVimAPI: Starting")
    
    -- Create a window split
    vim.cmd("vsplit")
    local win_id = vim.api.nvim_get_current_win()
    print("Created window:", win_id)
    
    -- Call another deferred function
    local result = TestVimAPI()
    print("TestVimAPI returned:", vim.inspect(result))
    
    -- More vim API calls
    vim.api.nvim_win_close(win_id, true)
    print("Closed window")
    
    return "nested-complete"
end)

-- Test scheduling and vim.schedule interaction
local TestScheduling = NvimAsync.defer(function()
    print("\nTestScheduling: Starting")
    
    -- Direct vim API call
    local initial_mode = vim.api.nvim_get_mode().mode
    print("Initial mode:", initial_mode)
    
    -- Async operation
    nio.sleep(20)
    
    -- Use vim.schedule inside async context
    local scheduled_executed = false
    vim.schedule(function()
        print("vim.schedule callback executed")
        scheduled_executed = true
    end)
    
    -- Another async operation
    nio.sleep(30)
    
    print("Scheduled executed?", scheduled_executed)
    
    -- Test vim.defer_fn
    local defer_executed = false
    vim.defer_fn(function()
        print("vim.defer_fn callback executed")
        defer_executed = true
    end, 10)
    
    -- Wait for defer_fn
    nio.sleep(20)
    
    print("Defer executed?", defer_executed)
    
    return "scheduling-test-complete"
end)

-- Run tests
print("=== Testing Vim API Calls in NvimAsync ===")

NvimAsync.run(function()
    print("\n--- Test 1: Basic vim API calls ---")
    local result1 = TestVimAPI()
    print("Result 1:", vim.inspect(result1))
    
    print("\n--- Test 2: Nested with vim API ---")
    local result2 = TestNestedVimAPI()
    print("Result 2:", vim.inspect(result2))
    
    print("\n--- Test 3: Scheduling interactions ---")
    local result3 = TestScheduling()
    print("Result 3:", vim.inspect(result3))
    
    print("\n=== All tests completed successfully ===")
end)

-- Give time for everything to complete
vim.defer_fn(function()
    print("\n=== Test script finished ===")
end, 500)