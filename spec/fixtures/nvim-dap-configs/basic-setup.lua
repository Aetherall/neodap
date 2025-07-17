-- Basic nvim-dap configuration for testing compatibility
return {
  adapters = {
    node = {
      type = "executable",
      command = "js-debug",
    },
    python = {
      type = "server",
      port = 5678,
      executable = {
        command = "python",
        args = {"-m", "debugpy.adapter"}
      }
    }
  },
  configurations = {
    javascript = {
      {
        name = "Launch Node",
        type = "node",
        request = "launch",
        program = "${workspaceFolder}/server.js"
      },
      {
        name = "Debug Tests",
        type = "node",
        request = "launch",
        program = "${workspaceFolder}/test.js"
      }
    },
    python = {
      {
        name = "Launch Python",
        type = "python",
        request = "launch",
        program = "${workspaceFolder}/main.py"
      }
    }
  }
}