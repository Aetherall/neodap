local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local NvimAsync = require("neodap.tools.async")

---@class neodap.plugin.VariableCoreProps
---@field api Api
---@field logger Logger
---@field sessions table<integer, table> -- Session-scoped state

---@class neodap.plugin.VariableCore: neodap.plugin.VariableCoreProps
---@field new Constructor<neodap.plugin.VariableCoreProps>
local VariableCore = Class()

VariableCore.name = "VariableCore"
VariableCore.description = "Shared variable management for debugging sessions"

function VariableCore.plugin(api)
    local logger = Logger.get("Plugin:VariableCore")

    local instance = VariableCore:new({
        api = api,
        logger = logger,
        sessions = {}, -- Session-scoped state storage
    })

    -- Set up session event listeners for cleanup
    instance:listen()

    return instance
end

function VariableCore:new(props)
    local instance = {
        api = props.api,
        logger = props.logger,
        sessions = {},
    }
    return setmetatable(instance, { __index = self })
end

function VariableCore:listen()
    self.api:onSession(function(session)
        local session_id = session.ref.id
        self.logger:debug("VariableCore: New session started", session_id)
        
        -- Initialize session state
        self.sessions[session_id] = {
            expanded_scopes = {},
            cached_variables = {},
            current_frame = nil,
        }

        session:onTerminated(function()
            self.logger:debug("VariableCore: Session terminated, cleaning up", session_id)
            self.sessions[session_id] = nil
        end, { name = "VariableCore.onTerminated" })
    end, { name = "VariableCore.onSession" })
end

---Get session-scoped state for variable management
---@param session_id integer
---@return table Session state
function VariableCore:getSessionState(session_id)
    if not self.sessions[session_id] then
        self.sessions[session_id] = {
            expanded_scopes = {},
            cached_variables = {},
            current_frame = nil,
        }
    end
    return self.sessions[session_id]
end

---Format a variable value for display, handling newlines and length limits
---@param variable table Raw DAP variable object
---@param max_length? integer Maximum length before truncation (default 40)
---@return string Formatted value string
function VariableCore:formatVariableValue(variable, max_length)
    max_length = max_length or 40
    
    if not variable.value then
        return ""
    end
    
    local value = tostring(variable.value)
    -- Replace newlines with visual representation to avoid buffer line issues
    value = value:gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    
    if #value > max_length then
        value = value:sub(1, max_length) .. "..."
    end
    
    return value
end

---Format a single variable for display
---@param variable table Raw DAP variable object
---@param indent integer Indentation level
---@param highlight_name? string Override highlight for variable name
---@return table { text: string, highlights: table[] }
function VariableCore:formatVariable(variable, indent, highlight_name)
    local line_parts = {}
    local hl_parts = {}

    -- Add indentation
    local indent_str = string.rep("  ", indent)
    table.insert(line_parts, indent_str)

    -- Add variable name
    local name = variable.name or "unknown"
    table.insert(line_parts, name)
    local name_start = #table.concat(line_parts, "") - #name
    local name_highlight = highlight_name or "NeodapScopeVariable"
    table.insert(hl_parts, { name_start, name_start + #name, name_highlight })

    -- Add value if available
    if variable.value then
        table.insert(line_parts, " = ")
        local value = self:formatVariableValue(variable)
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

---Check if a scope should be auto-expanded by default
---@param scope table Raw DAP scope object
---@return boolean
function VariableCore:shouldAutoExpand(scope)
    -- Auto-expand non-expensive scopes by default
    return not scope.expensive
end

---Get scope key for state management
---@param scope table Raw DAP scope object
---@param index integer Scope index as fallback
---@return string Unique scope identifier
function VariableCore:getScopeKey(scope, index)
    return "scope_" .. (scope.variablesReference or index)
end

---Determine current scope based on cursor position
---@param scopes table[] Array of DAP scope objects
---@param cursor_line integer Current cursor line (1-indexed)
---@param cursor_col integer Current cursor column (0-indexed)
---@return table < /dev/null | nil Current scope or nil if none found
function VariableCore:getCurrentScope(scopes, cursor_line, cursor_col)
    -- Try position-based highlighting first
    for _, scope in ipairs(scopes) do
        if scope.hasRange and scope:hasRange() then
            local start, finish = scope:region()
            if cursor_line >= start[1] and cursor_line <= finish[1] then
                -- Check if cursor is within the scope's range
                if (cursor_line > start[1] or cursor_col + 1 >= start[2]) and 
                   (cursor_line < finish[1] or cursor_col + 1 <= finish[2]) then
                    return scope
                end
            end
        end
    end
    
    -- Fallback: return Local scope if no position-based match
    for _, scope in ipairs(scopes) do
        if scope.ref.name == "Local" or scope.ref.presentationHint == "locals" then
            return scope
        end
    end
    
    return nil
end

---Build a scope tree for display with cursor-based highlighting
---@param frame api.Frame Frame containing scopes
---@param session_id integer Session ID for state management
---@param cursor_line? integer Current cursor line for highlighting (1-indexed)
---@param cursor_col? integer Current cursor column for highlighting (0-indexed)
---@return table[] lines Array of formatted line strings
---@return table[] highlights Array of highlight definitions
---@return table<integer, table> scope_map Map from line number to scope object
---@return table<string, boolean> expanded_state Current expansion state
function VariableCore:buildScopeTree(frame, session_id, cursor_line, cursor_col)
    local session_state = self:getSessionState(session_id)
    local expanded_state = session_state.expanded_scopes
    
    local scopes = frame:scopes()
    if not scopes or #scopes == 0 then
        return { "No scopes available" }, {}, {}, expanded_state
    end

    local lines = {}
    local highlights = {}
    local scope_map = {}

    -- Determine current scope for highlighting
    local current_scope = nil
    if cursor_line and cursor_col then
        current_scope = self:getCurrentScope(scopes, cursor_line, cursor_col)
    end

    self.logger:debug("Building scope tree for frame", frame.ref.id, "with", #scopes, "scopes")

    for i, scope in ipairs(scopes) do
        local scope_ref = scope.ref
        local scope_key = self:getScopeKey(scope_ref, i)
        
        -- Determine if this scope should be expanded
        local is_expanded = expanded_state[scope_key]
        if is_expanded == nil then
            -- First time seeing this scope - check if it should auto-expand
            is_expanded = self:shouldAutoExpand(scope_ref)
            expanded_state[scope_key] = is_expanded
        end

        -- Format scope header line
        local line_parts = {}
        local hl_parts = {}

        -- Add expansion indicator
        if is_expanded then
            table.insert(line_parts, "▼ ")
        else
            table.insert(line_parts, "▶ ")
        end

        -- Add scope name
        local name = scope_ref.name or "Unknown"
        table.insert(line_parts, name)
        local name_start = #table.concat(line_parts, "") - #name
        
        -- Use current scope highlight if this scope contains the cursor
        local name_highlight = "NeodapScopeExpanded"
        if current_scope and scope == current_scope then
            name_highlight = "NeodapScopeCurrent"
        end
        table.insert(hl_parts, { name_start, name_start + #name, name_highlight })

        -- Add scope type if expensive
        if scope_ref.expensive then
            table.insert(line_parts, " (expensive)")
        end

        local line = table.concat(line_parts, "")
        table.insert(lines, line)
        table.insert(highlights, hl_parts)
        scope_map[#lines] = scope

        self.logger:debug("Added scope line", #lines, ":", name, "expanded:", is_expanded)

        -- Add variables if scope is expanded
        if is_expanded then
            self.logger:debug("Fetching variables for expanded scope:", name)
            local variables_response = frame:variables(scope_ref.variablesReference)
            local variables = variables_response and variables_response or {}
            
            if variables and #variables > 0 then
                self.logger:debug("Successfully got", #variables, "variables for scope:", name)
                for _, variable in ipairs(variables) do
                    local var_line = self:formatVariable(variable, 1)
                    table.insert(lines, var_line.text)
                    table.insert(highlights, var_line.highlights)
                    scope_map[#lines] = scope -- Map to parent scope
                end
            else
                self.logger:debug("No variables found for scope:", name)
                -- Add a placeholder line indicating no variables
                table.insert(lines, "    (no variables)")
                table.insert(highlights, {})
                scope_map[#lines] = scope
            end
        end
    end

    self.logger:debug("Built scope tree with", #lines, "total lines")
    return lines, highlights, scope_map, expanded_state
end

---Toggle expansion state of a scope
---@param session_id integer Session ID
---@param scope_key string Scope identifier
---@return boolean New expansion state
function VariableCore:toggleScopeExpansion(session_id, scope_key)
    local session_state = self:getSessionState(session_id)
    local current_state = session_state.expanded_scopes[scope_key]
    local new_state = not current_state
    session_state.expanded_scopes[scope_key] = new_state
    
    self.logger:debug("Toggled scope expansion", scope_key, "from", current_state, "to", new_state)
    return new_state
end

---Set expansion state of a scope
---@param session_id integer Session ID
---@param scope_key string Scope identifier
---@param expanded boolean New expansion state
function VariableCore:setScopeExpansion(session_id, scope_key, expanded)
    local session_state = self:getSessionState(session_id)
    session_state.expanded_scopes[scope_key] = expanded
    self.logger:debug("Set scope expansion", scope_key, "to", expanded)
end

---Get expansion state of a scope
---@param session_id integer Session ID
---@param scope_key string Scope identifier
---@return boolean|nil Expansion state (nil means not set)
function VariableCore:getScopeExpansion(session_id, scope_key)
    local session_state = self:getSessionState(session_id)
    return session_state.expanded_scopes[scope_key]
end

---Clear all expansion state for a session
---@param session_id integer Session ID
function VariableCore:clearExpansionState(session_id)
    local session_state = self:getSessionState(session_id)
    session_state.expanded_scopes = {}
    self.logger:debug("Cleared expansion state for session", session_id)
end

---Set variable value using DAP setVariable request
---@param frame api.Frame Current frame
---@param variable_name string Name of variable to set
---@param new_value string New value to set
---@param parent_variables_reference integer Parent scope variables reference
---@return boolean success Whether the operation succeeded
---@return string|nil error_message Error message if failed
function VariableCore:SetVariableValue(frame, variable_name, new_value, parent_variables_reference)
    local success, result = pcall(function()
        local response = frame.stack.thread.session.ref.calls:setVariable({
            variablesReference = parent_variables_reference,
            name = variable_name,
            value = new_value,
            threadId = frame.stack.thread.id,
        }):wait()
        
        return response
    end)
    
    if success and result then
        self.logger:debug("Successfully set variable", variable_name, "to", new_value)
        return true, nil
    else
        local error_msg = result or "Unknown error"
        self.logger:error("Failed to set variable", variable_name, ":", error_msg)
        return false, error_msg
    end
end

---Evaluate lazy variable using DAP evaluate request
---@param frame api.Frame Current frame
---@param evaluate_name string Expression to evaluate
---@return boolean success Whether the operation succeeded
---@return table|nil result Evaluation result
---@return string|nil error_message Error message if failed
function VariableCore:EvaluateLazyVariable(frame, evaluate_name)
    local success, result = pcall(function()
        local response = frame.stack.thread.session.ref.calls:evaluate({
            expression = evaluate_name,
            frameId = frame.ref.id,
            threadId = frame.stack.thread.id,
            context = "watch"
        }):wait()
        
        return response
    end)
    
    if success and result then
        self.logger:debug("Successfully evaluated lazy variable", evaluate_name)
        return true, result, nil
    else
        local error_msg = result or "Unknown error"
        self.logger:error("Failed to evaluate lazy variable", evaluate_name, ":", error_msg)
        return false, nil, error_msg
    end
end

---Check if a variable is lazy based on presentation hints
---@param variable table Raw DAP variable object
---@return boolean
function VariableCore:isLazyVariable(variable)
    if not variable.presentationHint then
        return false
    end
    
    if variable.presentationHint.lazy then
        return true
    end
    
    if variable.presentationHint.attributes then
        for _, attr in ipairs(variable.presentationHint.attributes) do
            if attr == "lazy" then
                return true
            end
        end
    end
    
    return false
end

return VariableCore
