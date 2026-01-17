-- Plugin: Input buffer for expression evaluation using entity_buffer framework
--
-- URI format:
--   dap://input/@frame                    - Follows focused frame (reactive)
--   dap://input/@frame?pin                - Pin to current frame at open time
--   dap://input/@frame?closeonsubmit      - Close buffer after submit
--   dap://input/frame:session:abc:123     - Explicit frame URI (static)

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local a = require("neodap.async")

-- Namespace for virtual text
local ns_id = vim.api.nvim_create_namespace("neodap-input-buffer")

---@class InputBufferConfig
---@field trigger_chars? string[] Auto-complete trigger chars (default: {".", "[", "("})
---@field history_size? number Max history entries (default: 100)

local default_config = {
  trigger_chars = { ".", "[", "(" },
  history_size = 100,
}

---@param debugger neodap.entities.Debugger
---@param config? InputBufferConfig
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  -- Shared state across buffers
  local history = {}
  local history_index = {} -- Per-buffer history position

  -- Initialize entity_buffer with debugger
  entity_buffer.init(debugger)

  ---Format frame info for virtual text
  ---@param frame any? Frame entity
  ---@return string
  local function format_frame_info(frame)
    if not frame then
      return "⚠ No frame"
    end

    local name = frame.name:get() or "?"
    local line = frame.line:get()

    if line then
      return string.format("→ %s:%d", name, line)
    else
      return string.format("→ %s", name)
    end
  end

  ---Update virtual text indicator for buffer
  ---@param bufnr number
  ---@param frame any? Frame entity
  local function update_frame_indicator(bufnr, frame)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    local text = format_frame_info(frame)
    local hl = frame and "Comment" or "WarningMsg"

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, 0, {
      virt_text = { { text, hl } },
      virt_text_pos = "right_align",
    })
  end

  ---Navigate history
  ---@param bufnr number
  ---@param direction number -1 for older, 1 for newer
  local function history_navigate(bufnr, direction)
    if #history == 0 then
      return
    end

    local current = history_index[bufnr] or (#history + 1)
    local new_index = current + direction

    if new_index < 1 then
      new_index = 1
    end
    if new_index > #history then
      history_index[bufnr] = nil
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
      local frame = entity_buffer.get_entity(bufnr)
      update_frame_indicator(bufnr, frame)
      return
    end

    history_index[bufnr] = new_index
    local expr = history[new_index]
    local lines = vim.split(expr, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { #lines, #lines[#lines] })
    local frame = entity_buffer.get_entity(bufnr)
    update_frame_indicator(bufnr, frame)
  end

  -- Register dap://input scheme (optional entity - works without focused frame)
  entity_buffer.register("dap://input", "Frame", "one", {
    optional = true,
    -- Render empty input
    render = function(bufnr, frame)
      return ""
    end,

    -- Submit evaluates expression
    submit = function(bufnr, frame, content)
      if content == "" then
        return
      end
      if not frame then
        vim.notify("No frame available for evaluation", vim.log.levels.WARN)
        return
      end

      -- Add to history
      table.insert(history, content)
      if #history > config.history_size then
        table.remove(history, 1)
      end
      history_index[bufnr] = nil

      -- Evaluate expression asynchronously
      a.run(function()
        frame:evaluate(content)
      end, function(err)
        if err then
          vim.schedule(function()
            vim.notify("Evaluation error: " .. tostring(err), vim.log.levels.ERROR)
          end)
        end
      end)

      -- Clear buffer for next input (entity_buffer handles closeonsubmit)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
          local current_frame = entity_buffer.get_entity(bufnr)
          update_frame_indicator(bufnr, current_frame)
          vim.cmd("startinsert")
        end
      end)
    end,

    -- Setup buffer with keymaps and completion
    setup = function(bufnr, frame, options)
      -- TODO: pin option removed - needs redesign to capture frame URI at open time
      -- instead of using reactive @frame URL

      -- Initial indicator
      update_frame_indicator(bufnr, frame)

      -- Use shared DAP completion
      vim.bo[bufnr].omnifunc = "v:lua.dap_complete"

      -- Submit expression (Enter in both modes)
      vim.keymap.set({ "n", "i" }, "<CR>", function()
        entity_buffer.submit(bufnr)
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

      -- Close without saving
      vim.keymap.set("n", "q", function()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end, { buffer = bufnr, desc = "Close buffer" })

      -- Auto-trigger completion
      if #config.trigger_chars > 0 then
        vim.api.nvim_create_autocmd("InsertCharPre", {
          buffer = bufnr,
          callback = function()
            local char = vim.v.char
            if vim.tbl_contains(config.trigger_chars, char) then
              vim.defer_fn(function()
                if vim.fn.pumvisible() == 0 and vim.fn.mode():match("^i") then
                  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-o>", true, false, true), "n", false)
                end
              end, 50)
            end
          end,
        })
      end

      -- Enter insert mode
      vim.cmd("startinsert")
    end,

    -- Cleanup history index on buffer close
    cleanup = function(bufnr)
      history_index[bufnr] = nil
    end,

    -- Update indicator when frame changes
    on_change = "always",
  })

  -- Return public API
  return {
    ---Get expression history
    ---@return string[]
    history = function()
      return vim.deepcopy(history)
    end,

    ---Clear expression history
    clear_history = function()
      history = {}
      history_index = {}
    end,
  }
end
