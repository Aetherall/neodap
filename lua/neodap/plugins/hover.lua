-- Plugin: In-process LSP for DAP hover
-- Registers as an LSP provider so vim.lsp.buf.hover() includes DAP info
--
-- When a debug session is active and thread is stopped, hovering over
-- expressions will show their evaluated values alongside regular LSP hover.

local ms = vim.lsp.protocol.Methods
local log = require("neodap.logger")

---@class HoverKeymapContext
---@field expression string The hovered expression
---@field win number The hover window id
---@field buf number The hover buffer id

---@class HoverConfig
---@field auto_attach? boolean Automatically attach to buffers (default: true)
---@field keymaps? table<string, fun(ctx: HoverKeymapContext)> Custom keymaps for hover window

local default_config = {
  auto_attach = true,
  keymaps = {},
}

---@param debugger neodap.entities.Debugger
---@param config? HoverConfig
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local client_id = nil
  local attached_buffers = {} -- bufnr -> true
  local last_hover_expression = nil -- Track for edit keybind

  -- LSP handlers
  local handlers = {}

  -- Capabilities: we only provide hover
  local initializeResult = {
    capabilities = {
      hoverProvider = true,
    },
  }

  handlers[ms.initialize] = function(_, callback)
    callback(nil, initializeResult)
  end

  handlers[ms.shutdown] = function(_, callback)
    callback(nil, nil)
  end

  ---Get expression at cursor position using treesitter
  ---@param bufnr number
  ---@param row number 0-indexed
  ---@param col number 0-indexed
  ---@return string?
  local function get_expression_at_position(bufnr, row, col)
    -- Try treesitter first
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col } })
    if ok and node then
      local expr_types = {
        identifier = true,
        member_expression = true,
        subscript_expression = true,
        dot_index_expression = true,
        bracket_index_expression = true,
        attribute = true,
        property_identifier = true,
        field_expression = true,
      }

      local current = node
      local best = nil

      while current do
        local node_type = current:type()
        if expr_types[node_type] then
          best = current
        end
        if node_type:match("statement") or node_type:match("declaration") then
          break
        end
        current = current:parent()
      end

      if best then
        local text = vim.treesitter.get_node_text(best, bufnr)
        if text and text ~= "" then
          return text
        end
      end
    end

    -- Fallback: get word at position
    local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
    if not lines[1] then return nil end

    local line = lines[1]
    local start_col = col
    local end_col = col

    local function is_word_char(c)
      return c:match("[%w_]")
    end

    while start_col > 0 and is_word_char(line:sub(start_col, start_col)) do
      start_col = start_col - 1
    end
    start_col = start_col + 1

    while end_col <= #line and is_word_char(line:sub(end_col + 1, end_col + 1)) do
      end_col = end_col + 1
    end

    local word = line:sub(start_col, end_col)
    return word ~= "" and word or nil
  end

  ---Evaluate expression and call callback with markdown result
  ---@param expression string
  ---@param callback fun(markdown: string?)
  local function evaluate_for_hover(expression, callback)
    -- Get thread from context
    local thread = debugger.ctx.thread:get()
    if not thread or not thread:isStopped() then
      log:debug("evaluate_for_hover: thread not stopped")
      callback(nil)
      return
    end

    -- Get current stack and top frame
    local stack = thread.stack:get()
    if not stack then
      log:debug("evaluate_for_hover: no stack")
      callback(nil)
      return
    end

    -- Get the focused frame, or default to top frame
    local frame = debugger.ctx.frame:get()
    if not frame then
      -- Fallback to top frame from stack
      for f in stack.frames:iter() do
        frame = f
        break
      end
    end

    if not frame then
      log:debug("evaluate_for_hover: no frame")
      callback(nil)
      return
    end

    -- Validate frame belongs to current stack (not stale from previous stop)
    if frame.stack:get() ~= stack then
      log:debug("evaluate_for_hover: frame is stale, using top frame")
      -- Frame is stale, fall back to top frame
      for f in stack.frames:iter() do
        frame = f
        break
      end
    end

    local session = thread.session:get()
    if not session then
      log:debug("evaluate_for_hover: no session")
      callback(nil)
      return
    end

    local context_mod = require("neodap.plugins.dap.context")
    local dap_session = context_mod.get_dap_session(session)
    if not dap_session then
      log:debug("evaluate_for_hover: no dap_session")
      callback(nil)
      return
    end

    local frame_id = frame.frameId:get()
    log:debug("evaluate_for_hover: sending request", { frameId = frame_id, expression = expression })

    dap_session.client:request("evaluate", {
      expression = expression,
      frameId = frame_id,
      context = "hover",
    }, function(err, body)
      if err then
        log:debug("evaluate_for_hover: DAP error", { err = tostring(err) })
        callback(nil)
        return
      end

      if not body or not body.result then
        callback(nil)
        return
      end

      local result = body.result
      local vtype = body.type
      log:debug("evaluate_for_hover: success", { result = result, vtype = vtype })

      -- Format as markdown
      local lines = {}
      if vtype and vtype ~= "" then
        table.insert(lines, string.format("**%s** `%s`", expression, vtype))
      else
        table.insert(lines, string.format("**%s**", expression))
      end
      table.insert(lines, "```")
      table.insert(lines, tostring(result))
      table.insert(lines, "```")

      callback(table.concat(lines, "\n"))
    end)
  end

  handlers[ms.textDocument_hover] = function(params, callback)
    log:debug("Hover handler called", { params = params })

    -- Extract position from params
    local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
    local row = params.position.line
    local col = params.position.character

    -- Get expression at position
    local expression = get_expression_at_position(bufnr, row, col)
    log:debug("Expression at position", { expression = expression, row = row, col = col })
    if not expression then
      log:debug("No expression found, returning nil")
      callback(nil, nil)
      return
    end

    -- Evaluate asynchronously
    log:debug("Evaluating expression", { expression = expression })
    evaluate_for_hover(expression, function(markdown)
      log:debug("Hover evaluation result", { markdown = markdown })
      if markdown then
        -- Store expression for edit keybind
        last_hover_expression = expression
        callback(nil, {
          contents = {
            kind = "markdown",
            value = markdown,
          },
        })
      else
        callback(nil, nil)
      end
    end)
  end

  -- Create the in-process LSP client
  local function create_client()
    if client_id then return client_id end

    client_id = vim.lsp.start({
      name = "neodap-hover",
      cmd = function(_dispatchers)
        return {
          request = function(method, params, callback)
            log:debug("LSP request", { method = method, has_handler = handlers[method] ~= nil })
            if handlers[method] then
              handlers[method](params, callback)
            else
              callback(nil, nil)
            end
            return true -- Indicate request was accepted
          end,
          notify = function(method, params)
            log:debug("LSP notify", { method = method })
          end,
          is_closing = function() return false end,
          terminate = function() end,
        }
      end,
      root_dir = vim.fn.getcwd(),
    }, {
      reuse_client = function(existing_client, _cfg)
        return existing_client.name == "neodap-hover"
      end,
    })

    return client_id
  end

  -- Attach to a buffer
  local function attach(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local id = create_client()
    if not id then return end

    -- Check if already attached
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      if client.id == id then
        return -- Already attached
      end
    end

    vim.lsp.buf_attach_client(bufnr, id)
    attached_buffers[bufnr] = true
  end

  -- Detach from a buffer
  local function detach(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not attached_buffers[bufnr] then return end

    if client_id then
      vim.lsp.buf_detach_client(bufnr, client_id)
    end
    attached_buffers[bufnr] = nil
  end

  -- Auto-attach to source buffers
  if config.auto_attach then
    local group = vim.api.nvim_create_augroup("neodap-hover", { clear = true })

    -- Attach when entering buffers
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      callback = function(ev)
        -- Only attach to normal file buffers
        if vim.bo[ev.buf].buftype == "" then
          attach(ev.buf)
        end
      end,
    })

    -- Cleanup on buffer delete
    vim.api.nvim_create_autocmd("BufDelete", {
      group = group,
      callback = function(ev)
        attached_buffers[ev.buf] = nil
      end,
    })

    -- Attach to current buffer immediately
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.bo[bufnr].buftype == "" then
      attach(bufnr)
    end

    -- Add custom keymaps to hover floating windows
    if config.keymaps and next(config.keymaps) then
      vim.api.nvim_create_autocmd("WinEnter", {
        group = group,
        callback = function()
          local win = vim.api.nvim_get_current_win()
          local win_config = vim.api.nvim_win_get_config(win)

          -- Check if it's a floating window
          if win_config.relative == "" then return end

          local buf = vim.api.nvim_get_current_buf()

          -- Check if we have a recent hover expression and buffer looks like our hover
          if not last_hover_expression then return end
          if vim.bo[buf].buftype ~= "nofile" then return end

          -- Check first line matches our format
          local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
          if not lines[1] or not lines[1]:match("^%*%*.*%*%*") then return end

          -- Add keymaps (only if not already set)
          if vim.b[buf].neodap_hover_keymaps then return end
          vim.b[buf].neodap_hover_keymaps = true

          local expr = last_hover_expression
          for key, callback in pairs(config.keymaps) do
            vim.keymap.set("n", key, function()
              callback({
                expression = expr,
                win = win,
                buf = buf,
              })
            end, { buffer = buf })
          end
        end,
      })
    end
  end

  return {
    attach = attach,
    detach = detach,
    get_client_id = function() return client_id end,
  }
end
