local nio = require("nio")
local Logger = require("neodap.tools.logger")

local logger = Logger.get("Core:Async")

-- Registry for NvimAsync-managed coroutines
-- Weak keys ensure coroutines are garbage collected when done
local nvim_async_coroutines = setmetatable({}, { __mode = "k" })

-- Store the original nio.current_task before overriding
local original_current_task = nio.current_task

-- Global override to provide nio task context for NvimAsync coroutines
nio.current_task = function()
    local co = coroutine.running()
    if co and nvim_async_coroutines[co] then
        return nvim_async_coroutines[co].task
    end
    return original_current_task()
end

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

    -- Check if we're already in a registered NvimAsync context
    local current_co = coroutine.running()
    if current_co and nvim_async_coroutines[current_co] then
        if isPreempted and isPreempted() then
            print("NVIM_ASYNC: Preempted in nested context")
            return
        end
        -- Already in NvimAsync context, run directly
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

                -- Clean up registry entry on error
                nvim_async_coroutines[co] = nil

                -- Error recovery: By default, we continue gracefully instead of crashing
                -- This prevents erratic plugin behavior from taking down the entire system
                -- Set NEODAP_PANIC=true environment variable to restore original crash behavior for debugging
                local panic_mode = os.getenv("NEODAP_PANIC") == "true"

                if panic_mode then
                    -- Original catastrophic behavior for debugging
                    vim.notify(
                        "CRITICAL FAILURE, INTERRUPTING, check the last log file in the log folder to understand why.")
                    vim.cmd("qa!") -- Quit all
                else
                    -- Graceful recovery - log and continue execution
                    logger:warn("Continuing execution despite error (set NEODAP_PANIC=true to debug)")
                end

                return
            end

            if coroutine.status(co) == "dead" then
                -- Coroutine finished successfully
                -- Clean up registry entry
                nvim_async_coroutines[co] = nil
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
        fake = true,
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

    -- Register this coroutine with its fake task
    nvim_async_coroutines[co] = {
        task = fake_task,
        completed = false
    }

    -- Start the coroutine
    step()

    return fake_task
end

local function current_non_main_co()
    local data = { coroutine.running() }

    if select("#", unpack(data)) == 2 then
        local co, is_main = unpack(data)
        if is_main then
            return nil
        end
        return co
    end

    return unpack(data)
end

--- Creates a fire-and-forget async wrapper for a function
--- Useful for vim autocommands, keybindings, and other sync contexts
--- that need to trigger async operations
---@param func function The function to wrap
---@return function wrapped_func The async wrapper that runs in NvimAsync context
function NvimAsync.defer(func)
    return function(...)
        local args = { ... }
        local co = coroutine.running()

        -- If we're already in a registered NvimAsync context, run directly
        if co and nvim_async_coroutines[co] then
            return func(unpack(args))
        end

        -- Otherwise, create new NvimAsync context
        NvimAsync.run(function()
            func(unpack(args))
        end)
        -- Returns immediately (fire-and-forget)
        -- Return a special value that warns when used
        local warned = false
        local function warn_once()
            if not warned then
                warned = true
                local method_name = debug.getinfo(func, "n").name or "unknown"
                local caller_info = debug.getinfo(3, "Sl")
                local location = caller_info and (caller_info.short_src .. ":" .. caller_info.currentline) or "unknown"

                vim.notify(
                    "⚠️  ASYNC/SYNC MISMATCH: PascalCase method '" ..
                    method_name .. "' called from sync context at " .. location .. ". " ..
                    "Return value is fire-and-forget (nil). Use camelCase for sync methods or nio.wrap() for proper async.",
                    vim.log.levels.WARN
                )
            end
        end

        -- Create a special truthy value that warns when used
        -- This way `if not result` will be false, but any other usage triggers warning
        local poison = setmetatable({ __async_poison = true }, {
            __index = function()
                warn_once(); return nil
            end,
            __newindex = function() warn_once() end,
            __call = function()
                warn_once(); error("Cannot call async method return value")
            end,
            __tostring = function()
                warn_once(); return "ASYNC_FIRE_AND_FORGET"
            end,
            __concat = function()
                warn_once(); return "ASYNC_FIRE_AND_FORGET"
            end,
            __eq = function(a, b)
                if b ~= poison then warn_once() end
                return false
            end,
            __lt = function()
                warn_once(); return false
            end,
            __le = function()
                warn_once(); return false
            end,
            __add = function()
                warn_once(); return 0
            end,
            __sub = function()
                warn_once(); return 0
            end,
            __mul = function()
                warn_once(); return 0
            end,
            __div = function()
                warn_once(); return 0
            end,
            __mod = function()
                warn_once(); return 0
            end,
            __pow = function()
                warn_once(); return 0
            end,
            __unm = function()
                warn_once(); return 0
            end,
            __len = function()
                warn_once(); return 0
            end,
        })

        return poison
    end
end

return NvimAsync
