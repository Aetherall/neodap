local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')

---@class neodap.core.VariableCoreProps
---@field logger Logger
---@field sessions table<integer, table> -- Session-scoped state

---@class neodap.core.VariableCore: neodap.core.VariableCoreProps
---@field new Constructor<neodap.core.VariableCoreProps>
local VariableCore = Class()

VariableCore.name = "VariableCore"

function VariableCore:new(props)
    local instance = {
        logger = props.logger or Logger.get("Core:VariableCore"),
        sessions = {},
    }
    return setmetatable(instance, { __index = self })
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
---@return table { text: string, highlights: table[] }
function VariableCore:formatVariable(variable, indent)
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

---Build a scope tree for display
---@param frame api.Frame Frame containing scopes
---@param session_id? integer Session ID for state management
---@param expanded_state? table<string, boolean> Current expansion state
---@return table[] lines Array of formatted line strings
---@return table[] highlights Array of highlight definitions
---@return table<integer, table> scope_map Map from line number to scope object
function VariableCore:buildScopeTree(frame, session_id, expanded_state)
    expanded_state = expanded_state or {}
    
    local scopes = frame:scopes()
    if not scopes or #scopes == 0 then
        return { "No scopes available" }, {}, {}
    end

    local lines = {}
    local highlights = {}
    local scope_map = {}

    self.logger:debug("Building scope tree for frame", frame.ref.id, "with", #scopes, "scopes")

    for i, scope in ipairs(scopes) do
        local scope_ref = scope.ref
        local scope_key = "scope_" .. (scope_ref.variablesReference or i)
        
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
        table.insert(hl_parts, { name_start, name_start + #name, "NeodapScopeExpanded" })

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
    return lines, highlights, scope_map
end

return VariableCore