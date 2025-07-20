vim.g.mapleader = " "

local function go()
    local Manager              = require("neodap.session.manager")
    local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")
    local Session              = require("neodap.session.session")
    local nio                  = require("nio")
    local Api                  = require("neodap.api.Api")
    local manager              = Manager.create()

    local adapter              = ExecutableTCPAdapter.create({
        executable = {
            cmd = "js-debug",
            cwd = vim.fn.getcwd(),
        },
        connection = {
            host = "::1",
        },
    })

    local namespace            = vim.api.nvim_create_namespace("neodap")
    vim.api.nvim_set_hl(namespace, "Default", { fg = "#ffffff", bg = "#000000" })




    local api = Api.register(manager)

    -- -- local HighlightCurrentFrame = require("neodap.plugins.HighlightCurrentFrame")
    -- local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
    -- local BreakpointApi = require("neodap.plugins.BreakpointApi")
    -- -- local FrameVariables = require("neodap.plugins.FrameVariables")
    -- local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
    -- local StackNavigation = require("neodap.plugins.StackNavigation")
    -- local FrameHighlight = require("neodap.plugins.FrameHighlight")
    -- -- local CallStackViewer = require("neodap.plugins.CallStackViewer")

    api:getPluginInstance(require("neodap.plugins.JumpToStoppedFrame"))
    api:getPluginInstance(require("neodap.plugins.BreakpointVirtualText"))
    api:getPluginInstance(require("neodap.plugins.BreakpointApi"))
    -- api:getPluginInstance(require("neodap.plugins.FrameVariables"))
    local stack = api:getPluginInstance(require("neodap.plugins.StackNavigation"))
    local brkpt = api:getPluginInstance(require("neodap.plugins.ToggleBreakpoint"))
    api:getPluginInstance(require("neodap.plugins.FrameHighlight"))
    api:getPluginInstance(require("neodap.plugins.DebugMode"))
    api:getPluginInstance(require("neodap.plugins.SimpleVariableTree4"))
    -- api:getPluginInstance(require("neodap.plugins.ScopeViewer"))

    local neotree = require('neo-tree')

    neotree.setup({
        sources = {
            "neodap.plugins.SimpleVariableTree4",
        },
    })

    local currentStopped = nil


    api:onSession(function(session)
        session:onOutput(function(body)
            -- print("Output from session " .. session.id .. ": " .. body.output)
        end)

        session:onThread(function(thread, body)
            vim.t = thread
            thread:onStopped(function(body)
                currentStopped = thread
            end)

            thread:onResumed(function()
                currentStopped = nil
            end)
        end)
    end)

    vim.keymap.set("n", "<leader>db", function()
        toggleBreakpoint:Toggle()
    end, { noremap = true, silent = true, desc = "Toggle Breakpoint" })

    vim.keymap.set("n", "<leader>dc", function()
        if currentStopped then
            currentStopped:continue()
        end
    end, { noremap = true, silent = true, desc = "Continue All Threads" })

    vim.keymap.set("n", "<leader>ds", function()
        if currentStopped then
            currentStopped:stepIn()
        end
    end, { noremap = true, silent = true, desc = "Step Into" })

    vim.keymap.set("n", "<leader>do", function()
        if currentStopped then
            currentStopped:stepOver()
        end
    end, { noremap = true, silent = true, desc = "Step Over" })


    vim.keymap.set("n", "<leader>du", function()
        stack:Up()
    end, { noremap = true, silent = true, desc = "Step Out" })


    vim.keymap.set("n", "<leader>dd", function()
        stack:Down()
    end, { noremap = true, silent = true, desc = "Jump to Stopped Frame" })

    -- Add command to show log file path
    vim.keymap.set("n", "<leader>dl", function()
        local get_log_path = require('neodap.tools.get_log_path')
        local log_path = get_log_path()
        -- Write to cmdline instead of notify to avoid prompt
        vim.api.nvim_echo({ { "Log file: " .. log_path, "Normal" } }, false, {})
    end, { noremap = true, silent = true, desc = "Show Debug Log Path" })

    -- Add keybinding for frame variables
    vim.keymap.set("n", "<leader>dv", function()
        vim.cmd("NeodapVariablesFloat")
    end, { noremap = true, silent = true, desc = "Show Frame Variables" })

    api:onSession(function(session)
        session:onSourceLoaded(function(source)
            -- Only process file sources
            if source:isFile() then
                if source:filename() == "recurse.js" then
                    -- Use ToggleBreakpoint plugin to add breakpoint
                    local Location = require('neodap.api.Location')
                    local location = Location.fromSource(source, { line = 3, column = 1 })
                    brkpt:toggle(location)
                end
            end
        end)
    end)

    local session = Session.create({
        manager = manager,
        adapter = adapter,
    })


    ---@async
    nio.run(function()
        session:start({
            configuration = {
                type = "pwa-node",
                program = vim.fn.getcwd() .. "/spec/fixtures/recurse.js",
                cwd = vim.fn.getcwd(),
            },
            request = "launch",
        })

        nio.sleep(1000)
    end)
end


go()
