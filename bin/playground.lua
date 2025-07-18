#!/usr/bin/env -S NEODAP_PLAYGROUND=1 nvim -u NONE -U NONE -N -i NONE -V1 -S


-- Set up isolated playground environment
vim.env.LAZY_STDPATH = ".cache/playground"

-- Bootstrap lazy.nvim
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Set up leader key early
vim.g.mapleader = " "

-- Use lazy.nvim's minit functionality for playground
require("lazy.minit").repro({
    spec = {
        -- Core dependencies for neodap
        {
            "nvim-neotest/nvim-nio",
            lazy = false,
        },
        {
            "nvim-lua/plenary.nvim",
            lazy = false,
        },
        {
            "MunifTanjim/nui.nvim",
            lazy = false,
        },
        {
            "nvim-telescope/telescope.nvim",
            lazy = false,
        },

        -- Additional development plugins for enhanced playground experience
        {
            "folke/trouble.nvim",
            lazy = true,
            cmd = "Trouble",
            keys = {
                { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",              desc = "Diagnostics (Trouble)" },
                { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics (Trouble)" },
            },
        },

        {
            "nvim-treesitter/nvim-treesitter",
            lazy = false,
            config = function()
                require("nvim-treesitter.configs").setup({
                    ensure_installed = { "lua", "javascript", "typescript" },
                    highlight = { enable = true },
                    indent = { enable = true },
                })
            end,
        },

        -- Add neodap itself as a plugin from current directory
        {
            dir = ".",
            name = "neodap",
            lazy = false,
        },
    },

    -- Enhanced configuration for playground
    performance = {
        cache = {
            enabled = true,
        },
        reset_packpath = false,
    },

    -- Better UI for development
    ui = {
        border = "rounded",
        backdrop = 60,
    },

    -- Development-friendly settings
    dev = {
        path = ".",
        patterns = { "neodap" },
        fallback = false,
    },

    headless = {
        process = false,
        log = os.getenv("LAZY_DEBUG") and true or false,
        task = os.getenv("LAZY_DEBUG") and true or false,
        colors = os.getenv("LAZY_DEBUG") and true or false,
    },
})

-- Set tabstop=1 to ensure buffer positions match screen positions
-- This is critical for terminal snapshot tests where visual markers need to align
vim.opt.tabstop = 1
vim.opt.shiftwidth = 1
vim.opt.expandtab = false

-- Debug output after setup
if os.getenv("LAZY_DEBUG") then
    print("lazy-lua-interpreter: lazy.nvim setup complete")
    print("lazy-lua-interpreter: Ready to execute piped Lua code")
end

-- Function to get lua code from various sources
local function get_lua_code()
    local input_lines = {}

    -- Check command line arguments first
    local args = vim.v.argv or {}

    if os.getenv("LAZY_DEBUG") then
        print("lazy-lua-interpreter: Processing args:", vim.inspect(args))
    end

    -- Look for arguments that come after the script name
    local script_found = false
    for i = 1, #args do
        local arg = args[i]

        -- Skip until we find our interpreter script
        if arg:match("playground.lua$") then
            script_found = true
        elseif script_found and not arg:match("^-") then
            -- This is our argument after the script name
            if vim.fn.filereadable(arg) == 1 then
                -- It's a file, read it
                local file_content = vim.fn.readfile(arg)
                if file_content then
                    table.insert(input_lines, table.concat(file_content, "\n"))
                    if os.getenv("LAZY_DEBUG") then
                        print("lazy-lua-interpreter: Reading code from file:", arg)
                    end
                end
            else
                -- Treat as lua code string
                if arg:len() > 0 then
                    table.insert(input_lines, arg)
                    if os.getenv("LAZY_DEBUG") then
                        print("lazy-lua-interpreter: Using code from argument:", arg)
                    end
                end
            end
            -- Only process the first non-flag argument after script name
            break
        end
    end

    -- If no arguments, try to read from stdin
    if #input_lines == 0 then
        local ok, stdin_input = pcall(io.read, "*a")
        if ok and stdin_input and stdin_input:len() > 0 then
            -- Clean up the input - remove trailing whitespace but preserve the code structure
            stdin_input = stdin_input:gsub("%s*$", "")

            -- Don't split by lines, keep the input as a single block of code
            if stdin_input:len() > 0 then
                table.insert(input_lines, stdin_input)
                if os.getenv("LAZY_DEBUG") then
                    print("lazy-lua-interpreter: Reading code from stdin")
                end
            end
        end
    end

    -- Join all input lines into a single string
    return table.concat(input_lines, "\n")
end

-- Function to execute lua code
local function execute_code()
    local lua_code = get_lua_code()

    if lua_code and lua_code:len() > 0 then
        if os.getenv("LAZY_DEBUG") then
            print("lazy-lua-interpreter: Executing Lua code:")
            print("--- BEGIN CODE ---")
            print(lua_code)
            print("--- END CODE ---")
        end

        -- Execute the lua code with better error handling
        local success, result = pcall(function()
            -- Use load() instead of loadstring() for better Lua 5.1+ compatibility
            local func, err = load(lua_code, "user_code", "t")
            if not func then
                error("Syntax error: " .. tostring(err))
            end
            return func()
        end)

        if success then
            if os.getenv("LAZY_DEBUG") then
                print("lazy-lua-interpreter: Code executed successfully")
            end
            if result ~= nil then
                print(vim.inspect(result))
            end
        else
            print("Error executing Lua code:", result)
            vim.cmd("cquit 1")
        end
    else
        if os.getenv("LAZY_DEBUG") then
            print("lazy-lua-interpreter: No code to execute")
        end
    end
end

vim.schedule(function()
    execute_code()
end)
