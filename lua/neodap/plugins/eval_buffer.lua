-- Plugin: Evaluation input buffer for dap-eval: URIs
-- Provides a REPL-style input buffer with DAP completions
--
-- URI format:
--   dap-eval:@frame                    - Use context frame
--   dap-eval:session:<sid>/frame:<fid> - Explicit frame
--   dap-eval:@frame?closeonsubmit      - Close buffer after submit

local neostate = require("neostate")

---@class EvalBufferConfig
---@field trigger_chars? string[] Auto-complete trigger chars (default: {".", "[", "("})
---@field history_size? number Max history entries (default: 100)
---@field on_submit? fun(expression: string, frame: Frame, result: EvaluateResult?, err: any?)

local default_config = {
  trigger_chars = { ".", "[", "(" },
  history_size = 100,
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

---@param debugger Debugger
---@param config? EvalBufferConfig
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local group = vim.api.nvim_create_augroup("neodap-eval-buffer", { clear = true })
  local history = {}  -- Shared history across buffers
  local history_index = {}  -- Per-buffer history position
  local completefuncs = {}  -- Per-buffer completion functions

  ---Parse dap-eval: URI into frame pattern and options
  ---@param uri string
  ---@return string frame_pattern, table options
  local function parse_eval_uri(uri)
    -- Remove dap-eval: prefix
    local path = uri:gsub("^dap%-eval:", "")

    -- Split path and query string
    local frame_pattern, query = path:match("^([^?]+)%??(.*)")
    frame_pattern = frame_pattern or path

    -- Parse query options
    local options = {}
    if query and query ~= "" then
      for param in query:gmatch("[^&]+") do
        local key, value = param:match("([^=]+)=?(.*)")
        if key then
          options[key] = value ~= "" and value or true
        end
      end
    end

    return frame_pattern, options
  end

  ---Check if session is a bootstrap session (has child sessions)
  ---@param session Session
  ---@return boolean
  local function is_bootstrap_session(session)
    for _ in session:children():iter() do
      return true
    end
    return false
  end

  ---Resolve frame from pattern
  ---@param frame_pattern string
  ---@return Frame?
  local function resolve_frame(frame_pattern)
    -- Handle contextual @frame pattern
    if frame_pattern == "@frame" or frame_pattern == "" then
      -- First try buffer-local context
      local frame = debugger:resolve_contextual_one("@frame", "frame"):get()
      if frame then
        -- Check if frame is from a bootstrap session (bootstrap sessions return REPL commands, not code completions)
        local session = frame.stack.thread.session
        if not is_bootstrap_session(session) then
          return frame
        end
        -- Otherwise, fall through to find a non-bootstrap session frame
      end

      -- Fallback: find any stopped frame (useful when eval buffer has no context or context is bootstrap)
      -- Skip bootstrap sessions (sessions with children) - prefer actual debug sessions
      for session in debugger.sessions:iter() do
        if not is_bootstrap_session(session) then
          for thread in session:threads():iter() do
            if thread.state:get() == "stopped" then
              local stack = thread:stack()
              if stack then
                return stack:top()
              end
            end
          end
        end
      end
      return nil
    end

    -- Handle explicit URI pattern like session:<sid>/frame:<fid>
    local full_uri = "dap:" .. frame_pattern
    local frame = debugger:resolve_one(full_uri)
    return frame
  end

  ---Find the start position for completion (0-indexed)
  ---@param line string
  ---@param col number 0-indexed cursor column
  ---@return number start 0-indexed start position
  local function find_completion_start(line, col)
    local start = col
    while start > 0 do
      local char = line:sub(start, start)
      -- Break on whitespace, operators, brackets, and property access (.)
      if char:match("[%s%(%[%{%,%;%=%+%-%*%/%<>%&%|%!%~%^%%%#%.]") then
        break
      end
      start = start - 1
    end
    return start
  end

  ---Fetch completions from DAP
  ---@param bufnr number
  ---@param text string
  ---@param column number 1-indexed column position
  ---@param callback fun(items: table[])
  local function fetch_completions(bufnr, text, column, callback)
    local frame_pattern = vim.b[bufnr].dap_eval_frame_pattern

    -- Run everything async since resolve_frame may need to fetch stack
    neostate.void(function()
      local frame = resolve_frame(frame_pattern)

      if not frame then
        vim.schedule(function() callback({}) end)
        return
      end

      local session = frame.stack.thread.session

      -- Check if adapter supports completions
      if not session.capabilities or not session.capabilities.supportsCompletionsRequest then
        vim.schedule(function() callback({}) end)
        return
      end

      ---@type dap.CompletionsArguments
      local args = {
        text = text,
        column = column,
        frameId = frame.id,
      }

      local body, err = neostate.settle(session.client:request("completions", args))

      if err or not body or not body.targets then
        vim.schedule(function() callback({}) end)
        return
      end

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

  ---Create completefunc for a buffer
  ---@param bufnr number
  ---@return function
  local function create_completefunc(bufnr)
    return function(findstart, base)
      if findstart == 1 then
        -- Phase 1: Find start position
        local line = vim.api.nvim_get_current_line()
        local col = vim.fn.col(".") - 1
        return find_completion_start(line, col)
      else
        -- Phase 2: Return completions (async via vim.fn.complete)
        -- Note: In phase 2, Vim moves cursor to start position and passes 'base' as text to complete
        local line = vim.api.nvim_get_current_line()
        local col = vim.fn.col(".") - 1  -- This is now at completion start
        local start = col  -- Start is where cursor is in phase 2
        -- Reconstruct full text: prefix + base (text being completed)
        local full_text = line:sub(1, col) .. base
        local full_col = col + #base  -- Column at end of typed text

        fetch_completions(bufnr, full_text, full_col + 1, function(items)
          -- DAP adapter already filters completions, don't double-filter
          if #items > 0 and vim.fn.mode():match("^i") then
            vim.schedule(function()
              if vim.fn.mode():match("^i") then
                vim.fn.complete(start + 1, items)
              end
            end)
          end
        end)

        -- Return -2 to stay in completion mode while async fetch runs
        return -2
      end
    end
  end

  ---Navigate history
  ---@param bufnr number
  ---@param direction number -1 for older, 1 for newer
  local function history_navigate(bufnr, direction)
    if #history == 0 then return end

    local current = history_index[bufnr] or (#history + 1)
    local new_index = current + direction

    if new_index < 1 then new_index = 1 end
    if new_index > #history then
      history_index[bufnr] = nil
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      return
    end

    history_index[bufnr] = new_index
    local expr = history[new_index]
    local lines = vim.split(expr, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { #lines, #lines[#lines] })
  end

  ---Submit expression for evaluation
  ---@param bufnr number
  local function submit_expression(bufnr)
    -- Capture all buffer data synchronously BEFORE any async work
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local expression = table.concat(lines, "\n")

    if expression == "" then return end

    local frame_pattern = vim.b[bufnr].dap_eval_frame_pattern
    local close_on_submit = vim.b[bufnr].dap_eval_close_on_submit

    -- Add to history (sync)
    table.insert(history, expression)
    if #history > config.history_size then
      table.remove(history, 1)
    end
    history_index[bufnr] = nil

    -- Clear buffer or close IMMEDIATELY (before async work)
    -- This gives immediate user feedback
    if close_on_submit then
      vim.cmd("stopinsert")  -- Return to normal mode before closing
      vim.api.nvim_buf_delete(bufnr, { force = true })
    else
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      vim.cmd("startinsert")
    end

    -- Now do async work (frame resolution may need async stack fetch)
    neostate.void(function()
      local frame = resolve_frame(frame_pattern)

      if not frame then
        vim.schedule(function()
          vim.notify("No frame for evaluation", vim.log.levels.WARN)
        end)
        return
      end

      local err, result = frame:evaluate(expression, "repl")

      if config.on_submit then
        vim.schedule(function()
          config.on_submit(expression, frame, result, err)
        end)
      end
    end)()
  end

  ---Setup buffer with keymaps and options
  ---@param bufnr number
  local function setup_buffer(bufnr)
    -- Buffer options
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = true

    -- Setup completefunc
    local fn = create_completefunc(bufnr)
    local fn_name = string.format("_dap_eval_complete_%d", bufnr)
    _G[fn_name] = fn
    completefuncs[bufnr] = fn_name
    vim.bo[bufnr].completefunc = "v:lua." .. fn_name

    -- Submit expression (Enter in both modes)
    vim.keymap.set({ "n", "i" }, "<CR>", function()
      submit_expression(bufnr)
    end, { buffer = bufnr, desc = "Submit expression" })

    -- Literal newline (Ctrl-Enter)
    vim.keymap.set("i", "<C-CR>", function()
      local pos = vim.api.nvim_win_get_cursor(0)
      vim.api.nvim_buf_set_lines(bufnr, pos[1], pos[1], false, { "" })
      vim.api.nvim_win_set_cursor(0, { pos[1] + 1, 0 })
    end, { buffer = bufnr, desc = "Insert newline" })

    -- History navigation
    vim.keymap.set("i", "<Up>", function()
      history_navigate(bufnr, -1)
    end, { buffer = bufnr, desc = "Previous history" })

    vim.keymap.set("i", "<Down>", function()
      history_navigate(bufnr, 1)
    end, { buffer = bufnr, desc = "Next history" })

    -- Auto-trigger completion
    if #config.trigger_chars > 0 then
      vim.api.nvim_create_autocmd("InsertCharPre", {
        buffer = bufnr,
        group = group,
        callback = function()
          local char = vim.v.char
          if vim.tbl_contains(config.trigger_chars, char) then
            vim.defer_fn(function()
              if vim.fn.pumvisible() == 0 and vim.fn.mode():match("^i") then
                vim.api.nvim_feedkeys(
                  vim.api.nvim_replace_termcodes("<C-x><C-u>", true, false, true),
                  "n",
                  false
                )
              end
            end, 50)
          end
        end,
      })
    end
  end

  -- BufReadCmd for dap-eval: URIs
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = { "dap-eval:*" },
    group = group,
    callback = function(opts)
      local bufnr = opts.buf
      local uri = opts.file

      -- Parse URI
      local frame_pattern, options = parse_eval_uri(uri)

      -- Store in buffer variables
      vim.b[bufnr].dap_eval_frame_pattern = frame_pattern
      vim.b[bufnr].dap_eval_close_on_submit = options.closeonsubmit

      -- Setup buffer
      setup_buffer(bufnr)

      -- Enter insert mode
      vim.cmd("startinsert")
    end,
  })

  -- Cleanup on buffer wipeout
  vim.api.nvim_create_autocmd("BufWipeout", {
    pattern = { "dap-eval:*" },
    group = group,
    callback = function(opts)
      local bufnr = opts.buf
      if completefuncs[bufnr] then
        _G[completefuncs[bufnr]] = nil
        completefuncs[bufnr] = nil
      end
      history_index[bufnr] = nil
    end,
  })

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    for _, fn_name in pairs(completefuncs) do
      _G[fn_name] = nil
    end
    completefuncs = {}
    history_index = {}
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end)

  -- Return cleanup function
  return function()
    for _, fn_name in pairs(completefuncs) do
      _G[fn_name] = nil
    end
    completefuncs = {}
    history_index = {}
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
end
