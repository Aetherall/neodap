-- Visual improvements for Variables tree readability

local M = {}

-- Type-specific icons
M.TYPE_ICONS = {
  -- Functions
  ["function"] = "󰊕",
  ["Function"] = "󰊕",
  
  -- Objects and structures  
  ["Object"] = "󰆩",
  ["Array"] = "󰅪",
  ["Map"] = "󰘿",
  ["Set"] = "󰏗",
  
  -- Primitives
  ["string"] = "󰀫",
  ["number"] = "󰎠",
  ["boolean"] = "◯",
  ["null"] = "󰟢",
  ["undefined"] = "󰇨",
  
  -- Special
  ["symbol"] = "󰫧",
  ["bigint"] = "󰎠",
  
  -- Default
  ["default"] = "󰀫",
}

-- Scope-specific icons
M.SCOPE_ICONS = {
  ["Local"] = "󰌾",      -- Stack/local icon
  ["Closure"] = "󰆧",    -- Link/closure icon
  ["Global"] = "󰇧",     -- Globe icon
  ["Catch"] = "󰨮",      -- Exception icon
  ["Block"] = "󰅩",      -- Block icon
  ["Script"] = "󰈮",     -- Script icon
  ["With"] = "󰡱",       -- Context icon
  ["Module"] = "󰕳",     -- Module icon
}

-- Format variable value with proper truncation
function M.formatValue(value, varType, maxLength)
  maxLength = maxLength or 40  -- Reduced for better tree display
  
  -- Handle special cases
  if value == "" then
    return '""'
  elseif value == nil or value == "nil" then
    return "nil"
  elseif value == "undefined" then
    return "undefined"
  end
  
  -- Format dates more concisely
  if varType == "Date" or value:match("^%w+ %w+ %d+ %d%d%d%d %d+:%d+:%d+") then
    -- Try to extract just the date part
    local year, month, day = value:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if year then
      return year .. "-" .. month .. "-" .. day
    end
    
    -- Try another format: "Mon Jan 01 2024..."
    local monthName, dayNum, yearNum = value:match("^%w+ (%w+) (%d+) (%d%d%d%d)")
    if monthName then
      return monthName .. " " .. dayNum .. ", " .. yearNum
    end
    
    -- Fallback: just truncate
    if #value > maxLength then
      return value:sub(1, maxLength - 3) .. "..."
    end
    return value
  end
  
  -- For functions, show clean representation
  if varType == "function" or varType == "Function" then
    -- Extract function name if available
    local funcName = value:match("^function%s+([%w_]+)")
    if funcName then
      return "ƒ " .. funcName .. "()"
    elseif value:match("native code") then
      return "ƒ [native]"
    elseif value:match("^function%s*%(") then
      -- Anonymous function - try to extract parameters
      local params = value:match("^function%s*%(([^)]*)")
      if params and params ~= "" then
        return "ƒ(" .. params .. ")"
      else
        return "ƒ()"
      end
    else
      return "ƒ()"
    end
  end
  
  -- Handle long strings
  if varType == "string" then
    -- Check if value is already properly quoted and displayed by the debugger
    if value:match("^'.*'$") then
      -- Already single-quoted, use as-is
      if #value > maxLength then
        return value:sub(1, maxLength - 4) .. "...'"
      else
        return value
      end
    elseif value:match('^".*"$') then
      -- Convert double quotes to single quotes for consistency
      local unquoted = value:sub(2, -2)
      if #unquoted > maxLength - 2 then
        return "'" .. unquoted:sub(1, maxLength - 5) .. "...'"
      else
        return "'" .. unquoted .. "'"
      end
    else
      -- Add single quotes
      if #value > maxLength - 2 then
        return "'" .. value:sub(1, maxLength - 5) .. "...'"
      else
        return "'" .. value .. "'"
      end
    end
  end
  
  -- Truncate other long values
  if #value > maxLength then
    -- Try to truncate at a meaningful boundary
    local truncated = value:sub(1, maxLength - 3)
    
    -- Don't cut in the middle of a word
    local lastSpace = truncated:reverse():find(" ")
    if lastSpace and lastSpace < 10 then
      truncated = truncated:sub(1, #truncated - lastSpace)
    end
    
    return truncated .. "..."
  end
  
  return value
end

-- Format variable name with special handling
function M.formatName(name, isArrayIndex)
  -- Array indices
  if isArrayIndex then
    return "[" .. name .. "]"
  end
  
  -- Internal/special properties - keep the double brackets
  if name:match("^%[%[") then
    return name  -- Keep [[Prototype]] as-is
  end
  
  return name
end

-- Get icon for variable type
function M.getIcon(varType, isExpandable)
  if isExpandable then
    -- Expandable items always get folder-like icon
    return M.TYPE_ICONS[varType] or "󰅩"
  else
    return M.TYPE_ICONS[varType] or M.TYPE_ICONS.default
  end
end

-- Create a formatted variable display
function M.formatVariableDisplay(var, maxTotalLength)
  maxTotalLength = maxTotalLength or 60  -- Maximum total display length
  
  local name = var.name or "<anonymous>"
  local value = var.value or ""
  local varType = var.type
  local isExpandable = var.variablesReference and var.variablesReference > 0
  
  -- Check if array index
  local isArrayIndex = tonumber(var.name) ~= nil
  
  -- Format name
  local displayName = M.formatName(name, isArrayIndex)
  
  -- For expandable items, show name and enhanced type info
  if isExpandable then
    local result
    if varType then
      -- Enhance type display with counts when available
      local enhancedType = varType
      
      -- Extract count from value if available
      if varType == "Array" and value then
        local count = value:match("%((%d+)%)") or value:match("Array%[(%d+)%]")
        if count then
          enhancedType = "Array[" .. count .. "]"
        else
          enhancedType = "Array"
        end
      elseif varType == "Object" and value then
        -- Try to extract property count
        local count = value:match("%((%d+)%)") or value:match("{(%d+)}")
        if count then
          enhancedType = "Object{" .. count .. "}"
        end
      elseif varType == "Map" and value then
        local count = value:match("%((%d+)%)")
        if count then
          enhancedType = "Map(" .. count .. ")"
        end
      elseif varType == "Set" and value then
        local count = value:match("%((%d+)%)")
        if count then
          enhancedType = "Set(" .. count .. ")"
        end
      end
      
      result = displayName .. " " .. enhancedType
    else
      result = displayName
    end
    
    -- Truncate if too long
    if #result > maxTotalLength then
      return result:sub(1, maxTotalLength - 3) .. "..."
    end
    return result
  end
  
  -- For leaf items, show formatted value
  local formattedValue = M.formatValue(value, varType)
  local result = displayName .. ": " .. formattedValue
  
  -- Truncate complete line if too long
  if #result > maxTotalLength then
    -- Try to keep more of the name and less of the value
    local nameLen = #displayName + 2  -- +2 for ": "
    local remainingLen = maxTotalLength - nameLen - 3  -- -3 for "..."
    if remainingLen > 5 then
      formattedValue = M.formatValue(value, varType, remainingLen)
      result = displayName .. ": " .. formattedValue
    else
      -- Name itself is too long
      result = result:sub(1, maxTotalLength - 3) .. "..."
    end
  end
  
  return result
end

-- Enhanced node line preparation with better visuals
function M.prepareNodeLine(node, opts)
  local line = require("nui.line")()
  opts = opts or {}
  
  local depth = node:get_depth() - 1
  
  -- Tree guides for better depth perception
  if opts.useTreeGuides and depth > 0 then
    for i = 1, depth - 1 do
      line:append("│ ", "NonText")
    end
    -- Simple tree connector for now
    line:append("├─", "NonText")
  else
    -- Simple indentation
    line:append(string.rep("  ", depth))
  end
  
  -- Expand indicator
  if node:has_children() then
    local indicator = node:is_expanded() and "▾ " or "▸ "
    line:append(indicator, "NeoTreeExpander")
  else
    line:append("  ")
  end
  
  -- Icon based on type
  local icon
  local highlight
  
  if node.type == "scope" then
    -- Use the actual scope name from the node
    local scopeName = node.name or node.text or "Block"
    -- Remove any suffix like ": testVariables" from "Local: testVariables"
    local baseScopeName = scopeName:match("^(%w+)") or scopeName
    icon = M.SCOPE_ICONS[baseScopeName] or M.SCOPE_ICONS["Block"]
    highlight = "NeoTreeDirectoryIcon"
  elseif node.type == "variable" then
    icon = M.getIcon(node.varType, node.is_expandable)
    highlight = node.is_expandable and "NeoTreeDirectoryIcon" or "NeoTreeFileIcon"
  else
    icon = "󰀫"
    highlight = "Normal"
  end
  
  line:append(icon .. " ", highlight)
  
  -- Node text with appropriate highlighting
  if node.type == "variable" then
    -- For variables, we need to split name and value for different highlighting
    local text = node.name or node.text
    local colonPos = text:find(": ")
    
    if colonPos then
      -- Property name (dimmed)
      local propName = text:sub(1, colonPos - 1)
      local value = text:sub(colonPos + 2)
      
      -- Special highlighting for internal properties
      if propName:match("^%[%[") then
        line:append(propName, "Comment")
      else
        line:append(propName, "Identifier")
      end
      
      line:append(": ", "Delimiter")
      
      -- Value with appropriate highlighting based on content
      if value:match("^'.*'$") or value:match('^".*"$') then
        line:append(value, "String")
      elseif value == "true" or value == "false" then
        line:append(value, "Boolean")
      elseif value == "null" or value == "undefined" then
        line:append(value, "Keyword")
      elseif tonumber(value) then
        line:append(value, "Number")
      else
        line:append(value, "Normal")
      end
    else
      -- No value, just the name (for expandable items)
      if text:match("^%[%[") then
        line:append(text, "Comment")
      else
        line:append(text)
      end
    end
  else
    -- Scope nodes
    line:append(node.name or node.text)
  end
  
  return line
end

return M