local rpc = require("dap-client")
local uv = vim.uv or vim.loop

describe("Real Adapters", function()
  -- Helper to find an open port
  local function get_free_port()
    local tcp = uv.new_tcp()
    tcp:bind("127.0.0.1", 0)
    local addr = tcp:getsockname()
    tcp:close()
    return addr.port
  end

  it("should connect to debugpy via unified stdio adapter", function()
    local adapter = rpc.create_adapter({
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local client = adapter.connect()

    local result = nil
    local done = false

    client:request("initialize", {
      adapterID = "test-python",
      clientID = "neostate-test",
      clientName = "Neostate Test",
      pathFormat = "path",
      linesStartAt1 = true,
      columnsStartAt1 = true,
      locale = "en-us"
    }, function(err, res)
      result = res
      done = true
    end)

    vim.wait(5000, function() return done end)

    assert.is_not_nil(result)
    assert.is_nil(result.error)

    client:close()
  end)

  it("should connect to js-debug via unified server adapter", function()
    local adapter = rpc.create_adapter({
      type = "server",
      command = "js-debug",
      args = { "0" },
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        return tonumber(p), h
      end
    })

    local client = adapter.connect()

    local result = nil
    local done = false

    client:request("initialize", {
      adapterID = "test-js",
      clientID = "neostate-test",
      clientName = "Neostate Test",
      pathFormat = "path",
      linesStartAt1 = true,
      columnsStartAt1 = true,
      locale = "en-us"
    }, function(err, res)
      result = res
      done = true
    end)

    vim.wait(5000, function() return done end)

    assert.is_not_nil(result)

    -- Server will auto-terminate when client closes
    client:close()
  end)

  it("should connect to lldb-dap via unified stdio adapter", function()
    -- lldb-vscode (or lldb-dap) is usually just a binary
    local adapter = rpc.create_adapter({
      type = "stdio",
      command = "lldb-dap",
      args = {}
    })

    local client = adapter.connect()
    local result = nil
    local done = false

    client:request("initialize", {
      adapterID = "test-lldb",
      clientID = "neostate-test"
    }, function(err, res)
      result = res
      done = true
    end)

    vim.wait(5000, function() return done end)
    assert.is_not_nil(result)
    client:close()
  end)

  it("should connect to delve via unified server adapter", function()
    -- dlv dap --listen=127.0.0.1:0
    local adapter = rpc.create_adapter({
      type = "server",
      command = "dlv",
      args = { "dap", "--listen=127.0.0.1:0" },
      -- Delve prints "DAP server listening at: 127.0.0.1:36873"
      connect_condition = function(chunk)
        local _, p = chunk:match("DAP server listening at: (.*):(%d+)")
        return tonumber(p)
      end
    })

    local client = adapter.connect()
    local result = nil
    local done = false

    client:request("initialize", {
      adapterID = "test-go",
      clientID = "neostate-test"
    }, function(err, res)
      result = res
      done = true
    end)

    vim.wait(5000, function() return done end)
    assert.is_not_nil(result)
    -- Server will auto-terminate when client closes
    client:close()
  end)

  it("should connect to netcoredbg via unified stdio adapter", function()
    local adapter = rpc.create_adapter({
      type = "stdio",
      command = "netcoredbg",
      args = { "--interpreter=vscode" }
    })

    local client = adapter.connect()
    local result = nil
    local done = false

    client:request("initialize", {
      adapterID = "test-netcore",
      clientID = "neostate-test"
    }, function(err, res)
      result = res
      done = true
    end)

    vim.wait(5000, function() return done end)
    assert.is_not_nil(result)
    client:close()
  end)

  it("should connect to codelldb via unified stdio adapter", function()
    -- Find codelldb in nix store
    local handle = io.popen("find /nix/store -name codelldb -type f -path '*/adapter/codelldb' 2>/dev/null | head -n 1")
    local codelldb_path = handle:read("*a"):gsub("\n", "")
    handle:close()

    if codelldb_path == "" then
      print("Skipping codelldb test: binary not found")
      return
    end

    local adapter = rpc.create_adapter({
      type = "stdio",
      command = codelldb_path,
      args = {}
    })

    local client = adapter.connect()
    local result = nil
    local done = false

    client:request("initialize", {
      adapterID = "test-codelldb",
      clientID = "neostate-test"
    }, function(err, res)
      result = res
      done = true
    end)

    vim.wait(5000, function() return done end)
    assert.is_not_nil(result)
    client:close()
  end)
end)
