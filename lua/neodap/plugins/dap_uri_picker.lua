-- Plugin: Generic URI picker
-- Resolves a URI pattern to a single entity, showing a picker if multiple matches exist

---@class UriPicker
---@field debugger Debugger

---Format an entity for display in the picker
---@param item any
---@return string
local function format_item(item)
  -- Session: use name signal
  if item.name and type(item.name) == "table" and item.name.get then
    return item.name:get() or item.uri or tostring(item)
  end

  -- Frame: show function name and location
  if item.name and item.source and item.line then
    local source_name = item.source.name or item.source.path or "unknown"
    if item.source.path then
      source_name = vim.fn.fnamemodify(item.source.path, ":t")
    end
    return string.format("%s @ %s:%d", item.name, source_name, item.line)
  end

  -- Thread: show name or id
  if item.id and item.state then
    local name = item.name or ("Thread " .. item.id)
    return string.format("%s (%s)", name, item.state:get())
  end

  -- Breakpoint: show location
  if item.source and item.line and not item.name then
    local path = item.source.path or item.source.name or "unknown"
    local filename = vim.fn.fnamemodify(path, ":t")
    return string.format("%s:%d", filename, item.line)
  end

  -- Binding: use location signal
  if item.location and type(item.location) == "table" and item.location.get then
    return item.location:get() or item.uri or tostring(item)
  end

  -- Fallback to URI
  if item.uri then
    return item.uri
  end

  return tostring(item)
end

---@param debugger Debugger
---@return UriPicker
return function(debugger)
  local Picker = {}
  Picker.debugger = debugger

  ---Resolve a URI pattern to a single entity
  ---Shows picker if multiple matches, returns directly if single match
  ---Supports contextual URIs like "@stack/frame" which expand using current context
  ---@param uri_pattern string URI pattern to resolve (may contain @ markers)
  ---@param callback? fun(entity: any?) Called with selected entity (or nil if cancelled/empty)
  ---@return any? entity Returns entity directly in coroutine context, nil otherwise
  function Picker:resolve(uri_pattern, callback)
    -- Resolve URI to collection (handles contextual URIs transparently)
    local collection, err = debugger:resolve(uri_pattern)

    if not collection then
      if callback then callback(nil) end
      return nil
    end

    -- 2. Collect items
    local items = {}
    for item in collection:iter() do
      items[#items + 1] = item
    end

    -- 3. Handle based on count
    if #items == 0 then
      if callback then callback(nil) end
      return nil
    elseif #items == 1 then
      if callback then callback(items[1]) end
      return items[1]
    else
      -- Multiple items - show picker
      local co = coroutine.running()

      vim.ui.select(items, {
        prompt = "Select:",
        format_item = format_item,
      }, function(selected)
        if callback then
          callback(selected)
        elseif co then
          -- Resume coroutine with selected item (use schedule for safety)
          vim.schedule(function()
            coroutine.resume(co, selected)
          end)
        end
      end)

      -- If in coroutine and no callback, yield to wait for selection
      if co and not callback then
        return coroutine.yield()
      end

      return nil
    end
  end

  return Picker
end
