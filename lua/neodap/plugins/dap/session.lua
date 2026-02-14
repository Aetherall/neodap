-- Session entity DAP methods
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local a = require("neodap.async")

local Session = entities.Session
local Debugger = entities.Debugger
local get_dap_session = context.get_dap_session

function Session:disconnect()
  local dap_session = get_dap_session(self)
  if not dap_session then error("No DAP session", 0) end
  a.wait(function(cb) dap_session:disconnect(cb) end)
  self:update({ state = "terminated" })
  local cfg = self.config:get()
  if cfg then
    cfg:checkStopAll()
    cfg:updateState()
  end
end
Session.disconnect = a.fn(Session.disconnect)

function Session:terminate()
  local dap_session = get_dap_session(self)
  if not dap_session then error("No DAP session", 0) end
  -- Mark the entire dap_session tree as terminating (vs disconnecting)
  -- so the "closing" handler knows to kill terminal processes
  context.mark_terminating(dap_session)
  a.wait(function(cb) dap_session:terminate(cb) end)
  self:update({ state = "terminated" })
  local cfg = self.config:get()
  if cfg then
    cfg:checkStopAll()
    cfg:updateState()
  end
end
Session.terminate = a.fn(Session.terminate)

---Clear hit state on all breakpoint bindings for this session
function Session:clearHitBreakpoints()
  self:forEachBreakpointBinding(function(bpb)
    if bpb.hit:get() then
      bpb:update({ hit = false })
    end
  end)
end

function Session:supportsRestart()
  local dap_session = get_dap_session(self)
  if not dap_session or not dap_session.capabilities then return false end
  return dap_session.capabilities.supportsRestartRequest or false
end

function Session:restart(args)
  local dap_session = get_dap_session(self)
  if not dap_session then error("No DAP session", 0) end
  if not self:supportsRestart() then
    error("Adapter does not support restart request", 0)
  end
  a.wait(function(cb) dap_session.client:request("restart", args or {}, cb) end)
end
Session.restart = a.fn(Session.restart)

function Session:fetchThreads()
  local dap_session = get_dap_session(self)
  if not dap_session then error("No DAP session", 0) end

  local body = a.wait(function(cb)
    dap_session.client:request("threads", {}, cb)
  end)

  local graph, session_id = self._graph, self.sessionId:get()
  for _, thread_data in ipairs(body.threads or {}) do
    local existing_thread = self:findThreadById(thread_data.id)
    if existing_thread then
      existing_thread:update({ name = thread_data.name })
    else
      local thread = entities.Thread.new(graph, {
        uri = uri.thread(session_id, thread_data.id),
        threadId = thread_data.id, name = thread_data.name, state = "running", stops = 0,
      })
      thread.sessions:link(self)
      self.threads:link(thread)
    end
  end
end
Session.fetchThreads = a.fn(Session.fetchThreads)

function Session:syncExceptionFilters()
  local dap_session = get_dap_session(self)
  if not dap_session then error("No DAP session", 0) end

  local supports_filter_options = dap_session.capabilities and
    dap_session.capabilities.supportsExceptionFilterOptions

  local filters, filterOptions = {}, {}
  for binding in self.exceptionFilterBindings:iter() do
    if binding:getEffectiveEnabled() then
      local ef = binding.exceptionFilter:get()
      local filter_id = ef.filterId:get()
      table.insert(filters, filter_id)

      if supports_filter_options then
        -- Use binding condition override, or global filter condition if set
        local condition = binding.condition:get()
        if condition and condition ~= "" then
          table.insert(filterOptions, { filterId = filter_id, condition = condition })
        end
      end
    end
  end

  local args = { filters = filters }
  if supports_filter_options and #filterOptions > 0 then args.filterOptions = filterOptions end

  a.wait(function(cb) dap_session.client:request("setExceptionBreakpoints", args, cb) end)
end
Session.syncExceptionFilters = a.fn(Session.syncExceptionFilters)

function Session:supportsBreakpointLocations()
  local dap_session = get_dap_session(self)
  if not dap_session or not dap_session.capabilities then return false end
  return dap_session.capabilities.supportsBreakpointLocationsRequest or false
end

function Session:breakpointLocations(source, line, opts)
  opts = opts or {}
  local dap_session = get_dap_session(self)
  if not dap_session then error("No DAP session", 0) end
  if not self:supportsBreakpointLocations() then
    error("Adapter does not support breakpointLocations request", 0)
  end

  local response = a.wait(function(cb)
    dap_session.client:request("breakpointLocations", {
      source = source, line = line, column = opts.column,
      endLine = opts.endLine, endColumn = opts.endColumn,
    }, cb)
  end)

  local locations = {}
  for _, loc in ipairs((response and response.breakpoints) or {}) do
    table.insert(locations, {
      line = loc.line, column = loc.column or 1,
      endLine = loc.endLine, endColumn = loc.endColumn,
    })
  end
  return locations
end
Session.breakpointLocations = a.fn(Session.breakpointLocations)

function Debugger:breakpointLocations(source, line, opts)
  opts = opts or {}
  if not self:supportsBreakpointLocations() then
    error("No session supports breakpointLocations", 0)
  end

  local all_locations, seen = {}, {}
  for session in self:iterSessionsSupporting("supportsBreakpointLocations") do
    for _, loc in ipairs(session:breakpointLocations(source, line, opts)) do
      local key = string.format("%d:%d:%s:%s", loc.line, loc.column, loc.endLine or "", loc.endColumn or "")
      if not seen[key] then
        seen[key] = true
        table.insert(all_locations, loc)
      end
    end
  end

  table.sort(all_locations, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.column < b.column
  end)
  return all_locations
end
Debugger.breakpointLocations = a.fn(Debugger.breakpointLocations)

return { Session = Session, Debugger = Debugger }
