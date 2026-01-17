-- Plugin: Inline variable values as virtual text
--
-- Shows variable values inline in source buffers during debugging.
-- Uses treesitter locals.scm queries to find variable definitions.

local a = require("neodap.async")
local scoped = require("neodap.scoped")

local default_config = {
  max_lines = 30,
  max_length = 50,
  hl_group = "DapInlineValue",
}

---@param debugger neodap.entities.Debugger
---@param config? table
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local ns = vim.api.nvim_create_namespace("neodap_inline_values")
  vim.api.nvim_set_hl(0, "DapInlineValue", { fg = "#89b4fa", italic = true, default = true })

  local plugin_scope = scoped.current()
  local augroup = vim.api.nvim_create_augroup("NeodapInlineValues", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(ev)
      local bufnr = ev.buf
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      if vim.b[bufnr].neodap_inline_values then return end
      if vim.api.nvim_buf_get_name(bufnr) == "" then return end

      vim.b[bufnr].neodap_inline_values = true
      local buffer_scope = scoped.createScope(plugin_scope)

      vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete" }, {
        buffer = bufnr,
        once = true,
        callback = function() buffer_scope:cancel() end,
      })

      scoped.withScope(buffer_scope, function()
        debugger.ctx.frame:use(function(frame)
          if not vim.api.nvim_buf_is_valid(bufnr) then return end
          if not frame or not frame:isStopped() then return end
          local loc = frame:location()
          if not loc or not loc.line or loc:bufnr() ~= bufnr then return end

          -- Get treesitter parser
          local lang = vim.bo[bufnr].filetype
          if lang == "" then return end
          local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
          if not ok then return end
          local tree = parser:parse()[1]
          if not tree then return end

          -- Get defined names from locals.scm
          local defined
          local lok, locals = pcall(vim.treesitter.query.get, lang, "locals")
          if lok and locals then
            defined = {}
            for id, node in locals:iter_captures(tree:root(), bufnr) do
              if locals.captures[id]:match("^local%.definition") then
                local text = vim.treesitter.get_node_text(node, bufnr)
                if text then defined[text] = true end
              end
            end
          end

          local iok, id_query = pcall(vim.treesitter.query.parse, lang, "(identifier) @id")
          if not iok then return end

          -- Collect id -> lines
          local start_line = math.max(0, loc.line - 1 - config.max_lines)
          local end_line = math.min(vim.api.nvim_buf_line_count(bufnr), loc.line + config.max_lines)
          local id_lines, seen = {}, {}
          for _, node in id_query:iter_captures(tree:root(), bufnr, start_line, end_line) do
            local text = vim.treesitter.get_node_text(node, bufnr)
            if text and not text:match("^[A-Z]") and (not defined or defined[text]) then
              local row = node:start()
              if not seen[text .. ":" .. row] then
                seen[text .. ":" .. row] = true
                id_lines[text] = id_lines[text] or {}
                table.insert(id_lines[text], row)
              end
            end
          end

          -- Each identifier evaluates and renders itself
          for id, lines in pairs(id_lines) do
            a.run(function()
              local result = frame:evaluate(id)
              if not result then return end
              local v = tostring(result):gsub("%s+", " ")
              local display = #v > config.max_length and v:sub(1, config.max_length) .. "..." or v
              vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(bufnr) then return end
                for _, line in ipairs(lines) do
                  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, 0, {
                    virt_text = { { "  " .. id .. " = " .. display, config.hl_group } },
                    virt_text_pos = "eol",
                  })
                end
              end)
            end)
          end

          return function()
            pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
          end
        end)
      end)
    end,
  })

  vim.api.nvim_create_user_command("DapInlineValues", function()
    -- Trigger refresh by re-setting focusedUrl (causes subscribers to re-run)
    local url = debugger.focusedUrl:get()
    if url then debugger.focusedUrl:set(url) end
  end, {})

  local function clear()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
    end
  end

  return {
    clear = clear,
    refresh = function()
      -- Trigger refresh by re-setting focusedUrl (causes subscribers to re-run)
      local url = debugger.focusedUrl:get()
      if url then debugger.focusedUrl:set(url) end
    end,
    cleanup = function()
      pcall(vim.api.nvim_del_user_command, "DapInlineValues")
      pcall(vim.api.nvim_del_augroup_by_name, "NeodapInlineValues")
      plugin_scope:cancel()
    end,
  }
end
