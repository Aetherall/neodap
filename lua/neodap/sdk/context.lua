---@class Context : Class
---@field frame_uri Signal<string?> Effective frame URI (computed from local or parent)
---@field _local_uri Signal<string?> Local override URI (nil = follow parent)
---@field _parent Context? Parent context to inherit from
local neostate = require("neostate")

local M = {}

-- =============================================================================
-- CONTEXT
-- =============================================================================

---@class Context : Class
local Context = neostate.Class("Context")

---Create a new context
---@param parent Context? Parent context to inherit from
function Context:init(parent)
  self._parent = parent

  -- Local override URI (nil = follow parent)
  self._local_uri = self:signal(nil, "local_uri")

  -- Build dependency list for computed
  local deps = { self._local_uri }
  if parent then
    table.insert(deps, parent.frame_uri)
  end

  -- Effective URI: local if set, otherwise parent's
  self.frame_uri = self:computed(function()
    local local_uri = self._local_uri:get()
    if local_uri then
      return local_uri
    end
    if self._parent then
      return self._parent.frame_uri:get()
    end
    return nil
  end, deps, "frame_uri")
end

---Pin this context to a specific frame URI
---@param uri string Frame URI like "dap:session:xxx/stack[0]/frame[0]"
function Context:pin(uri)
  self._local_uri:set(uri)
end

---Unpin this context (follow parent again)
function Context:unpin()
  self._local_uri:set(nil)
end

---Check if this context is pinned (has local override)
---@return boolean
function Context:is_pinned()
  return self._local_uri:get() ~= nil
end

---Get the parent context
---@return Context?
function Context:parent()
  return self._parent
end

M.Context = Context

return M
