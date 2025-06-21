local nio = require("nio")

local name = "VirtualTextValues"
return {
  name = name,
  description = "Plugin to display virtual text values in the editor",
  ---@param api Api
  plugin = function(api)
    local namespace = vim.api.nvim_create_namespace(name)

    local printForPosition = function(bufnr, path, line, column)

    end


    api:onSession(function(session)
      session:onThread(function(thread)
        thread:onStopped(function()
          local stack = thread:stack()
          if not stack then
            return
          end

          printForPosition = function(bufnr, path, line, column)
            local top = stack:top()

            local scopes = top:scopes()


            for _, scope in ipairs(scopes) do
              if scope.ref.source then
                local src = session:getSourceFor(scope.ref.source)
                if not src then
                  return
                end

                local ranged = scope:isRanged()

                -- print(vim.inspect({ src = src.ref, scope = scope.ref, }))


                if ranged then
                  local start, finish = ranged:region()

                  local variables = scope:variables()
                  if not variables then
                    return
                  end

                  -- print(vim.print(variables))

                  local variablesSummary = table.concat(
                    vim.tbl_map(function(var)
                      return (var.ref.name or "nil") .. ": " .. (var.ref.value or "nil")
                    end, variables),
                    ", "
                  )

                  vim.schedule(function()
                    vim.api.nvim_buf_set_extmark(bufnr, namespace, start[1], start[2], {
                      virt_text = { { scope.ref.name .. ": " .. variablesSummary, "Comment" } },
                      virt_text_pos = "eol",
                      hl_mode = "replace",
                    })
                  end)
                end
              end
            end
          end

          vim.schedule(function()
            local bufnr = vim.api.nvim_get_current_buf()
            vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
            local path = vim.api.nvim_buf_get_name(bufnr)
            local line = vim.api.nvim_win_get_cursor(0)[1] - 1
            local column = vim.api.nvim_win_get_cursor(0)[2] + 1
            nio.run(function() printForPosition(bufnr, path, line, column) end)
          end)
        end, { name = name .. ".onStopped" })
      end, { name = name .. ".onThread" })
    end, { name = name .. ".onSession" })


    vim.api.nvim_create_autocmd("CursorHold", {
      group = vim.api.nvim_create_augroup(name, { clear = true }),
      callback = function()
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
        local path = vim.api.nvim_buf_get_name(bufnr)
        local line = vim.api.nvim_win_get_cursor(0)[1] - 1
        local column = vim.api.nvim_win_get_cursor(0)[2] + 1
        nio.run(function() printForPosition(bufnr, path, line, column) end)
      end,
    })
  end
}
