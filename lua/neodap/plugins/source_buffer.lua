-- Plugin: Source buffer using entity_buffer framework
--
-- URI format:
--   dap://source/source:path/to/file.js     - Source by key (path)
--   dap://source/source:path?session=abc    - Source with session hint
--
-- Usage:
--   source:open({ line = 10 })              - Use Source:open() method directly

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local a = require("neodap.async")

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function apply_pending_cursor(bufnr)
  local pending = vim.b[bufnr].dap_pending_cursor
  if not pending then return end
  vim.b[bufnr].dap_pending_cursor = nil

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local line = math.max(1, math.min(pending.line, line_count))
  local line_text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  local col = math.max(0, math.min(pending.col, #line_text))

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_win_set_cursor(win, { line, col })
      vim.api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
      break
    end
  end
end

--------------------------------------------------------------------------------
-- Plugin
--------------------------------------------------------------------------------

---@param debugger neodap.entities.Debugger
---@param config? table
return function(debugger, config)
  config = config or {}

  -- Initialize entity_buffer with debugger
  entity_buffer.init(debugger)

  -- Register dap://source scheme
  entity_buffer.register("dap://source", "Source", "one", {
    -- Initial render shows loading indicator
    render = function(bufnr, source)
      return "-- Loading..."
    end,

    -- No submit - read-only buffer

    -- Setup: async load content and set filetype
    setup = function(bufnr, source, options)
      -- Async load content
      a.run(function()
        local content = source:loadContent(options.session)
        a.wait(a.main, "source_buffer:schedule")
        if not vim.api.nvim_buf_is_valid(bufnr) then return end

        -- Set content
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content or "", "\n"))
        vim.bo[bufnr].modifiable = false
        vim.bo[bufnr].modified = false

        -- Set filetype based on source name/path
        local name = source.name:get() or ""
        local path = source.path:get() or ""

        -- Try filename-based detection first, fall back to adapter hint
        local ft = vim.filetype.match({ filename = name })
          or vim.filetype.match({ filename = path })
          or source.fallbackFiletype:get()

        if ft then vim.bo[bufnr].filetype = ft end

        -- Apply any pending cursor position
        apply_pending_cursor(bufnr)
      end, function(err)
        if err then
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
              vim.bo[bufnr].modifiable = true
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "-- Error loading source:",
                "-- " .. tostring(err),
              })
              vim.bo[bufnr].modifiable = false
            end
          end)
        end
      end)
    end,

    -- Note: on_change not needed - source URIs always resolve to same entity
  })

  return {}
end
