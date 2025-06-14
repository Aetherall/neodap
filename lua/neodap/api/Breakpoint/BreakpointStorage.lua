local Class = require('neodap.tools.class')

---@class api.BreakpointStorageProps
---@field _breakpoints { [string]: api.SourceBreakpoint }

---@class api.BreakpointStorage: api.BreakpointStorageProps
---@field new Constructor<api.BreakpointStorageProps>
local BreakpointStorage = Class()

---Create a new BreakpointStorage instance
---@return api.BreakpointStorage
function BreakpointStorage.create()
  return BreakpointStorage:new({
    _breakpoints = {}
  })
end

---Add a breakpoint to storage
---@param breakpoint api.SourceBreakpoint
function BreakpointStorage:add(breakpoint)
  if not breakpoint or not breakpoint.id then
    error("Cannot add breakpoint without valid ID")
  end
  
  self._breakpoints[breakpoint.id] = breakpoint
end

---Remove a breakpoint from storage
---@param breakpointOrId api.SourceBreakpoint | string
---@return api.SourceBreakpoint? -- The removed breakpoint, if it existed
function BreakpointStorage:remove(breakpointOrId)
  local id = type(breakpointOrId) == "string" and breakpointOrId or breakpointOrId.id
  if not id then return nil end
  
  local breakpoint = self._breakpoints[id]
  self._breakpoints[id] = nil
  return breakpoint
end

---Get a breakpoint by ID
---@param id string
---@return api.SourceBreakpoint?
function BreakpointStorage:getById(id)
  return self._breakpoints[id]
end

---Get all breakpoints
---@return api.SourceBreakpoint[]
function BreakpointStorage:getAll()
  local breakpoints = {}
  for _, breakpoint in pairs(self._breakpoints) do
    table.insert(breakpoints, breakpoint)
  end
  return breakpoints
end

---Get breakpoints by source ID (computed query - replaces dual storage)
---@param sourceId string
---@return api.SourceBreakpoint[]
function BreakpointStorage:getBySourceId(sourceId)
  if not sourceId then return {} end
  
  local result = {}
  for _, breakpoint in pairs(self._breakpoints) do
    -- Check if breakpoint has any bindings for this source
    for _, binding in pairs(breakpoint._bindings or {}) do
      if binding.source and binding.source:identifier() == sourceId then
        table.insert(result, breakpoint)
        break -- Only add once per breakpoint
      end
    end
  end
  return result
end

---Get breakpoints by session (computed query)
---@param session api.Session
---@return api.SourceBreakpoint[]
function BreakpointStorage:getBySession(session)
  if not session then return {} end
  
  local result = {}
  local sessionId = session.ref.id
  
  for _, breakpoint in pairs(self._breakpoints) do
    if breakpoint._bindings and breakpoint._bindings[sessionId] then
      table.insert(result, breakpoint)
    end
  end
  return result
end

return BreakpointStorage
