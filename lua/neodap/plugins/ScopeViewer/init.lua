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
---@field sessions table<integer, table> -- Session-scoped state
---@field cursor_debounce_timer integer | nil

---@class neodap.plugin.ScopeViewer: neodap.plugin.ScopeViewerProps
---@field new Constructor<neodap.plugin.ScopeViewerProps>
local ScopeViewer = Class()

ScopeViewer.name = "ScopeViewer"
ScopeViewer.description = "Visual scope viewer for debugging sessions"

function ScopeViewer.plugin(api)
    local logger = Logger.get("Plugin:ScopeViewer")

    local instance = ScopeViewer:new({
        api = api,
        logger = logger,
        stackNavigation = api:getPluginInstance(StackNavigation),
        debugOverlay = api:getPluginInstance(DebugOverlay),
        scopes = {},
        scope_map = {},
        current_frame = nil,
        highlight_namespace = vim.api.nvim_create_namespace("neodap_scope_viewer"),
        sessions = {}, -- Session-scoped state storage
        cursor_debounce_timer = nil,
    })

    instance:listen()
    
    -- Create vim commands for user interaction
    instance:setupCommands()

    return instance
end

function ScopeViewer:getCurrentFrame()
    -- Get the smart closest frame for current cursor position
    local cursor = Location.fromCursor()
    if not cursor then
        return nil
    end

    return self.stackNavigation:getSmartClosestFrame(cursor)
end

function ScopeViewer:show()
    if not self.debugOverlay:is_open() then
        self.debugOverlay:show()
    end

    self.logger:debug("ScopeViewer:show() called, getting session ID...")
    local session_id = self:getCurrentSessionId()
    self.logger:debug("ScopeViewer:show() got session_id:", session_id)
    
    if not session_id then
        self.logger:debug("No active session in show()")
        return
    end
    
    local session_state = self:getSessionState(session_id)
    local frame = session_state.current_frame or self:getCurrentFrame()
    
    self.logger:debug("Using frame for show():", frame and frame.ref.id or "nil", "from", session_state.current_frame and "session_state" or "getCurrentFrame")
    self.logger:debug("Session state for", session_id, ":", session_state)
    
    if not frame then
        self.logger:debug("No frame available in show(), cannot render scopes")
        return
    end

    self.logger:debug("Calling Render from show() with session_id:", session_id)
    self:Render(frame, session_id)
end

function ScopeViewer:hide()
    self.logger:debug("Hide called - clearing left panel and scope_map")
    self.debugOverlay:clear_left_panel()
    self.scope_map = {} -- Clear scope map so scopesAreVisible returns false
end

function ScopeViewer:toggle()
    -- Check if scopes are actually showing by checking if left panel has content
    -- We need to check the actual panel content, not just if overlay is open
    local overlay_open = self.debugOverlay:is_open()
    local scopes_visible = self:scopesAreVisible()
    self.logger:debug("Toggle called - overlay_open:", overlay_open, "scopes_visible:", scopes_visible)
    
    if overlay_open and scopes_visible then
        self.logger:debug("Toggle: hiding scopes")
        self:hide()
    else
        self.logger:debug("Toggle: showing scopes")
        self:show()
    end
end

function ScopeViewer:scopesAreVisible()
    -- Simple heuristic: if we have a scope_map with entries, scopes are visible
    return self.scope_map and next(self.scope_map) ~= nil
end

function ScopeViewer:listen()
    self.api:onSession(function(session)
        local session_id = session.ref.id
        self.logger:debug("Setting up session-scoped ScopeViewer for session", session_id)
        
        -- Initialize session-scoped state
        self:InitSessionState(session_id)
        
        session:onInitialized(function()
            self.logger:debug("Session", session_id, "initialized - setting up event handlers")
            self:setupSessionEvents(session)
        end)
        
        session:onThread(function(thread)
            thread:onStopped(function(stopped_event)
                -- Automatically show the overlay when debug session stops (breakpoint hit, etc.)
                if not self.debugOverlay:is_open() then
                    self.debugOverlay:show()
                end

                local frame = self:getCurrentFrame()
                if frame then
                    self:Render(frame, session_id)
                end
            end)

            thread:onResumed(function()
                if self.debugOverlay:is_open() then
                    self.debugOverlay:clear_left_panel()
                end
            end)
        end)

        session:onTerminated(function()
            self.logger:debug("Session", session_id, "terminated - cleaning up state")
            self:CleanupSessionState(session_id)
            self:hide()
        end)
    end, { name = self.name .. ".onSession" })
end


-- Session State Management
function ScopeViewer:InitSessionState(session_id)
    self.sessions[session_id] = {
        expanded_scopes = {},
        current_frame = nil,
        autocmd_group = nil -- Will be created later in setupSessionEvents
    }
    self.logger:debug("Initialized session state for session", session_id)
end

function ScopeViewer:CleanupSessionState(session_id)
    if self.sessions[session_id] then
        -- Clean up autocmds for this session
        if self.sessions[session_id].autocmd_group then
            vim.api.nvim_del_augroup_by_id(self.sessions[session_id].autocmd_group)
        end
        -- Remove session state
        self.sessions[session_id] = nil
        self.logger:debug("Cleaned up session state for session", session_id)
    end
end

function ScopeViewer:getSessionState(session_id)
    return self.sessions[session_id] or {}
end

function ScopeViewer:getCurrentSessionId()
    -- Get the active session ID from the current frame or stack navigation
    local frame = self:getCurrentFrame()
    self.logger:debug("GetCurrentSessionId: frame =", frame and frame.ref.id or "nil")
    if frame then
        self.logger:debug("GetCurrentSessionId: frame.stack =", frame.stack and "exists" or "nil")
        if frame.stack then
            self.logger:debug("GetCurrentSessionId: frame.stack.session =", frame.stack.session and "exists" or "nil")
            if frame.stack.session then
                self.logger:debug("GetCurrentSessionId: frame.stack.session.ref.id =", frame.stack.session.ref.id)
                return frame.stack.session.ref.id
            end
        end
    end
    
    -- Fallback: get the highest session ID (most recent session)
    local highest_session_id = nil
    local session_count = 0
    for session_id, _ in pairs(self.sessions) do
        session_count = session_count + 1
        if not highest_session_id or session_id > highest_session_id then
            highest_session_id = session_id
        end
    end
    
    self.logger:debug("GetCurrentSessionId: session_count =", session_count, "highest_session_id =", highest_session_id)
    if highest_session_id then
        self.logger:debug("GetCurrentSessionId: returning fallback session ID:", highest_session_id)
        return highest_session_id
    end
    
    -- Last fallback: check API for active sessions
    for session in self.api:eachSession() do
        if session and session.ref and session.ref.id then
            self.logger:debug("Found active session from API:", session.ref.id)
            return session.ref.id
        end
    end
    
    self.logger:debug("GetCurrentSessionId: returning nil")
    return nil
end

function ScopeViewer:setupSessionEvents(session)
    local session_id = session.ref.id
    local session_state = self.sessions[session_id]
    if not session_state then return end
    
    -- Create autocmd group for this session (safe context)
    session_state.autocmd_group = vim.api.nvim_create_augroup("NeodapScopeViewer_" .. session_id, { clear = true })
    
    -- Set up session-scoped autocmds
    vim.api.nvim_create_autocmd("User", {
        pattern = "NeodapStackNavigationChanged",
        callback = function(event)
            self:OnNavigationChanged(event.data, session_id)
        end,
        group = session_state.autocmd_group,
    })

    -- Debounced cursor movement handler
    vim.api.nvim_create_autocmd("CursorMoved", {
        callback = function()
            self:OnGlobalCursorMoved(session_id)
        end,
        group = session_state.autocmd_group,
    })

    -- Overlay panel interaction events
    vim.api.nvim_create_autocmd("User", {
        pattern = "NeodapDebugOverlayLeftSelect",
        callback = function(event)
            self:OnPanelSelect(event.data.line, session_id)
        end,
        group = session_state.autocmd_group,
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = "NeodapDebugOverlayLeftToggle",
        callback = function(event)
            self:OnPanelToggle(event.data.line, session_id)
        end,
        group = session_state.autocmd_group,
    })
end

-- Event Handling Methods
function ScopeViewer:OnNavigationChanged(event_data, session_id)
    -- Only update if overlay is open
    if not self.debugOverlay:is_open() then
        return
    end

    -- Get the current frame and render its scopes
    local frame = self:getCurrentFrame()
    if frame then
        self:Render(frame, session_id)
    end
end

function ScopeViewer:OnGlobalCursorMoved(session_id)
    -- Only update if overlay is open
    if not self.debugOverlay:is_open() then
        return
    end

    -- Skip if cursor is in any overlay window
    local current_win = vim.api.nvim_get_current_win()
    if self.debugOverlay:is_managed_window(current_win) then
        return
    end

    -- Debounce cursor movement to reduce excessive updates
    if self.cursor_debounce_timer then
        vim.fn.timer_stop(self.cursor_debounce_timer)
    end
    
    self.cursor_debounce_timer = vim.fn.timer_start(150, function()
        self.cursor_debounce_timer = nil
        self:handleDebouncedCursorMove(session_id)
    end)
end

function ScopeViewer:handleDebouncedCursorMove(session_id)
    -- Only update if overlay is still open
    if not self.debugOverlay:is_open() then
        return
    end
    
    local session_state = self:getSessionState(session_id)
    if not session_state then
        return
    end

    -- Get the smart closest frame for current cursor position
    local frame = self:getCurrentFrame()
    if not frame then
        return
    end

    -- Update ScopeViewer to show scopes for the current frame
    if not session_state.current_frame or session_state.current_frame.ref.id ~= frame.ref.id then
        self:Render(frame, session_id)
    end
end

-- Panel interaction methods
function ScopeViewer:OnPanelSelect(line, session_id)
    local scope = self.scope_map[line]
    if scope then
        self:toggleScopeExpansion(scope, session_id)
    end
end

function ScopeViewer:OnPanelToggle(line, session_id)
    local scope = self.scope_map[line]
    if scope then
        self:toggleScopeExpansion(scope, session_id)
    end
end

function ScopeViewer:toggleScopeExpansion(scope, session_id)
    local session_state = self:getSessionState(session_id)
    if not session_state then return end
    
    local ref = scope.ref.variablesReference
    if ref and ref > 0 then
        session_state.expanded_scopes[ref] = not session_state.expanded_scopes[ref]
        if session_state.current_frame then
            self:Render(session_state.current_frame, session_id)
        end
    end
end

function ScopeViewer:setupHighlights()
    vim.cmd([[
    highlight default NeodapScopeExpanded guifg=#7aa2f7 gui=bold
    highlight default NeodapScopeCollapsed guifg=#9ece6a
    highlight default NeodapScopeVariable guifg=#e0af68
    highlight default NeodapScopeValue guifg=#f7768e
    highlight default NeodapScopeType guifg=#bb9af7
    highlight default NeodapScopeCurrent guibg=#3c3836 guifg=#fbf1c7 gui=bold
  ]])
end

-- Rendering Methods (Capitalized = automatic NvimAsync wrapping)
function ScopeViewer:Render(frame, session_id)
    session_id = session_id or self:GetCurrentSessionId()
    self.logger:debug("Render called with session_id:", session_id, "frame:", frame and frame.ref.id or "nil")
    
    if not session_id then
        self.logger:debug("No session ID found, showing no active session message")
        self.debugOverlay:set_left_panel_content({ "No active session" }, {}, { scope_map = {} })
        return
    end
    
    local session_state = self:getSessionState(session_id)
    if not session_state then
        self.logger:debug("No session state found for session", session_id)
        self.debugOverlay:set_left_panel_content({ "Session state not found" }, {}, { scope_map = {} })
        return
    end

    if not frame then
        self.logger:debug("No frame available for rendering")
        self.debugOverlay:set_left_panel_content({ "No frame available" }, {}, { scope_map = {} })
        return
    end

    session_state.current_frame = frame
    local scopes = frame:scopes() -- This can be expensive, but auto-wrapped in async
    self.logger:debug("Retrieved scopes:", scopes and #scopes or "nil", "scopes")

    if not scopes or #scopes == 0 then
        self.logger:debug("No scopes available for frame", frame.ref.id)
        self.debugOverlay:set_left_panel_content({ "No scopes available" }, {}, { scope_map = {} })
        return
    end

    local lines = {}
    local highlights = {}
    self.scope_map = {}

    -- Find which scope contains the cursor position
    local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
    local current_scope = nil
    
    -- Try position-based highlighting first
    for _, scope in ipairs(scopes) do
        if scope.hasRange and scope:hasRange() then
            local start, finish = scope:region()
            if cursor_line >= start[1] and cursor_line <= finish[1] then
                -- Check if cursor is within the scope's range
                if (cursor_line > start[1] or cursor_col + 1 >= start[2]) and 
                   (cursor_line < finish[1] or cursor_col + 1 <= finish[2]) then
                    current_scope = scope
                    break
                end
            end
        end
    end
    
    -- Fallback: highlight Local scope if no position-based match
    if not current_scope then
        for _, scope in ipairs(scopes) do
            if scope.ref.name == "Local" or scope.ref.presentationHint == "locals" then
                current_scope = scope
                break
            end
        end
    end

    for i, scope in ipairs(scopes) do
        local mt = getmetatable(scope)
        local class_name = mt and mt.__index and mt.__index.name or "unknown"
        self.logger:debug("Processing scope", i, "name:", scope.ref.name, "type:", type(scope), "class:", class_name, "has variables method:", scope.variables and "yes" or "no")
        
        if scope.variables then
            self.logger:debug("Scope", scope.ref.name, "variables method type:", type(scope.variables))
        else
            self.logger:debug("Scope", scope.ref.name, "missing variables method, available methods:", vim.tbl_keys(scope))
        end
        
        local line_parts = {}
        local hl_parts = {}

        -- Add expand/collapse indicator
        local ref = scope.ref.variablesReference
        local is_expandable = ref and ref > 0
        
        -- Auto-expand non-expensive scopes by default
        local is_expensive = scope.ref.expensive
        local is_expanded = session_state.expanded_scopes[ref]
        
        -- If this is the first time seeing this scope and it's not expensive, expand it by default
        if is_expandable and is_expanded == nil and not is_expensive then
            session_state.expanded_scopes[ref] = true
            is_expanded = true
            self.logger:debug("Auto-expanding non-expensive scope:", scope.ref.name)
        end

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
        
        -- Use current scope highlight if this scope contains the cursor
        local name_highlight = "NeodapScopeExpanded"
        if current_scope and scope == current_scope then
            name_highlight = "NeodapScopeCurrent"
        end
        table.insert(hl_parts, { name_start, name_start + #name, name_highlight })

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

        -- Add variables if scope is expanded (potentially expensive DAP operation)
        if is_expanded then
            self.logger:debug("Calling frame:variables() for scope:", scope.ref.name, "with variablesReference:", scope.ref.variablesReference)
            -- Since Render is PascalCase (async), we can call frame:variables() directly with :wait()
            local variables_response = frame:variables(scope.ref.variablesReference)
            local variables = variables_response and variables_response or {}
            
            if variables and #variables > 0 then
                self.logger:debug("Successfully got", #variables, "variables for scope:", scope.ref.name)
                for _, variable in ipairs(variables) do
                    local var_line = self:formatVariable(variable, 1)
                    table.insert(lines, var_line.text)
                    table.insert(highlights, var_line.highlights)
                    self.scope_map[#lines] = scope -- Map to parent scope
                end
            else
                self.logger:debug("No variables found for scope:", scope.ref.name)
                -- Add a placeholder line indicating no variables
                table.insert(lines, "    (no variables)")
                table.insert(highlights, {})
                self.scope_map[#lines] = scope
            end
        end
    end

    -- Send content to debug overlay
    self.debugOverlay:set_left_panel_content(lines, highlights, { scope_map = self.scope_map })

    -- Set up highlights
    self:setupHighlights()
end

function ScopeViewer:formatVariable(variable, indent)
    local line_parts = {}
    local hl_parts = {}

    -- Add indentation
    local indent_str = string.rep("  ", indent)
    table.insert(line_parts, indent_str)

    -- Add variable name (raw DAP variable object)
    local name = variable.name or "unknown"
    table.insert(line_parts, name)
    local name_start = #table.concat(line_parts, "") - #name
    table.insert(hl_parts, { name_start, name_start + #name, "NeodapScopeVariable" })

    -- Add value if available (raw DAP variable object)
    if variable.value then
        table.insert(line_parts, " = ")
        local value = tostring(variable.value)
        -- Replace newlines with visual representation to avoid buffer line issues
        value = value:gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        if #value > 40 then
            value = value:sub(1, 40) .. "..."
        end
        table.insert(line_parts, value)
        local value_start = #table.concat(line_parts, "") - #value
        table.insert(hl_parts, { value_start, value_start + #value, "NeodapScopeValue" })
    end

    -- Add type if available (raw DAP variable object)
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

function ScopeViewer:setupCommands()
    -- Clean up any existing commands
    pcall(vim.api.nvim_del_user_command, "NeodapScopeShow")
    pcall(vim.api.nvim_del_user_command, "NeodapScopeHide")
    pcall(vim.api.nvim_del_user_command, "NeodapScopeToggle")
    
    -- Create user commands for ScopeViewer interaction
    vim.api.nvim_create_user_command("NeodapScopeShow", function()
        self.logger:debug("NeodapScopeShow command called")
        self:show()
    end, { desc = "Show neodap scope viewer" })
    
    vim.api.nvim_create_user_command("NeodapScopeHide", function()
        self:hide()
    end, { desc = "Hide neodap scope viewer" })
    
    vim.api.nvim_create_user_command("NeodapScopeToggle", function()
        self:toggle()
    end, { desc = "Toggle neodap scope viewer" })
end

return ScopeViewer