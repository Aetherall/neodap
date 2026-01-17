-- Plugin: Generic URI picker
-- Resolves URL patterns to entities with interactive selection when multiple matches exist

-- Add format() methods to entity classes for picker display
local entities = require("neodap.entities")
local Session = entities.Session
local Thread = entities.Thread
local Frame = entities.Frame
local Scope = entities.Scope
local Variable = entities.Variable

function Session:format()
  local root = self:rootAncestor()
  local root_name = root.name:get()
  local self_name = self.name:get()
  local state = self.state:get()

  if root == self then
    return string.format("%s (%s)", self_name, state)
  else
    return string.format("%s › %s (%s)", root_name, self_name, state)
  end
end

function Thread:format()
  local name = self.name:get() or ""
  return string.format("Thread %d: %s (%s)", self.threadId:get(), name, self.state:get())
end

function Frame:format()
  local loc = self:location()
  local filename = loc and vim.fn.fnamemodify(loc.path or "", ":t") or "?"
  return string.format("%s @ %s:%d", self.name:get() or "?", filename, loc and loc.line or 0)
end

function Scope:format()
  return self.name:get()
end

function Variable:format()
  return string.format("%s = %s", self.name:get(), self.value:get())
end

---@param debugger neodap.entities.Debugger
---@return neodap.plugins.UriPicker
return function(debugger)
  ---@class neodap.plugins.UriPicker
  local Picker = {}

  ---Resolve URL pattern to single entity, showing picker if multiple matches
  ---@param url_pattern string URL like "/sessions", "@session/threads", "@frame/scopes"
  ---@param callback? fun(entity: any?) Called with selected entity (or nil if cancelled/empty)
  ---@return any? entity Returns entity directly in coroutine context, nil otherwise
  function Picker:resolve(url_pattern, callback)
    -- Resolve URL to entity or collection (array)
    local result = debugger:query(url_pattern)

    if not result then
      if callback then callback(nil) end
      return nil
    end

    -- Check if result is an array or single entity
    local items = {}
    if type(result) == "table" and result.type and type(result.type) == "function" then
      -- Single entity (has :type() method)
      items[1] = result
    elseif type(result) == "table" then
      -- It's an array (may be empty) - use directly
      items = result
    else
      -- Unknown format
      if callback then callback(nil) end
      return nil
    end

    -- Handle based on count
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
        format_item = function(item)
          if item.format then
            return item:format()
          end
          -- Fallback for entities without format method
          if item.uri then
            return item.uri:get() or tostring(item)
          end
          return tostring(item)
        end,
      }, function(selected)
        if callback then
          callback(selected)
        elseif co then
          -- Resume coroutine with selected item
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
