-- Example implementation of Adaptive Indentation approach

local M = {}

-- Calculate adaptive indentation based on depth
function M.getAdaptiveIndent(depth)
  -- Indentation schedule: 
  -- Levels 0-2: 2 spaces per level (normal)
  -- Levels 3-5: 1 space per level (compressed)
  -- Levels 6+: 0.5 spaces (using unicode half-space)
  
  if depth <= 0 then
    return ""
  elseif depth <= 2 then
    return string.rep("  ", depth)  -- 2 spaces per level
  elseif depth <= 5 then
    local baseIndent = string.rep("  ", 2)  -- First 2 levels = 4 spaces
    local compressedIndent = string.rep(" ", depth - 2)  -- 1 space per level after
    return baseIndent .. compressedIndent
  else
    -- Ultra-compressed for very deep nesting
    local baseIndent = string.rep("  ", 2)  -- First 2 levels = 4 spaces
    local compressedIndent = string.rep(" ", 3)  -- Levels 3-5 = 3 spaces
    local ultraCompressed = string.rep("·", depth - 5)  -- Dot for each level after 5
    return baseIndent .. compressedIndent .. ultraCompressed
  end
end

-- Enhanced tree guide system for adaptive indentation
function M.getTreeGuides(depth, isLast)
  local guides = {}
  
  -- Build guide characters based on depth
  for i = 1, depth - 1 do
    if i <= 2 then
      table.insert(guides, "│ ")  -- Normal guides for shallow levels
    elseif i <= 5 then
      table.insert(guides, "┆")   -- Thinner guides for medium depth
    else
      table.insert(guides, "·")   -- Dots for deep levels
    end
  end
  
  -- Add the connector for current level
  if depth > 0 then
    if isLast then
      table.insert(guides, "└─")
    else
      table.insert(guides, "├─")
    end
  end
  
  return table.concat(guides)
end

-- Format variable with depth awareness
function M.formatVariableWithDepth(var, depth)
  local name = var.name
  local value = var.value
  local varType = var.type
  
  -- At extreme depths, use more compact notation
  if depth > 6 then
    -- Use abbreviated format
    if varType == "Object" then
      return name .. "{…}"
    elseif varType == "Array" then
      local count = value:match("%((%d+)%)") or "?"
      return name .. "[" .. count .. "]"
    else
      -- Truncate values more aggressively
      local maxLen = math.max(10, 30 - depth * 2)
      if #value > maxLen then
        value = value:sub(1, maxLen - 1) .. "…"
      end
      return name .. ": " .. value
    end
  else
    -- Normal formatting for shallow to medium depth
    return M.formatVariableDisplay(var)  -- Use existing formatter
  end
end

-- Example of how to modify prepareNodeLine
function M.prepareNodeLineAdaptive(node, opts)
  local line = require("nui.line")()
  opts = opts or {}
  
  local depth = node:get_depth() - 1
  
  -- Use adaptive indentation
  if opts.useAdaptiveIndent then
    -- Method 1: Compressed spacing
    local indent = M.getAdaptiveIndent(depth)
    line:append(indent)
  elseif opts.useTreeGuides then
    -- Method 2: Adaptive tree guides
    local guides = M.getTreeGuides(depth, node.is_last)
    line:append(guides, "NonText")
  else
    -- Fallback to simple indentation
    line:append(string.rep("  ", depth))
  end
  
  -- Depth indicator for deep nesting
  if depth > 5 then
    local depthIndicator = "⁺" .. tostring(depth) .. " "
    line:append(depthIndicator, "Comment")
  end
  
  -- Rest of node rendering...
  -- [existing expand indicator and icon code]
  
  return line
end

-- Alternative: Path compression for very deep nodes
function M.compressPath(node)
  local path = {}
  local current = node
  
  -- Build path from root
  while current and current:get_parent_id() do
    table.insert(path, 1, current.name or current.text)
    current = current:get_parent()
  end
  
  -- Compress middle portions if path is long
  if #path > 4 then
    local compressed = {
      path[1],
      "→",
      path[#path - 1],
      "→",
      path[#path]
    }
    return table.concat(compressed, " ")
  else
    return table.concat(path, " → ")
  end
end

return M