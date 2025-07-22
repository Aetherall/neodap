local IdGenerator = {}

---Generate ID for a scope node
---@param scope table DAP scope reference
---@return string id Hierarchical scope ID
function IdGenerator.forScope(scope)
  -- Include variablesReference to ensure uniqueness within a session
  -- The reference changes each stop, which is what we want
  return string.format("scope[%d]:%s", scope.variablesReference, scope.name)
end

---Generate ID for a variable node
---@param parent_id string Parent node's ID
---@param var_ref table DAP variable reference
---@param index? number Optional index for array elements
---@return string id Hierarchical variable ID
function IdGenerator.forVariable(parent_id, var_ref, index)
  local name_part = var_ref.name

  -- Handle array indices
  if index then
    return string.format("%s[%d]", parent_id, index)
  end

  -- Handle already bracketed names (like "[Symbol.iterator]" or "[[Prototype]]")
  if name_part:match("^%[.+%]$") then
    -- For special internal properties like [[Prototype]], ensure uniqueness
    if name_part:match("^%[%[.+%]%]$") then
      -- Add the variablesReference to ensure uniqueness
      return string.format("%s%s[%d]", parent_id, name_part, var_ref.variablesReference or 0)
    end
    return parent_id .. name_part
  end

  -- Handle names that need escaping (contain dots, spaces, etc)
  if name_part:match("[%.%s%[%]%(%)%'%\"]") then
    -- Escape as bracketed property
    return string.format("%s[%q]", parent_id, name_part)
  end

  -- Simple property name
  return string.format("%s.%s", parent_id, name_part)
end

---Parse a variable ID to extract components
---@param id string The hierarchical ID
---@return string? parent_id The parent portion
---@return string? name The variable name
function IdGenerator.parse(id)
  -- Match array index: parent[123]
  local parent, index = id:match("^(.+)%[(%d+)%]$")
  if parent then
    return parent, index
  end

  -- Match bracketed property: parent["name"] or parent['name']
  parent, name = id:match("^(.+)%[([\"'])(.-)%2%]$")
  if parent then
    return parent, name
  end

  -- Match special bracket: parent[Symbol.iterator]
  parent, name = id:match("^(.+)(%[.+%])$")
  if parent then
    return parent, name
  end

  -- Match simple property: parent.name
  parent, name = id:match("^(.+)%.([^.]+)$")
  if parent then
    return parent, name
  end

  -- No parent (root scope)
  return nil, id
end

return IdGenerator
