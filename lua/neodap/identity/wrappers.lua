-- Wrapper creation for identity module

local function static(entity)
  return {
    get = function() return entity end,
    iter = function()
      local done = false
      return function()
        if done then return nil end
        done = true
        return entity
      end
    end,
    on = function() return function() end end,
    off = function() end,
    onChange = function() return function() end end,
    use = function(_, callback)
      callback(entity)
      return function() end
    end,
  }
end

local function empty(returns_single)
  return {
    get = function() return returns_single and nil or {} end,
    iter = function() return function() return nil end end,
    on = function() return function() end end,
    off = function() end,
    onChange = function() return function() end end,
    use = function(self, callback)
      callback(self:get())
      return function() end
    end,
  }
end

--- Compare two query results for equality
--- Handles: nil, single entities (by _id), arrays of entities (by _id set)
local function results_equal(a, b)
  -- Both nil
  if a == nil and b == nil then return true end
  -- One nil
  if a == nil or b == nil then return false end
  -- Same reference
  if a == b then return true end

  -- Single entity (has _id)
  if a._id and b._id then return a._id == b._id end

  -- Arrays: compare by entity IDs
  if type(a) == "table" and type(b) == "table" and a._id == nil and b._id == nil then
    if #a ~= #b then return false end
    -- Build ID set from a
    local ids = {}
    for _, e in ipairs(a) do
      if e._id then ids[e._id] = true end
    end
    -- Check all b IDs are in set
    for _, e in ipairs(b) do
      if not e._id or not ids[e._id] then return false end
    end
    return true
  end

  return false
end

local function watched(view, key_lookup, single_result)
  local w = {}

  -- Track subscriptions for disposal
  local unsubs = {}

  function w:dispose()
    for _, unsub in ipairs(unsubs) do
      pcall(unsub)
    end
    unsubs = {}
  end

  function w:get()
    local entities = {}
    for item in view:items() do
      -- Skip root (depth 0) - we want traversal results, not the starting point
      if item.depth > 0 and item.node then
        table.insert(entities, item.node)
      end
    end
    if single_result or key_lookup then return entities[1] end
    return entities
  end

  function w:iter()
    local entities = self:get()
    if type(entities) ~= "table" then
      local done = false
      return function()
        if done then return nil end
        done = true
        return entities
      end
    end
    local i = 0
    return function() i = i + 1; return entities[i] end
  end

  function w:on(event, callback)
    -- item.node has the entity metatable
    local unsub = view:on(event, function(item, index)
      callback(item.node, index)
    end)
    table.insert(unsubs, unsub)
    return unsub
  end

  function w:off(event)
    -- Note: neograph-native doesn't support bulk unsubscribe
    -- This is a no-op; use individual unsub functions instead
  end

  function w:onChange(callback)
    local current = self:get()

    local function notify()
      -- Defer to next event loop tick so view:items() reflects the change
      -- (documented async behavior in neograph-native)
      vim.schedule(function()
        local new = self:get()
        if not results_equal(new, current) then
          current = new
          callback(new)
        end
      end)
    end

    -- Subscribe to ALL view events for true reactivity
    local unsub_enter = view:on("enter", notify)
    local unsub_leave = view:on("leave", notify)
    local unsub_change = view:on("change", notify)

    table.insert(unsubs, unsub_enter)
    table.insert(unsubs, unsub_leave)
    table.insert(unsubs, unsub_change)

    return function()
      pcall(unsub_enter)
      pcall(unsub_leave)
      pcall(unsub_change)
    end
  end

  function w:use(callback)
    callback(self:get())
    return self:onChange(callback)
  end

  return w
end

return {
  static = static,
  empty = empty,
  watched = watched,
}
