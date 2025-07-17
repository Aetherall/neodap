-- Function-based adapter configuration for testing compatibility
return {
  adapters = {
    custom = function(callback, config)
      -- Simulate async adapter setup
      vim.defer_fn(function()
        callback({
          type = "server",
          host = "127.0.0.1",
          port = 8080
        })
      end, 100)
    end,
    
    node = {
      type = "executable",
      command = "js-debug",
    },
    
    conditional = function(callback, config)
      -- Adapter that depends on configuration
      if config.mode == "attach" then
        callback({
          type = "server",
          host = config.host or "127.0.0.1",
          port = config.port or 9229
        })
      else
        callback({
          type = "executable",
          command = "js-debug",
          args = {config.program}
        })
      end
    end
  },
  configurations = {
    custom = {
      {
        name = "Custom Debug",
        type = "custom",
        request = "launch",
        program = "${workspaceFolder}/app.js"
      }
    },
    javascript = {
      {
        name = "Launch with Function Adapter",
        type = "conditional",
        request = "launch",
        mode = "launch",
        program = "${workspaceFolder}/src/app.js"
      },
      {
        name = "Attach with Function Adapter",
        type = "conditional",
        request = "attach",
        mode = "attach",
        host = "localhost",
        port = 9229
      }
    }
  }
}