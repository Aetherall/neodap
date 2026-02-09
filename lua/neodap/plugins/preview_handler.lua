-- Plugin: Preview Handler
-- Routes entity URIs to appropriate display renderers via inline rendering.
--
-- URI format:
--   dap://preview/{entity_uri}
--
-- Examples:
--   dap://preview/source:abc           - Preview a source entity
--   dap://preview/variable:session:123 - Preview a variable
--   dap://preview/frame:session:42:0   - Preview a frame (shows source at location)
--
-- The preview buffer stays as dap://preview/... but delegates rendering
-- to other registered schemes (dap://source/, dap://var/, etc.)
--
-- Unlike other entity buffers, this uses uri.resolve() to find entities
-- by their URI rather than watching a URL path.

local entity_buffer = require("neodap.plugins.utils.entity_buffer")
local uri_module = require("neodap.uri")

---@class neodap.plugins.preview_handler.Config
---@field handlers? table<string, neodap.plugins.preview_handler.Handler> Entity type -> handler mapping

---@alias neodap.plugins.preview_handler.Handler
---| { scheme: string } Direct scheme mapping
---| fun(entity: table): { scheme: string, entity?: table, options?: table }? Function that transforms entity

---@param debugger neodap.entities.Debugger
---@param config? neodap.plugins.preview_handler.Config
return function(debugger, config)
  config = config or {}

  -- State local to this plugin instance
  local buffers = {}  -- bufnr -> { entity_uri, entity }
  local handlers = {}  -- entity_type -> handler

  -- Merge config handlers
  if config.handlers then
    for entity_type, handler in pairs(config.handlers) do
      handlers[entity_type] = handler
    end
  end

  -- Initialize entity_buffer for get_renderer/get_setup access
  entity_buffer.init(debugger)

  --- Get handler for entity type
  ---@param entity_type string
  ---@return neodap.plugins.preview_handler.Handler?
  local function get_handler(entity_type)
    return handlers[entity_type] or handlers.default
  end

  --- Resolve handler to get target scheme and entity
  ---@param handler neodap.plugins.preview_handler.Handler?
  ---@param entity table
  ---@return { scheme: string, entity: table, options?: table }
  local function resolve_handler(handler, entity)
    if type(handler) == "function" then
      local result = handler(entity)
      if result then
        return {
          scheme = result.scheme,
          entity = result.entity or entity,
          options = result.options,
        }
      end
    elseif type(handler) == "table" and handler.scheme then
      return { scheme = handler.scheme, entity = entity }
    end

    -- Default: use dap://url/ style display
    return { scheme = "dap://url", entity = entity }
  end

  --- Format entity for fallback display
  ---@param entity table
  ---@return string
  local function format_fallback(entity)
    local lines = {}
    table.insert(lines, "# Preview")
    table.insert(lines, "")

    if entity.uri then
      table.insert(lines, "URI: " .. entity.uri:get())
    end

    if entity.type then
      table.insert(lines, "Type: " .. entity:type())
    end

    local title = debugger:render_text(entity, { "title" })
    if title ~= "" then
      table.insert(lines, "Name: " .. title)
    end

    local value = debugger:render_text(entity, { "value" })
    if value ~= "" then
      table.insert(lines, "")
      table.insert(lines, "Value:")
      table.insert(lines, value)
    end

    return table.concat(lines, "\n")
  end

  --- Set buffer content
  ---@param bufnr number
  ---@param content string|string[]
  local function set_content(bufnr, content)
    local lines
    if type(content) == "string" then
      lines = vim.split(content, "\n")
    else
      lines = content
    end

    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
  end

  --- Render preview for an entity
  ---@param bufnr number
  ---@param entity table
  local function render_preview(bufnr, entity)
    local entity_type = entity:type()
    local handler = get_handler(entity_type)
    local target = resolve_handler(handler, entity)

    -- Get the target scheme's render function
    local render_fn = entity_buffer.get_renderer(target.scheme)
    local content
    if render_fn then
      -- Delegate to the target renderer
      content = render_fn(bufnr, target.entity)
    else
      -- Fallback: show entity info
      content = format_fallback(entity)
    end

    set_content(bufnr, content or "")

    -- Call setup if available
    local setup_fn = entity_buffer.get_setup(target.scheme)
    if setup_fn then
      setup_fn(bufnr, target.entity, target.options or {})
    else
      vim.bo[bufnr].filetype = "neodap-preview"
    end
  end

  --- Setup preview buffer
  ---@param bufnr number
  ---@param entity_uri string
  local function setup_buffer(bufnr, entity_uri)
    -- Buffer options
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false

    -- Resolve entity by URI
    local entity = uri_module.resolve(debugger, entity_uri)

    if not entity then
      set_content(bufnr, { "-- Entity not found", "-- URI: " .. entity_uri })
      return
    end

    -- Store state
    buffers[bufnr] = {
      entity_uri = entity_uri,
      entity = entity,
    }

    -- Initial render
    render_preview(bufnr, entity)
  end

  -- Create autocmd for dap://preview/* scheme
  local group = vim.api.nvim_create_augroup("neodap-preview-handler", { clear = true })

  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = "dap://preview/*",
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      local uri = ev.file

      -- Parse: dap://preview/{entity_uri}
      local entity_uri = uri:match("^dap://preview/(.+)$")
      if not entity_uri then
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
          "-- Invalid preview URI",
          "-- " .. uri,
        })
        vim.bo[bufnr].modifiable = false
        return
      end

      local ok, err = pcall(setup_buffer, bufnr, entity_uri)
      if not ok then
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
          "-- preview_handler error:",
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
      buffers[ev.buf] = nil
    end,
  })

  -- Return public API
  return {
    ---Register a handler for an entity type
    ---@param entity_type string Entity type name
    ---@param handler neodap.plugins.preview_handler.Handler Handler configuration
    register_handler = function(entity_type, handler)
      handlers[entity_type] = handler
    end,

    ---Get current handlers configuration
    ---@return table<string, neodap.plugins.preview_handler.Handler>
    get_handlers = function()
      return handlers
    end,

    ---Refresh preview buffer with new entity URI
    ---@param bufnr number Buffer number
    ---@param entity_uri string New entity URI to preview
    refresh = function(bufnr, entity_uri)
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      -- Resolve entity
      local entity = uri_module.resolve(debugger, entity_uri)
      if not entity then
        set_content(bufnr, { "-- Entity not found", "-- URI: " .. entity_uri })
        return
      end

      -- Update state
      buffers[bufnr] = {
        entity_uri = entity_uri,
        entity = entity,
      }

      -- Re-render
      render_preview(bufnr, entity)

      -- Update buffer name to reflect new entity
      vim.api.nvim_buf_set_name(bufnr, "dap://preview/" .. entity_uri)
    end,

    ---Get the entity currently being previewed
    ---@param bufnr? number Buffer number (default: current)
    ---@return table? entity
    get_entity = function(bufnr)
      bufnr = bufnr or vim.api.nvim_get_current_buf()
      local state = buffers[bufnr]
      return state and state.entity
    end,

    ---Open a preview buffer for an entity URI
    ---@param entity_uri string Entity URI to preview
    ---@param opts? { split?: "horizontal"|"vertical"|"tab" }
    open = function(entity_uri, opts)
      opts = opts or {}
      local uri = "dap://preview/" .. entity_uri

      if opts.split == "horizontal" then
        vim.cmd("split " .. vim.fn.fnameescape(uri))
      elseif opts.split == "vertical" then
        vim.cmd("vsplit " .. vim.fn.fnameescape(uri))
      elseif opts.split == "tab" then
        vim.cmd("tabedit " .. vim.fn.fnameescape(uri))
      else
        vim.cmd("edit " .. vim.fn.fnameescape(uri))
      end
    end,
  }
end
