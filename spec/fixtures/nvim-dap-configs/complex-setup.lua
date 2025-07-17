-- Complex nvim-dap configuration for testing compatibility with multiple languages
return {
  adapters = {
    node = {
      type = "executable",
      command = "js-debug",
      options = {
        source_filetype = "javascript"
      }
    },
    python = {
      type = "server",
      port = 5678,
      executable = {
        command = "python",
        args = {"-m", "debugpy.adapter"}
      }
    },
    go = {
      type = "server",
      port = "${port}",
      executable = {
        command = "dlv",
        args = {"dap", "-l", "127.0.0.1:${port}"}
      }
    }
  },
  configurations = {
    javascript = {
      {
        name = "Launch Node App",
        type = "node",
        request = "launch",
        program = "${workspaceFolder}/src/app.js",
        cwd = "${workspaceFolder}",
        env = {
          NODE_ENV = "development"
        }
      },
      {
        name = "Attach to Node",
        type = "node",
        request = "attach",
        port = 9229,
        restart = true,
        localRoot = "${workspaceFolder}",
        remoteRoot = "/app"
      }
    },
    python = {
      {
        name = "Launch Python",
        type = "python",
        request = "launch",
        program = "${workspaceFolder}/main.py",
        console = "integratedTerminal"
      },
      {
        name = "Python Module",
        type = "python",
        request = "launch",
        module = "mymodule",
        cwd = "${workspaceFolder}"
      }
    },
    go = {
      {
        name = "Launch Go",
        type = "go",
        request = "launch",
        mode = "debug",
        program = "${workspaceFolder}/main.go"
      }
    }
  }
}