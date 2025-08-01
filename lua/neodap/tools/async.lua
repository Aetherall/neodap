local nio = require("nio")

-- NvimAsync integration for simplified coroutine-based handlers
local NvimAsync = {}

--- Runs a coroutine function in NvimAsync context, enabling direct interleaving
--- of vim.api calls and nio.await calls while preserving NIO context
---@param coroutine_func fun(event: any) A function that contains asynchronous logic
---@param event any The event data to pass to the coroutine
function NvimAsync.run(coroutine_func, event)
  -- If we're already in a NvimAsync context, just run directly
  if nio.current_task() then
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
    if cancelled then
      return
    end
    
    -- Always resume coroutine in main thread for vim API safety
    vim.schedule(function()
      if cancelled then
        return
      end
      
      local yielded = { coroutine.resume(co, unpack(args)) }
      local success = yielded[1]
      
      if not success then
        vim.notify("NvimAsync error: " .. tostring(yielded[2]), vim.log.levels.ERROR)
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
      async_args[nargs] = step  -- Our step function becomes the callback
      
      -- Call the async operation (this runs in background as normal)
      err_or_fn(unpack(async_args, 1, nargs))
    end)
  end
  
  -- Create a fake task for nio.current_task() compatibility
  local fake_task = {
    cancel = function() 
      cancelled = true 
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
end


return NvimAsync