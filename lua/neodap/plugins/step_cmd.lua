-- Plugin: DapStep command for stepping through debug sessions
--
-- Usage:
--   :DapStep                     - step over focused thread
--   :DapStep over                - step over
--   :DapStep into                - step into
--   :DapStep out                 - step out
--   :DapStep over line           - step over with line granularity
--   :DapStep @session/threads    - step over all threads in session

---@class DapStepConfig
---@field granularity? "statement"|"line"|"instruction" Default granularity (default: "statement")

local default_config = {
  granularity = "statement",
}

local methods = { "over", "into", "out" }
local granularities = { "statement", "line", "instruction" }

local method_map = {
  over = "stepOver",
  into = "stepIn",
  out = "stepOut",
}

---Parse command arguments
---@param args string[]
---@param default_granularity string
---@return string method
---@return string granularity
---@return string? url
local function parse_args(args, default_granularity)
  local method = nil
  local granularity = nil
  local url = nil

  for _, arg in ipairs(args) do
    if vim.tbl_contains(methods, arg) then
      method = arg
    elseif vim.tbl_contains(granularities, arg) then
      granularity = arg
    elseif arg:match("^[@/]") or arg:match("^sessions") or arg:match("^threads") then
      url = arg
    end
  end

  return method or "over", granularity or default_granularity, url
end

local query = require("neodap.plugins.utils.query")
local log = require("neodap.logger")

---@param debugger neodap.entities.Debugger
---@param config? DapStepConfig
---@return table api Plugin API
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local api = {}

  ---Execute step on thread(s)
  ---@param method string "over"|"into"|"out"
  ---@param granularity? string "statement"|"line"|"instruction"
  ---@param url? string Optional URL to query threads
  ---@return boolean success
  function api.step(method, granularity, url)
    granularity = granularity or config.granularity

    local entities = query.query_or_default(debugger, url, function()
      return debugger.ctx.thread:get()
    end)
    if #entities == 0 then
      log:warn("DapStep: No thread found")
      return false
    end

    local step_fn = method_map[method]
    if not step_fn then
      log:error("DapStep: Unknown method", { method = method })
      return false
    end

    local step_opts = { granularity = granularity }
    local count = 0
    for _, entity in ipairs(entities) do
      if entity:type() == "Thread" and entity[step_fn] then
        entity[step_fn](entity, step_opts)
        count = count + 1
      end
    end

    if count > 0 then
      log:info("Step " .. method .. " executed")
      return true
    else
      log:warn("DapStep: No threads to step")
      return false
    end
  end

  ---Step over
  ---@param granularity? string
  ---@param url? string
  function api.step_over(granularity, url)
    return api.step("over", granularity, url)
  end

  ---Step into
  ---@param granularity? string
  ---@param url? string
  function api.step_into(granularity, url)
    return api.step("into", granularity, url)
  end

  ---Step out
  ---@param granularity? string
  ---@param url? string
  function api.step_out(granularity, url)
    return api.step("out", granularity, url)
  end

  vim.api.nvim_create_user_command("DapStep", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local method, granularity, url = parse_args(args, config.granularity)
    api.step(method, granularity, url)
  end, {
    nargs = "*",
    desc = "Step debugger (over/into/out) with optional granularity and URL",
    complete = function(arg_lead, cmd_line)
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

      -- Add URL completions
      local urls = {
        "@session/threads",
        "@session/threads(state=stopped)",
        "sessions/threads",
      }
      for _, u in ipairs(urls) do
        if u:match("^" .. vim.pesc(arg_lead)) then
          table.insert(completions, u)
        end
      end

      return completions
    end,
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapStep")
  end

  return api
end
