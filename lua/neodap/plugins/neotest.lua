-- Plugin: Neotest strategy for debugging tests via neodap
-- Provides a "neodap" strategy that can be used with neotest
--
-- Usage in neotest config:
--   require("neotest").setup({
--     strategies = {
--       neodap = require("neodap.plugins.neotest").strategy(debugger)
--     }
--   })
--
-- Then run tests with:
--   require("neotest").run.run({ strategy = "neodap" })

local neostate = require("neostate")

local M = {}

---Create a neotest strategy that uses neodap for debugging
---@param debugger Debugger The neodap debugger instance
---@return fun(spec: table, context: table): table? strategy function
function M.strategy(debugger)
  ---@param spec table RunSpec from neotest adapter
  ---@param context table Context with adapter and position info
  ---@return table? Process interface or nil if not supported
  return function(spec, context)
    -- spec.strategy contains the DAP-like config from the adapter
    local dap_config = spec.strategy
    if not dap_config then
      vim.notify("[neodap] No strategy config provided", vim.log.levels.WARN)
      return nil
    end

    -- State tracking
    local session = nil
    local exit_code = nil
    local is_complete = false
    local start_error = nil
    local output_file = vim.fn.tempname()
    local output_fd = nil
    local output_queue = {}
    local output_subscribers = {}

    -- Open output file for writing
    local fd, err = vim.uv.fs_open(output_file, "w", 438) -- 0666
    if fd then
      output_fd = fd
    else
      vim.notify("[neodap] Failed to create output file: " .. tostring(err), vim.log.levels.WARN)
    end

    -- Merge env and cwd into the config
    local launch_config = vim.tbl_extend("keep", dap_config, {
      env = spec.env,
      cwd = spec.cwd,
    })

    -- Extract before/after hooks if present
    local before_hook = dap_config.before
    local after_hook = dap_config.after
    launch_config.before = nil
    launch_config.after = nil

    -- Run before hook
    if before_hook then
      launch_config = before_hook(launch_config) or launch_config
    end

    -- Helper to notify subscribers
    local function notify_output(data)
      for _, subscriber in ipairs(output_subscribers) do
        subscriber(data)
      end
    end

    -- Start the debug session asynchronously
    neostate.void(function()
      local ok, result = pcall(function()
        return debugger:start(launch_config)
      end)

      if not ok then
        start_error = tostring(result)
        vim.notify("[neodap] Failed to start debug session: " .. start_error, vim.log.levels.ERROR)
        is_complete = true
        exit_code = 1
        return
      end

      session = result

      -- Subscribe to output events
      session:onOutput(function(output)
        local category = output.category
        -- Capture stdout, stderr, and console output
        if category == "stdout" or category == "stderr" or category == "console" then
          local text = output.output or ""
          -- Write to file
          if output_fd then
            vim.uv.fs_write(output_fd, text, -1)
          end
          -- Add to queue and notify
          table.insert(output_queue, text)
          notify_output(text)
        end
      end)

      -- Subscribe to exited event for exit code
      if session.client then
        session.client:on("exited", function(body)
          exit_code = body.exitCode or 0
        end)
      end

      -- Watch for session termination
      session.state:watch(function(state)
        if state == "terminated" then
          is_complete = true
          -- Close output file
          if output_fd then
            vim.uv.fs_close(output_fd)
            output_fd = nil
          end
          -- Run after hook
          if after_hook then
            after_hook()
          end
          -- Default exit code if not set by exited event
          if exit_code == nil then
            exit_code = 0
          end
        end
      end)
    end)()

    -- Return the Process interface immediately
    -- The session will be started asynchronously
    return {
      ---Check if the process has completed
      ---@return boolean
      is_complete = function()
        return is_complete
      end,

      ---Get an async iterator for output lines
      ---@return fun(): string? async iterator
      output_stream = function()
        local queue_index = 1

        return function()
          -- Return queued data first
          if queue_index <= #output_queue then
            local data = output_queue[queue_index]
            queue_index = queue_index + 1
            return data
          end

          -- If complete, no more data
          if is_complete then
            return nil
          end

          -- Wait for more data (blocking style for neotest's async)
          local new_data = nil
          local callback_id = #output_subscribers + 1
          output_subscribers[callback_id] = function(data)
            new_data = data
          end

          -- Poll until we get data or complete
          vim.wait(30000, function()
            return new_data ~= nil or is_complete
          end, 10)

          output_subscribers[callback_id] = nil
          return new_data
        end
      end,

      ---Get the path to the output file
      ---@return string
      output = function()
        return output_file
      end,

      ---Attach to the running process (open tree buffer)
      attach = function()
        if session then
          vim.cmd("edit dap-tree:session:" .. session.id)
        else
          vim.notify("[neodap] Session not started yet", vim.log.levels.WARN)
        end
      end,

      ---Stop the process
      stop = function()
        if session then
          session:disconnect(true) -- terminate = true
        else
          is_complete = true
          exit_code = 1
        end
      end,

      ---Wait for completion and return exit code
      ---@return integer
      result = function()
        -- Block until complete
        vim.wait(300000, function() -- 5 minute timeout
          return is_complete
        end, 50)
        return exit_code or 1
      end,
    }
  end
end

---Plugin setup function
---@param debugger Debugger
---@return table
return function(debugger)
  -- Store reference to debugger for the strategy
  M._debugger = debugger

  -- Create a convenience function that uses the stored debugger
  M.get_strategy = function()
    return M.strategy(debugger)
  end

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    M._debugger = nil
  end)

  return M
end
