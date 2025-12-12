-- Plugin: :DapOpen command
--
-- Unified command for opening any neodap buffer with an explicit position.
-- Replaces DapConsole, DapLog, DapOutput, DapTerminal.
--
-- Usage:
--   :DapOpen replace console          - open console in current window
--   :DapOpen vsplit tree              - open debugger tree in vertical split
--   :DapOpen split output             - open stdio output in horizontal split
--   :DapOpen tab log                  - open DAP protocol log in new tab
--   :DapOpen float input              - open expression input in a float
--   :DapOpen replace breakpoints      - open breakpoints tree in current window
--   :DapOpen vsplit dap://tree/@session
--   :DapOpen float dap://eval/@frame?expression=fibonacci(5)
--
-- Positions: replace | split | hsplit | vsplit | tab | float
--
-- Named targets:
--   console      dap://console/session:<focused>
--   terminal     dap://terminal/session:<focused>
--   output       <session.logDir>/output.log
--   log          /tmp/neodap-dap/<session_id>.log  (configurable via dap_log_dir)
--   tree         dap://tree/@debugger
--   input        dap://input/@frame
--   breakpoints  dap://tree/breakpoints:group

local E = require("neodap.error")
local url_completion = require("neodap.plugins.utils.url_completion")
local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local open = require("neodap.plugins.utils.open")

---@class neodap.OpenCmdConfig
---@field dap_log_dir? string Directory used by dap_log plugin (default: /tmp/neodap-dap)

---@param debugger neodap.entities.Debugger
---@param config? neodap.OpenCmdConfig
return function(debugger, config)
  config = config or {}
  local dap_log_dir = config.dap_log_dir or "/tmp/neodap-dap"

  local POSITIONS = { "replace", "split", "hsplit", "vsplit", "tab", "float" }

  local NAMED_TARGETS = {
    "console", "terminal", "output", "log", "tree", "input", "breakpoints",
  }

  ---Resolve a named target or raw URI to an openable URI/path
  ---@param target string Named target or raw dap:// URI
  ---@return string uri_or_path
  local function resolve(target)
    if target == "console" then
      local session = debugger.ctx.session:get()
      if not session then error(E.warn("DapOpen: No focused session"), 0) end
      return "dap://console/session:" .. session.sessionId:get()

    elseif target == "terminal" then
      local session = debugger.ctx.session:get()
      if not session then error(E.warn("DapOpen: No focused session"), 0) end
      return "dap://terminal/session:" .. session.sessionId:get()

    elseif target == "output" then
      local session = debugger.ctx.session:get()
      if not session then error(E.warn("DapOpen: No focused session"), 0) end
      local log_dir = session.logDir and session.logDir:get()
      if not log_dir then error(E.warn("DapOpen: Session has no output log"), 0) end
      local path = log_dir .. "/output.log"
      -- Ensure the file exists so the buffer can open it
      if vim.fn.filereadable(path) == 0 then
        local f = io.open(path, "w")
        if f then f:close() end
      end
      return path

    elseif target == "log" then
      local session = debugger.ctx.session:get()
      if not session then error(E.warn("DapOpen: No focused session"), 0) end
      local session_id = session.sessionId:get()
      local path = dap_log_dir .. "/" .. session_id .. ".log"
      if vim.fn.filereadable(path) == 0 then
        error(E.warn("DapOpen: No DAP log file for this session"), 0)
      end
      return path

    elseif target == "tree" then
      return "dap://tree/@debugger"

    elseif target == "input" then
      return "dap://input/@frame"

    elseif target == "breakpoints" then
      return "dap://tree/breakpoints:group"

    else
      -- Raw URI passthrough (dap://... or any path)
      return target
    end
  end

  ---After opening a buffer, register q → close window for plain file buffers.
  ---dap:// buffers already have q set up by their own plugin; for plain files
  ---we need to add it here. We always set it — it's a harmless overwrite for
  ---dap:// buffers and the necessary keymap for plain files (output, log).
  local function register_q_close()
    local bufnr = vim.api.nvim_get_current_buf()
    E.keymap("n", "q", function()
      local wins = vim.fn.win_findbuf(bufnr)
      if #wins <= 1 then
        -- Only one window showing this buffer — close it (keeps nvim alive
        -- by using :close instead of :q)
        vim.cmd("close")
      else
        vim.api.nvim_win_close(0, false)
      end
    end, { buffer = bufnr, nowait = true, desc = "Close DAP buffer" })
  end

  E.create_command("DapOpen", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    if #args < 2 then
      error(E.warn("DapOpen: Usage: DapOpen <position> <target>"), 0)
    end

    local pos    = args[1]
    local target = table.concat(vim.list_slice(args, 2), " ")

    -- Validate position
    if not vim.tbl_contains(POSITIONS, pos) then
      error(E.warn(
        "DapOpen: Unknown position '" .. pos .. "' — expected: " ..
        table.concat(POSITIONS, ", ")
      ), 0)
    end

    local uri = resolve(target)
    open.open(uri, { split = pos == "replace" and nil or pos })
    register_q_close()
  end, {
    nargs = "+",
    desc  = "Open a neodap buffer at an explicit position",
    complete = function(arglead, cmdline)
      local args = vim.split(cmdline, "%s+", { trimempty = true })
      -- args[1] = "DapOpen", args[2] = position, args[3] = target
      local nargs = #args
      -- When there is a trailing space, arglead is "" and we're completing the next token
      local completing_pos    = nargs == 1 or (nargs == 2 and arglead ~= "")
      local completing_target = nargs == 2 or (nargs >= 3 and arglead ~= "")

      if completing_pos then
        return vim.tbl_filter(function(p)
          return p:match("^" .. vim.pesc(arglead))
        end, POSITIONS)
      end

      if completing_target then
        local candidates = {}
        local lead = vim.pesc(arglead)

        -- Layer 1: Named targets (tree, console, input, ...)
        for _, t in ipairs(NAMED_TARGETS) do
          if t:match("^" .. lead) then
            table.insert(candidates, t)
          end
        end

        -- Layer 2: dap:// scheme completion (dap://tree/, dap://console/, ...)
        -- Offered when the user has typed "dap://" but hasn't completed the scheme yet.
        local dap_base, dap_path = arglead:match("^(dap://[^/]+/)(.*)")
        if dap_base then
          -- Layer 3: Path completion within a scheme
          -- e.g., dap://tree/@session/ → complete with Session edges
          local url_completions = url_completion.complete(debugger, dap_path)
          for _, c in ipairs(url_completions) do
            table.insert(candidates, dap_base .. c)
          end
        elseif arglead:match("^dap://") then
          -- Still typing the scheme name (e.g., "dap://tr")
          for _, scheme in ipairs(entity_buffer.registered_schemes()) do
            local candidate = scheme .. "/"
            if candidate:match("^" .. lead) then
              table.insert(candidates, candidate)
            end
          end
        else
          -- No dap:// prefix: offer URL path completions (@session, sessions, ...)
          local url_completions = url_completion.complete(debugger, arglead)
          vim.list_extend(candidates, url_completions)
        end

        return candidates
      end

      return {}
    end,
  })

  local api = {}

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapOpen")
  end

  return api
end
