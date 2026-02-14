-- Plugin: Expression edit buffer for editing values from source code
--
-- URI format:
--   dap://eval/@frame?expression=foo.bar              - Edit expression in current frame
--   dap://eval/@frame?expression=foo.bar&closeonsubmit - Close buffer after submit
--
-- Uses Frame:variable() to create Variable entities
-- Uses Variable:setValue() to modify values

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local edit_buffer = require("neodap.plugins.utils.edit_buffer")
local expression_utils = require("neodap.plugins.utils.expression")
local a = require("neodap.async")

-- Namespace for virtual text
local ns_id = vim.api.nvim_create_namespace("neodap-expression-edit")

--------------------------------------------------------------------------------
-- Plugin
--------------------------------------------------------------------------------

---@param debugger neodap.entities.Debugger
return function(debugger)
  entity_buffer.init(debugger)

  -- Track per-buffer state for dirty indicator
  local buffer_state = {}

  entity_buffer.register("dap://eval", "Variable", "one", {
    -- Resolve: @frame + expression option -> Variable entity
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
      edit_buffer.async_submit(bufnr, ns_id, debugger, function()
        variable:setValue(content)
      end, function()
        return entity_buffer.get_entity(bufnr)
      end)
    end,

    setup = function(bufnr, variable, options)
      buffer_state[bufnr] = { variable = variable, options = options }

      vim.bo[bufnr].filetype = "dap-expr"
      edit_buffer.update_indicator(bufnr, ns_id, debugger, variable, nil)

      -- Standard keymaps (with escape_insert for <C-s>)
      edit_buffer.setup_keymaps(bufnr, {
        desc_prefix = "Submit expression value",
        escape_insert = true,
      })

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

      -- Dirty tracking
      edit_buffer.setup_dirty_tracking(bufnr, ns_id, debugger, function()
        return entity_buffer.get_entity(bufnr)
      end)

      -- Cleanup state on buffer delete
      vim.api.nvim_create_autocmd("BufDelete", {
        buffer = bufnr,
        once = true,
        callback = function()
          buffer_state[bufnr] = nil
        end,
      })

      -- Position cursor at end and enter insert mode
      edit_buffer.cursor_to_end(bufnr, { insert = true })
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
        return expression_utils.get_visual_selection()
      end
      return expression_utils.get_expression_at_cursor({ include_calls = true, dotted_fallback = true })
    end,
  }
end
