local nio = require("nio")
local Logger = require("neodap.tools.logger")

local logger = Logger.get("Core:Async")

-- NvimAsync integration for simplified coroutine-based handlers
local NvimAsync = {}

--- Runs a coroutine function in NvimAsync context, enabling direct interleaving
--- of vim.api calls and nio.await calls while preserving NIO context
---@param coroutine_func fun(event: any) A function that contains asynchronous logic
---@param event any The event data to pass to the coroutine
---@param options? table Optional configuration with isPreempted function
function NvimAsync.run(coroutine_func, event, options)
    options = options or {}
    local isPreempted = options.isPreempted

    -- If we're already in a NvimAsync context, check preemption and run directly
    if nio.current_task() then
        if isPreempted and isPreempted() then
            print("NVIM_ASYNC: Preempted in nested context")
            return
        end
        -- print("NVIM_ASYNC: Running in nested context")
        coroutine_func(event)
        return
    end

    -- Custom task runner that implements NIO's yield protocol but resumes in main thread
    local co = coroutine.create(function()
        coroutine_func(event)
    end)

    local cancelled = false

    local function step(...)
        local args = { ... }
        if cancelled or (isPreempted and isPreempted()) then
            print("NVIM_ASYNC: Preempted in step function")
            return
        end

        -- Always resume coroutine in main thread for vim API safety
        vim.schedule(function()
            if cancelled or (isPreempted and isPreempted()) then
                print("NVIM_ASYNC: Preempted in scheduled step")
                return
            end

            local yielded = { coroutine.resume(co, unpack(args)) }
            local success = yielded[1]

            if not success then
                local error_msg = tostring(yielded[2])
                logger:error("NvimAsync coroutine error: " .. error_msg)
                
                -- Error recovery: By default, we continue gracefully instead of crashing
                -- This prevents erratic plugin behavior from taking down the entire system
                -- Set NEODAP_PANIC=true environment variable to restore original crash behavior for debugging
                local panic_mode = os.getenv("NEODAP_PANIC") == "true"
                
                if panic_mode then
                    -- Original catastrophic behavior for debugging
                    vim.notify("CRITICAL FAILURE, INTERRUPTING, check the last log file in the log folder to understand why.")
                    vim.cmd("qa!") -- Quit all
                else
                    -- Graceful recovery - log and continue execution
                    logger:warn("Continuing execution despite error (set NEODAP_PANIC=true to debug)")
                end
                
                return
            end

            if coroutine.status(co) == "dead" then
                -- Coroutine finished successfully
                return
            end

            -- Handle NIO yield protocol: (success, nargs, err_or_fn, ...args)
            local _, nargs, err_or_fn = unpack(yielded)

            if type(err_or_fn) ~= "function" then
                vim.notify("NvimAsync protocol error: expected function, got " .. type(err_or_fn), vim.log.levels.ERROR)
                return
            end

            -- Prepare arguments for the async function
            local async_args = { select(4, unpack(yielded)) }
            async_args[nargs] = step -- Our step function becomes the callback

            -- Call the async operation (this runs in background as normal)
            err_or_fn(unpack(async_args, 1, nargs))
        end)
    end

    -- Create a fake task for nio.current_task() compatibility
    local fake_task = {
        cancel = function()
            cancelled = true
        end,
        preempted = function()
            return cancelled or (isPreempted and isPreempted()) or false
        end,
        trace = function()
            return debug.traceback(co)
        end,
        wait = function()
            error("Cannot wait on NvimAsync task")
        end
    }

    -- Temporarily override nio.current_task for this coroutine
    local original_current_task = nio.current_task
    nio.current_task = function()
        local current_co = coroutine.running()
        if current_co == co then
            return fake_task
        end
        return original_current_task()
    end

    -- Start the coroutine
    step()

    -- Restore after the initial step
    vim.schedule(function()
        nio.current_task = original_current_task
    end)

    return fake_task
end

--- Creates a fire-and-forget async wrapper for a function
--- Useful for vim autocommands, keybindings, and other sync contexts
--- that need to trigger async operations
---@param func function The function to wrap
---@return function wrapped_func The async wrapper that runs in NvimAsync context
function NvimAsync.defer(func)
    return function(...)
        local args = { ... }
        NvimAsync.run(function()
            return func(unpack(args))
        end)
        -- Returns immediately (fire-and-forget)
    end
end

return NvimAsync
