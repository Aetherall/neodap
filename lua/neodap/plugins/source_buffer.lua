local uri_module = require("neodap.sdk.uri")

local M = {}

---Setup the URI handler
---@param debugger Debugger
function M.setup(debugger)
    local group = vim.api.nvim_create_augroup("neodap-uri-handler", { clear = true })

    vim.api.nvim_create_autocmd("BufReadCmd", {
        pattern = "dap:source:*",
        group = group,
        callback = function(opts)
            local bufnr = opts.buf
            local uri = opts.file

            -- Setup buffer options for virtual source
            vim.bo[bufnr].buftype = "nofile"
            vim.bo[bufnr].bufhidden = "hide"
            vim.bo[bufnr].swapfile = false
            vim.bo[bufnr].modifiable = false

            -- Parse URI using uri module
            local parsed = uri_module.parse(uri)

            if not parsed or parsed.type ~= "source" then
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                    "-- Error: Invalid DAP URI format",
                    "-- Expected: dap:source:<correlation_key>",
                    "-- Received: " .. uri
                })
                return
            end

            -- Find source by correlation_key (O(1) lookup using index)
            local source = debugger.sources:get_one("by_correlation_key", parsed.id)

            if not source then
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                    "-- Error: Source not found",
                    "-- Correlation key: " .. parsed.id
                })
                return
            end

            -- Request source content via SDK
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "-- Loading source..." })

            source:fetch_content(function(err, content)
                if not vim.api.nvim_buf_is_valid(bufnr) then return end

                vim.schedule(function()
                    if err then
                        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                            "-- Error loading source:",
                            "-- " .. tostring(err)
                        })
                        return
                    end

                    -- Split content into lines
                    local lines = vim.split(content or "", "\n")

                    -- Set buffer content
                    vim.bo[bufnr].modifiable = true
                    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                    vim.bo[bufnr].modifiable = false
                    vim.bo[bufnr].modified = false
                end)
            end)
        end
    })

    -- Cleanup on debugger dispose
    debugger:on_dispose(function()
        pcall(vim.api.nvim_del_augroup_by_id, group)
    end)

    -- Return cleanup function
    return function()
        pcall(vim.api.nvim_del_augroup_by_id, group)
    end
end

return M
