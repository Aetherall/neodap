-- Plugin: DapContext command for setting debug context via URI picker
-- Uses dap_uri_picker to resolve URIs and pins to buffer-local context

local dap_uri_picker = require("neodap.plugins.dap_uri_picker")

---@param debugger Debugger
---@param config? table
---@return function cleanup
return function(debugger, config)
  local picker = dap_uri_picker(debugger)

  vim.api.nvim_create_user_command("DapContext", function(opts)
    local uri = opts.args

    -- Default to session picker if no args
    if uri == "" then
      uri = "dap:session"
    end

    picker:resolve(uri, function(entity)
      if entity and entity.uri then
        -- Pin the current buffer's context (overrides auto_context)
        local bufnr = vim.api.nvim_get_current_buf()
        debugger:context(bufnr):pin(entity.uri)
      end
    end)
  end, {
    nargs = "?",
    desc = "Set debug context from URI (shows picker if multiple matches)",
  })

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    pcall(vim.api.nvim_del_user_command, "DapContext")
  end)

  -- Return manual cleanup function
  return function()
    pcall(vim.api.nvim_del_user_command, "DapContext")
  end
end
