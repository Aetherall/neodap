-- Plugin: Tree Preview Buffer
-- Buffer scheme that follows a tree buffer's selection and shows preview.
--
-- URI format:
--   dap://tree-preview/{tree_bufnr}
--
-- Example:
--   :edit dap://tree-preview/5    " Preview follows tree buffer #5
--
-- The buffer watches vim.b.focused_uri on the target tree buffer
-- and delegates rendering to dap://preview/{entity_uri}.

local entity_buffer = require("neodap.plugins.utils.entity_buffer")

---@param debugger neodap.entities.Debugger
---@param config? table
return function(debugger, config)
  config = config or {}

  -- State local to this plugin instance
  local buffers = {}  -- bufnr -> { tree_bufnr, autocmd_id }

  -- Load preview_handler for rendering delegation
  local preview_handler = require("neodap.plugins.preview_handler")(debugger)

  -- Initialize entity_buffer
  entity_buffer.init(debugger)

  --- Update preview buffer content based on tree's focused_uri
  ---@param bufnr number Preview buffer
  ---@param tree_bufnr number Tree buffer being watched
  local function update_preview(bufnr, tree_bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    if not vim.api.nvim_buf_is_valid(tree_bufnr) then
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "-- Tree buffer no longer valid",
        "-- Buffer: " .. tree_bufnr,
      })
      vim.bo[bufnr].modifiable = false
      return
    end

    local entity_uri = vim.b[tree_bufnr].focused_uri
    if not entity_uri then
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "-- No entity focused in tree",
      })
      vim.bo[bufnr].modifiable = false
      return
    end

    -- Delegate to preview_handler
    preview_handler.refresh(bufnr, entity_uri)
  end

  --- Setup tree preview buffer
  ---@param bufnr number Preview buffer
  ---@param tree_bufnr number Tree buffer to watch
  local function setup_buffer(bufnr, tree_bufnr)
    -- Buffer options
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false

    -- Validate tree buffer
    if not vim.api.nvim_buf_is_valid(tree_bufnr) then
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "-- Invalid tree buffer",
        "-- Buffer: " .. tree_bufnr,
      })
      vim.bo[bufnr].modifiable = false
      return
    end

    -- Check it's actually a tree buffer
    local tree_name = vim.api.nvim_buf_get_name(tree_bufnr)
    if not tree_name:match("^dap://tree/") then
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "-- Not a tree buffer",
        "-- Buffer: " .. tree_bufnr,
        "-- Name: " .. tree_name,
      })
      vim.bo[bufnr].modifiable = false
      return
    end

    -- Setup autocmd to track cursor movement in tree
    local autocmd_id = vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = tree_bufnr,
      callback = function()
        update_preview(bufnr, tree_bufnr)
      end,
    })

    -- Store state
    buffers[bufnr] = {
      tree_bufnr = tree_bufnr,
      autocmd_id = autocmd_id,
    }

    -- Initial render
    update_preview(bufnr, tree_bufnr)
  end

  --- Cleanup buffer state
  ---@param bufnr number
  local function cleanup_buffer(bufnr)
    local state = buffers[bufnr]
    if not state then return end

    if state.autocmd_id then
      pcall(vim.api.nvim_del_autocmd, state.autocmd_id)
    end

    buffers[bufnr] = nil
  end

  -- Create autocmd for dap://tree-preview/* scheme
  local group = vim.api.nvim_create_augroup("neodap-tree-preview", { clear = true })

  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = "dap://tree-preview/*",
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      local uri = ev.file

      -- Parse: dap://tree-preview/{tree_bufnr}
      local tree_bufnr_str = uri:match("^dap://tree%-preview/(%d+)$")
      if not tree_bufnr_str then
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
          "-- Invalid tree-preview URI",
          "-- Expected: dap://tree-preview/{bufnr}",
          "-- Got: " .. uri,
        })
        vim.bo[bufnr].modifiable = false
        return
      end

      local tree_bufnr = tonumber(tree_bufnr_str)
      local ok, err = pcall(setup_buffer, bufnr, tree_bufnr)
      if not ok then
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
          "-- tree_preview error:",
          "-- " .. tostring(err),
        })
        vim.bo[bufnr].modifiable = false
      end
    end,
  })

  -- Cleanup on buffer wipeout
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      cleanup_buffer(ev.buf)
    end,
  })

  -- No public API - users interact via :edit dap://tree-preview/{bufnr}
  return {}
end
