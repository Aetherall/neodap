local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local StackNavigation = require("neodap.plugins.StackNavigation")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local NvimAsync = require("neodap.tools.async")

---@class neodap.plugin.ScopeViewerProps
---@field api Api
---@field logger Logger
---@field stackNavigation neodap.plugin.StackNavigation
---@field debugOverlay neodap.plugin.DebugOverlay
---@field scopes table[]
---@field scope_map table<integer, api.Scope>
---@field current_frame api.Frame | nil
---@field highlight_namespace integer
---@field expanded_scopes table<integer, boolean>

---@class neodap.plugin.ScopeViewer: neodap.plugin.ScopeViewerProps
---@field new Constructor<neodap.plugin.ScopeViewerProps>
local ScopeViewer = Class()

ScopeViewer.name = "ScopeViewer"
ScopeViewer.description = "Visual scope viewer for debugging sessions"

function ScopeViewer.plugin(api)
    local logger = Logger.get("ScopeViewer")

    local instance = ScopeViewer:new({
        api = api,
        logger = logger,
        stackNavigation = api:getPluginInstance(StackNavigation),
        debugOverlay = api:getPluginInstance(DebugOverlay),
        scopes = {},
        scope_map = {},
        current_frame = nil,
        highlight_namespace = vim.api.nvim_create_namespace("neodap_scope_viewer"),
        expanded_scopes = {},
    })

    instance:listen()

    return instance
end

function ScopeViewer:get_current_frame()
    -- Get the smart closest frame for current cursor position
    local cursor = Location.fromCursor()
    if not cursor then
        return nil
    end

    return self.stackNavigation:getSmartClosestFrame(cursor)
end

function ScopeViewer:show()
    local frame = self:get_current_frame()
    if not frame then
        return
    end

    if not self.debugOverlay:is_open() then
        self.debugOverlay:show()
    end

    self:Render(frame)
end

function ScopeViewer:hide()
    self.debugOverlay:clear_left_panel()
end

function ScopeViewer:toggle()
    if self.debugOverlay:is_open() then
        self:hide()
    else
        self:show()
    end
end

function ScopeViewer:listen()
    self.api:onSession(function(session)
        session:onThread(function(thread)
            thread:onStopped(function(stopped_event)
                -- Automatically show the overlay when debug session stops (breakpoint hit, etc.)
                if not self.debugOverlay:is_open() then
                    self.debugOverlay:show()
                end

                local frame = self:get_current_frame()
                if frame then
                    self:Render(frame)
                end
            end)

            thread:onResumed(function()
                if self.debugOverlay:is_open() then
                    self.debugOverlay:clear_left_panel()
                end
            end)
        end)

        session:onTerminated(function()
            self:hide()
        end)
    end, { name = self.name .. ".onSession" })

    -- Listen for stack navigation events
    vim.api.nvim_create_autocmd("User", {
        pattern = "NeodapStackNavigationChanged",
        callback = function(event)
            self:OnNavigationChanged(event.data)
        end,
        group = vim.api.nvim_create_augroup("NeodapScopeViewer", { clear = true }),
    })

    -- Listen for cursor movement to update ScopeViewer
    vim.api.nvim_create_autocmd("CursorMoved", {
        callback = function()
            self:OnGlobalCursorMoved()
        end,
        group = vim.api.nvim_create_augroup("NeodapScopeViewer", { clear = false }),
    })

    -- Listen for overlay left panel selection events
    vim.api.nvim_create_autocmd("User", {
        pattern = "NeodapDebugOverlayLeftSelect",
        callback = function(event)
            self:OnPanelSelect(event.data.line)
        end,
        group = vim.api.nvim_create_augroup("NeodapScopeViewer", { clear = false }),
    })

    -- Listen for overlay left panel toggle events
    vim.api.nvim_create_autocmd("User", {
        pattern = "NeodapDebugOverlayLeftToggle",
        callback = function(event)
            self:OnPanelToggle(event.data.line)
        end,
        group = vim.api.nvim_create_augroup("NeodapScopeViewer", { clear = false }),
    })
end


-- Event Handling Methods
function ScopeViewer:OnNavigationChanged(event_data)
    -- Only update if overlay is open
    if not self.debugOverlay:is_open() then
        return
    end

    -- Get the current frame and render its scopes
    local frame = self:get_current_frame()
    if frame then
        self:Render(frame)
    end
end

function ScopeViewer:OnGlobalCursorMoved()
    -- Only update if overlay is open
    if not self.debugOverlay:is_open() then
        return
    end

    -- Skip if cursor is in any overlay window
    local current_win = vim.api.nvim_get_current_win()
    if self.debugOverlay:is_managed_window(current_win) then
        return
    end

    -- Get the smart closest frame for current cursor position
    local frame = self:get_current_frame()
    if not frame then
        return
    end

    -- Update ScopeViewer to show scopes for the current frame
    if not self.current_frame or self.current_frame.ref.id ~= frame.ref.id then
        self:Render(frame)
    end
end

-- Panel interaction methods
function ScopeViewer:OnPanelSelect(line)
    local scope = self.scope_map[line]
    if scope then
        self:toggle_scope_expansion(scope)
    end
end

function ScopeViewer:OnPanelToggle(line)
    local scope = self.scope_map[line]
    if scope then
        self:toggle_scope_expansion(scope)
    end
end

function ScopeViewer:toggle_scope_expansion(scope)
    local ref = scope.ref.variablesReference
    if ref and ref > 0 then
        self.expanded_scopes[ref] = not self.expanded_scopes[ref]
        if self.current_frame then
            self:Render(self.current_frame)
        end
    end
end

function ScopeViewer:setup_highlights()
    vim.cmd([[
    highlight default NeodapScopeExpanded guifg=#7aa2f7 gui=bold
    highlight default NeodapScopeCollapsed guifg=#9ece6a
    highlight default NeodapScopeVariable guifg=#e0af68
    highlight default NeodapScopeValue guifg=#f7768e
    highlight default NeodapScopeType guifg=#bb9af7
  ]])
end

-- Rendering Methods
function ScopeViewer:Render(frame)
    if not frame then
        self.debugOverlay:set_left_panel_content({ "No frame available" }, {}, { scope_map = {} })
        return
    end

    self.current_frame = frame
    local scopes = frame:scopes()

    if not scopes or #scopes == 0 then
        self.debugOverlay:set_left_panel_content({ "No scopes available" }, {}, { scope_map = {} })
        return
    end

    local lines = {}
    local highlights = {}
    self.scope_map = {}

    for i, scope in ipairs(scopes) do
        local line_parts = {}
        local hl_parts = {}

        -- Add expand/collapse indicator
        local ref = scope.ref.variablesReference
        local is_expandable = ref and ref > 0
        local is_expanded = self.expanded_scopes[ref]

        if is_expandable then
            local indicator = is_expanded and "▼ " or "▶ "
            table.insert(line_parts, indicator)
            table.insert(hl_parts, { 0, #indicator, is_expanded and "NeodapScopeExpanded" or "NeodapScopeCollapsed" })
        else
            table.insert(line_parts, "  ")
        end

        -- Add scope name
        local name = scope.ref.name or "Unknown"
        table.insert(line_parts, name)
        local name_start = #table.concat(line_parts, "") - #name
        table.insert(hl_parts, { name_start, name_start + #name, "NeodapScopeExpanded" })

        -- Add scope type if available
        if scope.ref.expensive then
            table.insert(line_parts, " (expensive)")
            local type_start = #table.concat(line_parts, "") - 11
            table.insert(hl_parts, { type_start, type_start + 11, "NeodapScopeType" })
        end

        local line = table.concat(line_parts, "")
        table.insert(lines, line)
        table.insert(highlights, hl_parts)
        self.scope_map[#lines] = scope

        -- Add variables if scope is expanded
        if is_expanded then
            local variables = scope:variables()
            if variables then
                for _, variable in ipairs(variables) do
                    local var_line = self:format_variable(variable, 1)
                    table.insert(lines, var_line.text)
                    table.insert(highlights, var_line.highlights)
                    self.scope_map[#lines] = scope -- Map to parent scope
                end
            end
        end
    end

    -- Send content to debug overlay
    self.debugOverlay:set_left_panel_content(lines, highlights, { scope_map = self.scope_map })

    -- Set up highlights
    self:setup_highlights()
end

function ScopeViewer:format_variable(variable, indent)
    local line_parts = {}
    local hl_parts = {}

    -- Add indentation
    local indent_str = string.rep("  ", indent)
    table.insert(line_parts, indent_str)

    -- Add variable name
    local name = variable.name or "unknown"
    table.insert(line_parts, name)
    local name_start = #table.concat(line_parts, "") - #name
    table.insert(hl_parts, { name_start, name_start + #name, "NeodapScopeVariable" })

    -- Add value if available
    if variable.value then
        table.insert(line_parts, " = ")
        local value = tostring(variable.value)
        if #value > 40 then
            value = value:sub(1, 40) .. "..."
        end
        table.insert(line_parts, value)
        local value_start = #table.concat(line_parts, "") - #value
        table.insert(hl_parts, { value_start, value_start + #value, "NeodapScopeValue" })
    end

    -- Add type if available
    if variable.type then
        table.insert(line_parts, " : ")
        table.insert(line_parts, variable.type)
        local type_start = #table.concat(line_parts, "") - #variable.type
        table.insert(hl_parts, { type_start, type_start + #variable.type, "NeodapScopeType" })
    end

    return {
        text = table.concat(line_parts, ""),
        highlights = hl_parts
    }
end

return ScopeViewer