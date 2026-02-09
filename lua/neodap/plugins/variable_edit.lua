-- Plugin: Variable edit buffer using entity_buffer framework
--
-- URI format:
--   dap://var/@frame/scopes[0]/variables:myVar     - Edit variable (follows focus)
--   dap://var/variable:session:abc:123              - Edit specific variable (static)
--   dap://var/...?closeonsubmit                     - Close buffer after submit

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local a = require("neodap.async")

-- Namespace for virtual text
local ns_id = vim.api.nvim_create_namespace("neodap-variable-edit")

--------------------------------------------------------------------------------
-- Plugin
--------------------------------------------------------------------------------

---@param debugger neodap.entities.Debugger
return function(debugger)

  ---Format variable info for virtual text
  ---@param variable any Variable entity
  ---@return string
  local function format_variable_info(variable)
    if not variable then
      return " No variable"
    end
    return debugger:render_text(variable, { { "title", prefix = " " }, { "type", prefix = ": " } })
  end

  ---Update virtual text indicator
  ---@param bufnr number
  ---@param variable any Variable entity
  ---@param status? string "modified"|"saved"|"error:..."|nil
  local function update_indicator(bufnr, variable, status)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    local info = format_variable_info(variable)
    local info_hl = variable and "Comment" or "WarningMsg"

    local virt_text = { { info, info_hl } }

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
  -- Initialize entity_buffer with debugger
  entity_buffer.init(debugger)

  -- Register dap://var scheme
  entity_buffer.register("dap://var", "Variable", "one", {
    -- Render variable value to buffer
    render = function(bufnr, variable)
      return variable.value:get() or ""
    end,

    -- Submit new value
    submit = function(bufnr, variable, content)
      -- Async setValue
      a.run(function()
        variable:setValue(content)
        vim.schedule(function()
          -- Show success indicator (get current entity in case it changed)
          local current_var = entity_buffer.get_entity(bufnr)
          update_indicator(bufnr, current_var, "saved")
          vim.defer_fn(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
              local var = entity_buffer.get_entity(bufnr)
              update_indicator(bufnr, var, nil)
            end
          end, 2000)
        end)
      end, function(err)
        if err then
          vim.schedule(function()
            local current_var = entity_buffer.get_entity(bufnr)
            update_indicator(bufnr, current_var, "error:" .. tostring(err))
          end)
        end
      end)
    end,

    -- Setup buffer with keymaps and virtual text
    setup = function(bufnr, variable, options)
      -- Initial indicator
      update_indicator(bufnr, variable, nil)

      -- Position cursor at end
      vim.schedule(function()
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local last_line = #lines
        local last_col = #lines[last_line]
        local win = vim.fn.bufwinid(bufnr)
        if win ~= -1 then
          vim.api.nvim_win_set_cursor(win, { last_line, last_col })
        end
      end)

      -- Submit on Enter (normal mode)
      vim.keymap.set("n", "<CR>", function()
        entity_buffer.submit(bufnr)
      end, { buffer = bufnr, desc = "Submit variable value" })

      -- Submit on Ctrl-S (both modes)
      vim.keymap.set({ "n", "i" }, "<C-s>", function()
        entity_buffer.submit(bufnr)
      end, { buffer = bufnr, desc = "Submit variable value" })

      -- Reset to original value
      vim.keymap.set("n", "u", function()
        if entity_buffer.is_dirty(bufnr) then
          entity_buffer.reset(bufnr)
          local current_var = entity_buffer.get_entity(bufnr)
          update_indicator(bufnr, current_var, nil)
        else
          vim.cmd("normal! u")
        end
      end, { buffer = bufnr, desc = "Reset to original value" })

      -- Close without saving
      vim.keymap.set("n", "q", function()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end, { buffer = bufnr, desc = "Close without saving" })

      -- Update indicator on text change
      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = bufnr,
        callback = function()
          local current_var = entity_buffer.get_entity(bufnr)
          local status = entity_buffer.is_dirty(bufnr) and "modified" or nil
          update_indicator(bufnr, current_var, status)
        end,
      })

      -- Enter insert mode
      vim.cmd("startinsert!")
    end,

    -- Don't update if user has unsaved changes
    on_change = "skip_if_dirty",
  })

  -- Return public API
  return {
    ---Open edit buffer for a variable
    ---@param variable any Variable entity or URL string
    ---@param opts? { close_on_submit?: boolean }
    edit = function(variable, opts)
      opts = opts or {}
      local url
      if type(variable) == "string" then
        url = variable
      else
        url = variable.uri:get()
      end
      local uri = "dap://var/" .. url
      if opts.close_on_submit then
        uri = uri .. "?closeonsubmit"
      end
      vim.cmd("edit " .. vim.fn.fnameescape(uri))
    end,
  }
end
