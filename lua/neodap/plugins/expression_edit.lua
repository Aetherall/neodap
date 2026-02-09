-- Plugin: Expression edit buffer for editing values from source code
--
-- URI format:
--   dap://eval/@frame?expression=foo.bar              - Edit expression in current frame
--   dap://eval/@frame?expression=foo.bar&closeonsubmit - Close buffer after submit
--
-- Uses Frame:variable() to create Variable entities
-- Uses Variable:setValue() to modify values

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local a = require("neodap.async")

-- Namespace for virtual text
local ns_id = vim.api.nvim_create_namespace("neodap-expression-edit")

---Get expression at cursor using treesitter
---@return string?
local function get_expression_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]

  -- Try treesitter first
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col } })
  if ok and node then
    -- Walk up to find expression node
    local expr_types = {
      -- JavaScript/TypeScript
      identifier = true,
      member_expression = true,
      subscript_expression = true,
      call_expression = true,
      -- Lua
      dot_index_expression = true,
      bracket_index_expression = true,
      -- Python
      attribute = true,
      -- General
      property_identifier = true,
      field_expression = true,
    }

    local current = node
    local best = nil

    -- Find the largest expression node containing cursor
    while current do
      local node_type = current:type()
      if expr_types[node_type] then
        best = current
      end
      -- Stop if we hit a statement or declaration
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

  -- Fallback: scan backwards for dotted expression
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then return vim.fn.expand("<cword>") end

  -- Find start and end of expression containing cursor
  local start_col = col
  local end_col = col

  -- Valid expression chars (identifiers, dots, brackets)
  local function is_expr_char(c)
    return c:match("[%w_%.%[%]'\"]")
  end

  -- Scan backwards
  while start_col > 0 and is_expr_char(line:sub(start_col, start_col)) do
    start_col = start_col - 1
  end
  start_col = start_col + 1

  -- Scan forwards
  while end_col <= #line and is_expr_char(line:sub(end_col + 1, end_col + 1)) do
    end_col = end_col + 1
  end

  local expr = line:sub(start_col, end_col)
  if expr and expr ~= "" then
    return expr
  end

  -- Last fallback: word under cursor
  return vim.fn.expand("<cword>")
end

---Get visual selection
---@return string?
local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row, start_col = start_pos[2], start_pos[3]
  local end_row, end_col = end_pos[2], end_pos[3]

  if start_row ~= end_row then
    -- Multi-line selection - just get first line for now
    local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
    return table.concat(lines, "\n")
  end

  local line = vim.api.nvim_buf_get_lines(0, start_row - 1, start_row, false)[1]
  if line then
    return line:sub(start_col, end_col)
  end
  return nil
end

--------------------------------------------------------------------------------
-- Plugin
--------------------------------------------------------------------------------

---@param debugger neodap.entities.Debugger
return function(debugger)
  entity_buffer.init(debugger)

  ---Format variable info for virtual text
  ---@param variable table Variable entity
  ---@return string
  local function format_variable_info(variable)
    return debugger:render_text(variable, { { "title", prefix = " " }, { "type", prefix = ": " } })
  end

  ---Update virtual text indicator
  ---@param bufnr number
  ---@param variable table Variable entity
  ---@param status? string "modified"|"saved"|"error:..."|nil
  local function update_indicator(bufnr, variable, status)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    local info = format_variable_info(variable)
    local virt_text = { { info, "Comment" } }

    if status then
      if status == "modified" then
        table.insert(virt_text, { " [modified]", "DiffChange" })
      elseif status == "saved" then
        table.insert(virt_text, { " [saved]", "DiffAdd" })
      elseif status:match("^error:") then
        local err_msg = status:gsub("^error:", "")
        table.insert(virt_text, { " [" .. err_msg .. "]", "ErrorMsg" })
      end
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, 0, {
      virt_text = virt_text,
      virt_text_pos = "right_align",
    })
  end

  -- Track per-buffer state for dirty indicator
  local buffer_state = {}

  entity_buffer.register("dap://eval", "Variable", "one", {
    -- Resolve: @frame + expression option → Variable entity
    resolve = function(frame, options)
      if not frame then
        error("No frame available", 0)
      end
      local expression = options.expression
      if not expression or expression == "" then
        error("No expression provided", 0)
      end
      -- Decode URL-encoded expression
      expression = vim.uri_decode(expression)
      -- Create/find Variable entity for this expression
      return frame:variable(expression)
    end,

    render = function(bufnr, variable)
      return variable.value:get() or ""
    end,

    submit = function(bufnr, variable, content)
      a.run(function()
        variable:setValue(content)

        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(bufnr) then return end
          update_indicator(bufnr, variable, "saved")

          -- Clear saved indicator after delay
          vim.defer_fn(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
              update_indicator(bufnr, variable, nil)
            end
          end, 2000)
        end)
      end, function(err)
        if err then
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
              update_indicator(bufnr, variable, "error:" .. tostring(err))
            end
          end)
        end
      end)
    end,

    setup = function(bufnr, variable, options)
      buffer_state[bufnr] = { variable = variable, options = options }

      vim.bo[bufnr].filetype = "dap-expr"
      update_indicator(bufnr, variable, nil)

      -- Submit on Enter (normal mode)
      vim.keymap.set("n", "<CR>", function()
        entity_buffer.submit(bufnr)
      end, { buffer = bufnr, desc = "Submit expression value" })

      -- Submit on Ctrl-S (both modes)
      vim.keymap.set({ "n", "i" }, "<C-s>", function()
        vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
        entity_buffer.submit(bufnr)
      end, { buffer = bufnr, desc = "Submit expression value" })

      -- Reset to original value
      vim.keymap.set("n", "u", function()
        if entity_buffer.is_dirty(bufnr) then
          entity_buffer.reset(bufnr)
          update_indicator(bufnr, variable, nil)
        else
          vim.cmd("normal! u")
        end
      end, { buffer = bufnr, desc = "Reset to original value" })

      -- Close without saving
      vim.keymap.set("n", "q", function()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end, { buffer = bufnr, desc = "Close without saving" })

      -- Explore in tree view
      vim.keymap.set("n", "t", function()
        local var_uri = variable.uri:get()
        if var_uri then
          -- Fetch children first to avoid empty tree on initial render
          a.run(function()
            local ref = variable.variablesReference:get()
            if ref and ref > 0 then
              variable:fetchChildren()
            end
            vim.schedule(function()
              vim.cmd("edit dap://tree/" .. var_uri)
            end)
          end)
        end
      end, { buffer = bufnr, desc = "Explore in tree view" })

      -- Update indicator on text change
      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = bufnr,
        callback = function()
          local is_dirty = entity_buffer.is_dirty(bufnr)
          update_indicator(bufnr, variable, is_dirty and "modified" or nil)
        end,
      })

      -- Cleanup state on buffer delete
      vim.api.nvim_create_autocmd("BufDelete", {
        buffer = bufnr,
        once = true,
        callback = function()
          buffer_state[bufnr] = nil
        end,
      })

      -- Position cursor at end and enter insert mode
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local last_line = #lines
        local last_col = #lines[last_line]
        local win = vim.fn.bufwinid(bufnr)
        if win ~= -1 then
          vim.api.nvim_win_set_cursor(win, { last_line, last_col })
        end
        vim.cmd("startinsert!")
      end)
    end,

    on_change = "skip_if_dirty",
  })

  -- Return public API
  return {
    ---Get expression at cursor or visual selection
    ---Handles both normal and visual modes
    ---@return string?
    cursor_expression = function()
      local mode = vim.fn.mode()
      if mode == "v" or mode == "V" or mode == "\22" then
        vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
        return get_visual_selection()
      end
      return get_expression_at_cursor()
    end,
  }
end
