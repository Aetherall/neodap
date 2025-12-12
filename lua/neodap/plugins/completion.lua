-- Plugin: DAP completion provider for omnifunc
-- Provides DAP-powered completions usable in any buffer
--
-- Usage:
--   vim.bo.omnifunc = "v:lua.dap_complete"
--   Then use <C-x><C-o> to trigger completions
--
-- Or set globally for specific filetypes in your config

local completion = require("neodap.plugins.utils.completion")
local type_to_kind = completion.type_to_kind
local log = require("neodap.logger")
local E = require("neodap.error")

---@param debugger neodap.entities.Debugger
return function(debugger)
  ---The omnifunc implementation
  ---@param findstart number 1 for finding start, 0 for getting completions
  ---@param base string The text to complete (only when findstart=0)
  ---@return number|table
  local function dap_complete(findstart, base)
    if findstart == 1 then
      -- Phase 1: Find start position
      local line = vim.api.nvim_get_current_line()
      local col = vim.fn.col(".") - 1
      return completion.find_completion_start(line, col)
    else
      -- Phase 2: Get completions
      -- Use buffer context to get the frame (respects buffer-local pinning)
      -- Falls back to session-level completions (global scope) when no frame
      local frame = debugger.ctx.frame:get()
      local completion_source = frame
      if not completion_source then
        local session = debugger.ctx.session:get()
        if not session or session:isTerminated() then
          return {}
        end
        completion_source = session
      end

      local line = vim.api.nvim_get_current_line()
      local col = vim.fn.col(".") - 1
      -- Reconstruct full text up to cursor
      local text = line:sub(1, col) .. base

      -- Request completions asynchronously
      local a = require("neodap.async")
      a.run(function()
        local targets = completion_source:completions(text, col + #base + 1)
        if not targets then return end

        local items = {}
        for _, target in ipairs(targets) do
          table.insert(items, {
            word = target.text or target.label,
            abbr = target.label,
            kind = type_to_kind[target.type] or "",
            menu = target.detail or "",
            info = target.detail or "",
            icase = 1,
            dup = 0,
          })
        end

        -- Show completions if still in insert mode
        vim.schedule(function()
          if #items > 0 and vim.fn.mode():match("^i") then
            vim.fn.complete(completion.find_completion_start(line, col) + 1, items)
          end
        end)
      end)

      -- Return -2 to stay in completion mode while async fetch runs
      return -2
    end
  end

  -- Register as global function for omnifunc
  _G.dap_complete = dap_complete

  -- Create command to set omnifunc in current buffer
  E.create_command("DapCompleteEnable", function()
    vim.bo.omnifunc = "v:lua.dap_complete"
    log:info("DAP completion enabled for this buffer")
  end, { desc = "Enable DAP completion in current buffer" })

  E.create_command("DapCompleteDisable", function()
    vim.bo.omnifunc = ""
    log:info("DAP completion disabled for this buffer")
  end, { desc = "Disable DAP completion in current buffer" })

  -- Return public API
  return {
    ---The completion function (for manual use)
    complete = dap_complete,

    ---Enable DAP completion in a buffer
    ---@param bufnr? number Buffer number (default: current)
    enable = function(bufnr)
      bufnr = bufnr or 0
      vim.bo[bufnr].omnifunc = "v:lua.dap_complete"
    end,

    ---Disable DAP completion in a buffer
    ---@param bufnr? number Buffer number (default: current)
    disable = function(bufnr)
      bufnr = bufnr or 0
      vim.bo[bufnr].omnifunc = ""
    end,
  }
end
