local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')

---@class api.BindingCollectionProps
---@field bindings api.FileSourceBinding[]

---@class api.BindingCollection: api.BindingCollectionProps
---@field new Constructor<api.BindingCollectionProps>
local BindingCollection = Class()


---@return api.BindingCollection
function BindingCollection.create()
  return BindingCollection:new({
    bindings = {},
  })
end


---@param binding api.FileSourceBinding
function BindingCollection:add(binding)
  table.insert(self.bindings, binding)
end

function BindingCollection:remove(binding)
  for i, b in ipairs(self.bindings) do
    if b == binding then
      table.remove(self.bindings, i)
      return
    end
  end
end


function BindingCollection:first()
  return self.bindings[1]
end

---@generic T
---@param by fun(binding: api.FileSourceBinding): T
---@param keyer fun(t: T): any
---@return fun(): T, api.BindingCollection
function BindingCollection:groupBy(by, keyer)
  local groups = {}
  for _, binding in ipairs(self.bindings) do
    local value = by(binding)
    local key = keyer(value)
    if not groups[key] then
      groups[key] = { collection = BindingCollection.create(), value = value }
    end
    groups[key].collection:add(binding)
  end

  local keys = vim.tbl_keys(groups)
  local index = 0
  return function()
    index = index + 1
    if index > #keys then
      return nil, nil
    end

    local group = groups[keys[index]]
    return group.value, group.collection
  end
end

function BindingCollection:filter(predicate)
  local filtered = BindingCollection.create()
  for _, binding in ipairs(self.bindings) do
    if predicate(binding) then
      filtered:add(binding)
    end
  end
  return filtered
end


---@return fun(): api.Session, api.BindingCollection
function BindingCollection:bySession()
  return self:groupBy(
    function(binding) return binding.session end,
    function(session) return session.ref.id end
  )
end

---@return fun(): api.Source, api.BindingCollection
function BindingCollection:bySource()
  return self:groupBy(
    function(binding) return binding.source end,
    function(source) return source.id end
  )
end


function BindingCollection:forSource(source)
  return self:filter(function(binding)
    return binding.source.id == source.id
  end)
end

---@param session api.Session
---@return api.BindingCollection
function BindingCollection:forSession(session)
  return self:filter(function(binding)
    return binding.session.id == session.id
  end)
end

---@param ids integer[]
function BindingCollection:forIds(ids)
  return self:filter(function(binding)
    return vim.tbl_contains(ids, binding.id)
  end)
end


---@param breakpoint api.FileSourceBreakpoint
---@return api.BindingCollection
function BindingCollection:forBreakpoint(breakpoint)
  return self:filter(function(binding)
    return binding.breakpointId == breakpoint.id
  end)
end

---@return api.FileSourceBinding[]
function BindingCollection:toArray()
  return vim.tbl_map(function(b) return b end, self.bindings or {})
end


---@return dap.SourceBreakpoint[]
function BindingCollection:toDapSourceBreakpoints()
  local dapBreakpoints = {}
  for _, binding in ipairs(self.bindings) do
    local dapBreakpoint = binding:toDapSourceBreakpoint()
    table.insert(dapBreakpoints, dapBreakpoint)
  end
  return dapBreakpoints
end

function BindingCollection:push()
  local log = Logger.get()
  log:info("BindingCollection:push - Starting to push breakpoints to debug adapter")
  
  for session, bindings in self:bySession() do
    for source, bindings in bindings:bySource() do
      
      local array = bindings:toArray()
      log:debug("Session", session.id, "- Pushing", #array, "breakpoints for source:", source:identifier())

      local dapBreakpoints = vim.tbl_map(function(binding) return binding:toDapSourceBreakpoint() end, array)
      
      log:info("Session", session.id, "- Calling setBreakpoints with", #dapBreakpoints, "breakpoints for source:", source:identifier())
      for i, dapBp in ipairs(dapBreakpoints) do
        log:info("  Breakpoint", i, "- line:", dapBp.line, "column:", dapBp.column or 0)
      end

      local result = session.ref.calls:setBreakpoints({
        source = source.ref,
        breakpoints = dapBreakpoints
      }):wait()
      
      log:debug("Session", session.id, "- setBreakpoints returned:", result)

      for i, breakpoint in ipairs(result.breakpoints) do
        local binding = array[i]
        if binding then
          log:debug("Session", session.id, "- Updating binding", i, "with DAP response")
          binding:update(breakpoint)
        end
      end
    end
  end
  
  log:info("BindingCollection:push - Completed pushing breakpoints")
end

---Push breakpoints for a specific session and source to the debug adapter
---This method handles empty collections by sending an empty array to clear breakpoints
---@param session api.Session
---@param source api.Source
function BindingCollection:pushForSource(session, source)
  local log = Logger.get()
  log:info("BindingCollection:pushForSource - Pushing breakpoints for session", session.id, "source:", source:identifier())
  
  -- Get all bindings for this specific session and source
  local bindings = self:forSession(session):forSource(source)
  local array = bindings:toArray()
  
  log:info("Session", session.id, "- Pushing", #array, "breakpoints for source:", source:identifier())
  
  local dapBreakpoints = vim.tbl_map(function(binding) return binding:toDapSourceBreakpoint() end, array)
  
  log:info("Session", session.id, "- Calling setBreakpoints with", #dapBreakpoints, "breakpoints for source:", source:identifier())
  for i, dapBp in ipairs(dapBreakpoints) do
    log:info("  Breakpoint", i, "- line:", dapBp.line, "column:", dapBp.column or 0)
  end

  local result = session.ref.calls:setBreakpoints({
    source = source.ref,
    breakpoints = dapBreakpoints
  }):wait()
  
  log:debug("Session", session.id, "- setBreakpoints returned:", result)

  -- Update bindings with DAP response
  for i, breakpoint in ipairs(result.breakpoints) do
    local binding = array[i]
    if binding then
      log:debug("Session", session.id, "- Updating binding", i, "with DAP response")
      binding:update(breakpoint)
    end
  end
  
  log:info("BindingCollection:pushForSource - Completed pushing breakpoints for source:", source:identifier())
end

---@param dapBinding dap.Breakpoint
function BindingCollection:match(dapBinding)
  return self:filter(function(binding)
    return binding:matches(dapBinding)
  end)
end


---@return fun(): api.FileSourceBinding
function BindingCollection:each()
  local index = 0
  return function()
    index = index + 1
    if index > #self.bindings then
      return nil
    end
    return self.bindings[index]
  end
end

return BindingCollection