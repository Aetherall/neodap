local Manager              = require("neodap.session.manager")
local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")
local Session              = require("neodap.session.session")
local nio                  = require("nio")
local Api                  = require("neodap.api.Api")
local Logger               = require("neodap.tools.logger")

-- Global cleanup registry to ensure proper test isolation
local _global_cleanup = nil

---@return Api, fun(fixture: string): Session, fun()
local function prepare()
  local log = Logger.get()
  
  -- Automatically call any existing cleanup from previous prepare() call
  if _global_cleanup then
    log:info("PREPARE: Auto-cleaning up from previous prepare() call")
    _global_cleanup()
    _global_cleanup = nil
  end
  
  -- Create fresh instances for each test to ensure complete isolation
  log:info("PREPARE: Creating fresh instances for this test")
  local manager = Manager.create()
  local adapter = ExecutableTCPAdapter.create({
    executable = {
      cmd = "js-debug",
      cwd = vim.fn.getcwd(),
    },
    connection = {
      host = "::1",
    },
  })
  local api = Api.register(manager)
  log:info("PREPARE: Fresh instances created - manager, adapter, and API ready")

  local function start(fixture)
    local session = Session.create({
      manager = manager,
      adapter = adapter,
    })
    
    log:info("PREPARE: Starting session", session.id, "at timestamp", os.clock())

    ---@async
    nio.run(function()
      session:start({
        configuration = {
          type = "pwa-node",
          program = vim.fn.fnamemodify("spec/fixtures/" .. fixture, ":p"),
          cwd = vim.fn.getcwd(),
        },
        request = "launch",
      })
    end)

    return session
  end

  local function cleanup()
    log:info("PREPARE: Cleaning up API and all plugins at timestamp", os.clock())
    
    -- Primary cleanup: API destroy will call plugin destroy methods
    log:info("PREPARE: Calling api:destroy() to trigger plugin cleanup")
    api:destroy()
    
    -- Fallback cleanup: Only clear remaining extmarks if plugin cleanup failed
    log:debug("PREPARE: Checking for any remaining extmarks after plugin cleanup")
    local total_remaining = 0
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        -- Check for remaining extmarks in neodap-related namespaces only
        for ns_id = 1, 50 do  -- Reduced range since proper cleanup should handle most cases
          local extmarks = pcall(vim.api.nvim_buf_get_extmarks, bufnr, ns_id, 0, -1, {})
          if extmarks and type(extmarks) == "table" and #extmarks > 0 then
            total_remaining = total_remaining + #extmarks
            log:warn("PREPARE: Found", #extmarks, "remaining extmarks in namespace", ns_id, "- cleaning up")
            pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)
          end
        end
      end
    end
    
    if total_remaining > 0 then
      log:warn("PREPARE: Fallback cleanup removed", total_remaining, "remaining extmarks")
    else
      log:info("PREPARE: No remaining extmarks found - plugin cleanup was successful")
    end
    
    -- Clear from global registry since we're cleaning up manually
    if _global_cleanup == cleanup then
      _global_cleanup = nil
    end
  end

  -- Register cleanup globally for automatic cleanup on next prepare() call
  _global_cleanup = cleanup

  return api, start, cleanup
end

-- Global cleanup function for manual cleanup without prepare()
local function cleanup_all()
  if _global_cleanup then
    local log = Logger.get()
    log:info("PREPARE: Manual global cleanup called")
    _global_cleanup()
    _global_cleanup = nil
  end
end

-- Export functions
return {
  prepare = prepare,
  cleanup_all = cleanup_all,
}
