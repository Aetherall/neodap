-- Plugin: DapStep command for stepping through debug sessions
-- Flexible argument order: :DapStep [method] [granularity] [uri]

local neostate = require("neostate")
local dap_uri_picker = require("neodap.plugins.dap_uri_picker")

---@class DapStepConfig
---@field multi_thread? "context"|"pick" Behavior when multiple threads (default: "context")

local default_config = {
  multi_thread = "context", -- "context" uses @thread, "pick" shows picker
}

local methods = { "over", "into", "out" }
local granularities = { "statement", "line", "instruction" }

local method_map = {
  over = "step_over",
  into = "step_into",
  out = "step_out",
}

---Parse command arguments (flexible order)
---@param args string[]
---@return string method
---@return string granularity
---@return string? uri
local function parse_args(args)
  local method = nil
  local granularity = nil
  local uri = nil

  for _, arg in ipairs(args) do
    if vim.tbl_contains(methods, arg) then
      method = arg
    elseif vim.tbl_contains(granularities, arg) then
      granularity = arg
    elseif arg:match("^dap:") or arg:match("^@") then
      uri = arg
    end
  end

  return method or "over", granularity or "line", uri
end

---@param debugger Debugger
---@param config? DapStepConfig
---@return function cleanup
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})
  local picker = dap_uri_picker(debugger)

  ---Execute step on a thread (async)
  ---@param thread Thread
  ---@param method string
  ---@param granularity string
  local function do_step(thread, method, granularity)
    local step_fn = method_map[method]
    if thread[step_fn] then
      -- Step methods are async, wrap in void coroutine
      neostate.void(function()
        thread[step_fn](thread, granularity)
      end)()
    else
      vim.notify("Unknown step method: " .. method, vim.log.levels.ERROR)
    end
  end

  vim.api.nvim_create_user_command("DapStep", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local method, granularity, uri = parse_args(args)

    -- Determine URI based on config and whether one was provided
    if not uri then
      if config.multi_thread == "pick" then
        uri = "dap:session/thread"  -- All threads, will show picker
      else
        uri = "@thread"  -- Context thread
      end
    end

    -- Resolve thread (shows picker if multiple matches)
    picker:resolve(uri, function(thread)
      if thread then
        do_step(thread, method, granularity)
      elseif uri == "@thread" then
        vim.notify("No thread in current context", vim.log.levels.WARN)
      end
    end)
  end, {
    nargs = "*",
    desc = "Step debugger (over/into/out) with optional granularity and thread URI",
    complete = function(arg_lead, cmd_line, cursor_pos)
      local completions = {}

      -- Add methods not already in command
      for _, m in ipairs(methods) do
        if not cmd_line:match("%s" .. m .. "%s") and not cmd_line:match("%s" .. m .. "$") then
          if m:match("^" .. vim.pesc(arg_lead)) then
            table.insert(completions, m)
          end
        end
      end

      -- Add granularities not already in command
      for _, g in ipairs(granularities) do
        if not cmd_line:match("%s" .. g .. "%s") and not cmd_line:match("%s" .. g .. "$") then
          if g:match("^" .. vim.pesc(arg_lead)) then
            table.insert(completions, g)
          end
        end
      end

      -- Add URI patterns if arg_lead looks like start of URI
      if arg_lead == "" or arg_lead:match("^[@d]") then
        if not cmd_line:match("@") and not cmd_line:match("dap:") then
          table.insert(completions, "@thread")
          table.insert(completions, "@session/thread")
        end
      end

      return completions
    end,
  })

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    pcall(vim.api.nvim_del_user_command, "DapStep")
  end)

  -- Return manual cleanup function
  return function()
    pcall(vim.api.nvim_del_user_command, "DapStep")
  end
end
