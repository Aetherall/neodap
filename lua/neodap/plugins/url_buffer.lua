-- Plugin: URL debug buffer using entity_buffer framework
-- Displays resolved URIs from a URL query, one per line.
-- Useful for debugging and designing other plugins.
--
-- URI format:
--   dap://url/@session/threads       - Watch URL reactively
--   dap://url/@frame/scopes          - Watch scopes of focused frame
--   dap://url/sessions               - Absolute URL
--
-- Buffer content shows resolved entity URIs, updating reactively.

local entity_buffer = require("neodap.plugins.utils.entity_buffer")

---@param debugger neodap.entities.Debugger
return function(debugger)
  -- Initialize entity_buffer with debugger
  entity_buffer.init(debugger)

  ---Extract URIs from entities
  ---@param entities any Entity, array of entities, or nil
  ---@return string[] uris
  local function extract_uris(entities)
    if entities == nil then
      return {}
    end

    -- Single entity (has uri signal)
    if type(entities) == "table" and entities.uri then
      return { entities.uri:get() }
    end

    -- Array of entities
    if type(entities) == "table" then
      local uris = {}
      for _, entity in ipairs(entities) do
        if entity and entity.uri then
          table.insert(uris, entity.uri:get())
        end
      end
      return uris
    end

    return {}
  end

  -- Register dap://url scheme
  entity_buffer.register("dap://url", nil, "many", {
    optional = true, -- Allow empty results

    -- Render entity URIs to buffer
    render = function(bufnr, entities)
      local url = entity_buffer.get_url(bufnr) or "?"
      local uris = extract_uris(entities)

      local lines = {}
      table.insert(lines, "# " .. url)
      table.insert(lines, "# " .. #uris .. " result(s)")
      table.insert(lines, "")

      for _, uri in ipairs(uris) do
        table.insert(lines, uri)
      end

      if #uris == 0 then
        table.insert(lines, "# (no results)")
      end

      return table.concat(lines, "\n")
    end,

    -- Setup: set filetype
    setup = function(bufnr, entities, options)
      vim.bo[bufnr].filetype = "neodap-url"
    end,

    -- Always update (read-only, no dirty tracking needed)
    on_change = "always",
  })

  -- Return public API
  return {
    ---Refresh a URL buffer manually
    ---@param bufnr? number Buffer number (default: current)
    refresh = function(bufnr)
      -- entity_buffer handles refresh via watch subscription
      -- Manual refresh triggers re-render by re-reading watch
      bufnr = bufnr or vim.api.nvim_get_current_buf()
      local url = entity_buffer.get_url(bufnr)
      if url then
        -- Force re-render by toggling modifiable
        vim.bo[bufnr].modifiable = true
        vim.bo[bufnr].modifiable = false
      end
    end,

    ---Get the URL being watched by a buffer
    ---@param bufnr? number Buffer number (default: current)
    ---@return string? url
    get_url = function(bufnr)
      return entity_buffer.get_url(bufnr)
    end,

    ---Open a URL buffer
    ---@param url string URL to watch
    ---@param opts? { split?: "horizontal"|"vertical"|"tab" }
    open = function(url, opts)
      opts = opts or {}
      local uri = "dap://url/" .. url

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
