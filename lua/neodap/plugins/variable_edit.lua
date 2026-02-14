-- Plugin: Variable edit buffer using entity_buffer framework
--
-- URI format:
--   dap://var/@frame/scopes[0]/variables:myVar     - Edit variable (follows focus)
--   dap://var/variable:session:abc:123              - Edit specific variable (static)
--   dap://var/...?closeonsubmit                     - Close buffer after submit

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local edit_buffer = require("neodap.plugins.utils.edit_buffer")

-- Namespace for virtual text
local ns_id = vim.api.nvim_create_namespace("neodap-variable-edit")

--------------------------------------------------------------------------------
-- Plugin
--------------------------------------------------------------------------------

---@param debugger neodap.entities.Debugger
return function(debugger)
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
      local function get_entity()
        return entity_buffer.get_entity(bufnr)
      end
      edit_buffer.async_submit(bufnr, ns_id, debugger, function()
        variable:setValue(content)
      end, get_entity)
    end,

    -- Setup buffer with keymaps and virtual text
    setup = function(bufnr, variable, options)
      -- Initial indicator
      edit_buffer.update_indicator(bufnr, ns_id, debugger, variable, nil)

      -- Position cursor at end
      edit_buffer.cursor_to_end(bufnr)

      -- Standard keymaps
      edit_buffer.setup_keymaps(bufnr, { desc_prefix = "Submit variable value" })

      -- Reset indicator on keymap reset
      local orig_u = vim.fn.maparg("u", "n", false, true)
      vim.keymap.set("n", "u", function()
        if entity_buffer.is_dirty(bufnr) then
          entity_buffer.reset(bufnr)
          edit_buffer.update_indicator(bufnr, ns_id, debugger, entity_buffer.get_entity(bufnr), nil)
        else
          vim.cmd("normal! u")
        end
      end, { buffer = bufnr, desc = "Reset to original value" })

      -- Dirty tracking
      edit_buffer.setup_dirty_tracking(bufnr, ns_id, debugger, function()
        return entity_buffer.get_entity(bufnr)
      end)

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
