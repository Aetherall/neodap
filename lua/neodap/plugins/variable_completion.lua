-- Plugin: DAP completions for variable edit buffers
-- Provides completion using the DAP completions request
-- Uses native completefunc for Neovim integration
-- Triggered via <C-x><C-u> or auto-trigger on configured characters

local neostate = require("neostate")

---@class VariableCompletionConfig
---@field trigger_chars? string[] Characters that trigger completion (default: {".", "[", "("})

local default_config = {
  trigger_chars = { ".", "[", "(" },
}

-- Map DAP completion types to vim complete-item kinds
local type_to_kind = {
  method = "m",
  ["function"] = "f",
  constructor = "f",
  field = "v",
  variable = "v",
  class = "t",
  interface = "t",
  module = "m",
  property = "v",
  unit = "v",
  value = "v",
  enum = "t",
  keyword = "k",
  snippet = "s",
  text = "t",
  color = "v",
  file = "f",
  reference = "v",
  customcolor = "v",
}

-- Store completion functions per buffer for cleanup
local completefuncs = {}

---@param debugger Debugger
---@param config? VariableCompletionConfig
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local group = vim.api.nvim_create_augroup("neodap-variable-completion", { clear = true })

  ---Get frame ID from variable edit buffer
  ---@param bufnr number
  ---@return number? frame_id, Session? session
  local function get_frame_context(bufnr)
    local concrete_uri = vim.b[bufnr].dap_var_concrete_uri
    if not concrete_uri then return nil, nil end

    -- Parse frame ID from URI: dap:session:<sid>/frame:<fid>/scope:...
    local session_id, frame_id = concrete_uri:match("dap:session:([^/]+)/frame:([^/]+)")
    if not session_id or not frame_id then return nil, nil end

    -- Find the session
    local session = nil
    for s in debugger.sessions:iter() do
      if s.id == session_id then
        session = s
        break
      end
    end

    return tonumber(frame_id), session
  end

  ---Fetch completions from DAP
  ---@param bufnr number
  ---@param text string
  ---@param column number 1-indexed column position
  ---@param callback fun(items: table[])
  local function fetch_completions(bufnr, text, column, callback)
    local frame_id, session = get_frame_context(bufnr)

    if not session then
      callback({})
      return
    end

    -- Check if adapter supports completions
    if not session.capabilities or not session.capabilities.supportsCompletionsRequest then
      callback({})
      return
    end

    ---@type dap.CompletionsArguments
    local args = {
      text = text,
      column = column, -- DAP uses 1-indexed columns
      frameId = frame_id,
    }

    -- Use neostate.void to run async request in coroutine context
    neostate.void(function()
      local body, err = neostate.settle(session.client:request("completions", args))

      if err or not body or not body.targets then
        vim.schedule(function() callback({}) end)
        return
      end

      -- Convert DAP completions to vim format
      local items = {}
      for _, target in ipairs(body.targets) do
        local item = {
          word = target.text or target.label,
          abbr = target.label,
          kind = type_to_kind[target.type] or "",
          menu = target.detail or "",
          info = target.detail or "",
          icase = 1,
          dup = 0,
        }
        table.insert(items, item)
      end

      vim.schedule(function() callback(items) end)
    end)()
  end

  ---Find the start position for completion (0-indexed)
  ---@param line string
  ---@param col number 0-indexed cursor column
  ---@return number start 0-indexed start position
  local function find_completion_start(line, col)
    local start = col
    while start > 0 do
      local char = line:sub(start, start)
      if char:match("[%s%(%[%{%,%;%=%+%-%*%/%<>%&%|%!%~%^%%%#]") then
        break
      end
      start = start - 1
    end
    return start
  end

  ---Create a completefunc for a specific buffer
  ---@param bufnr number
  ---@return function completefunc
  local function create_completefunc(bufnr)
    return function(findstart, base)
      if findstart == 1 then
        -- Phase 1: Return start column (0-indexed)
        local line = vim.api.nvim_get_current_line()
        local col = vim.fn.col(".") - 1
        return find_completion_start(line, col)
      else
        -- Phase 2: Return completion items (async)
        local line = vim.api.nvim_get_current_line()
        local col = vim.fn.col(".") - 1
        local start = find_completion_start(line, col)
        local full_text = line:sub(1, col)

        -- Fetch completions asynchronously
        fetch_completions(bufnr, full_text, col + 1, function(items)
          -- Filter by base if we have one
          if base ~= "" then
            local filtered = {}
            local base_lower = base:lower()
            for _, item in ipairs(items) do
              local word_lower = (item.word or ""):lower()
              if word_lower:find(base_lower, 1, true) == 1 then
                table.insert(filtered, item)
              end
            end
            items = filtered
          end

          -- Show completion popup if we have items and still in insert mode
          if #items > 0 and vim.fn.mode():match("^i") then
            vim.schedule(function()
              if vim.fn.mode():match("^i") then
                vim.fn.complete(start + 1, items) -- complete() uses 1-indexed
              end
            end)
          end
        end)

        -- Return empty for now, items will appear via vim.fn.complete()
        return {}
      end
    end
  end

  ---Trigger completion manually (for auto-trigger)
  ---@param bufnr number
  local function trigger_completion(bufnr)
    -- Use feedkeys to trigger <C-x><C-u> in insert mode
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<C-x><C-u>", true, false, true),
      "n",
      false
    )
  end

  -- Setup for variable edit buffers
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = { "dap:*/var:*", "dap:@*/var:*", "dap:*/variable:*", "dap:@*/variable:*" },
    group = group,
    callback = function(opts)
      local bufnr = opts.buf

      -- Create and register completefunc for this buffer
      local fn = create_completefunc(bufnr)
      local fn_name = string.format("_dap_complete_%d", bufnr)
      _G[fn_name] = fn
      completefuncs[bufnr] = fn_name
      vim.bo[bufnr].completefunc = "v:lua." .. fn_name

      -- Setup auto-trigger on certain characters
      if #config.trigger_chars > 0 then
        vim.api.nvim_create_autocmd("InsertCharPre", {
          buffer = bufnr,
          group = group,
          callback = function()
            local char = vim.v.char
            if vim.tbl_contains(config.trigger_chars, char) then
              -- Defer to let the character be inserted first
              vim.defer_fn(function()
                if vim.fn.pumvisible() == 0 and vim.fn.mode():match("^i") then
                  trigger_completion(bufnr)
                end
              end, 50)
            end
          end,
        })
      end
    end,
  })

  -- Cleanup on buffer wipeout
  vim.api.nvim_create_autocmd("BufWipeout", {
    pattern = { "dap:*/var:*", "dap:@*/var:*", "dap:*/variable:*", "dap:@*/variable:*" },
    group = group,
    callback = function(opts)
      local bufnr = opts.buf
      if completefuncs[bufnr] then
        _G[completefuncs[bufnr]] = nil
        completefuncs[bufnr] = nil
      end
    end,
  })

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    for bufnr, fn_name in pairs(completefuncs) do
      _G[fn_name] = nil
    end
    completefuncs = {}
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end)

  -- Return cleanup function
  return function()
    for bufnr, fn_name in pairs(completefuncs) do
      _G[fn_name] = nil
    end
    completefuncs = {}
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
end
