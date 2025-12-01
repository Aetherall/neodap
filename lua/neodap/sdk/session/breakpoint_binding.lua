local neostate = require("neostate")

local M = {}

-- =============================================================================
-- BREAKPOINT BINDING
-- =============================================================================

---@class Binding : Class
local Binding = neostate.Class("Binding")

function Binding:init(breakpoint, session)
  self.breakpoint = breakpoint
  self.session = session
  self.sessionId = session.id -- For indexing

  -- URI: dap:session:<session_id>/binding:<breakpoint_id>
  self.uri = "dap:session:" .. session.id .. "/binding:" .. breakpoint.id
  self.key = "binding:" .. breakpoint.id
  self._type = "binding"

  self.dapId = self:signal(nil, "dapId")  -- DAP breakpoint ID from setBreakpoints response
  self.verified = self:signal(false, "verified")
  self.message = self:signal(nil, "message")
  self.actualLine = self:signal(nil, "actualLine")
  self.actualColumn = self:signal(nil, "actualColumn")
  self.hit = self:signal(false, "hit")  -- Set by stopped event with reason=breakpoint
  self.active_frame = self:signal(nil, "active_frame")  -- Set when stack is fetched

  -- Binding location starts as requested location, updated when adapter verifies
  -- For virtual sources, use name or correlation_key instead of path
  local function get_source_identifier(source)
    return source.path or source.name or source.correlation_key or "unknown"
  end

  local function make_location(source_id, line, column)
    local loc = source_id .. ":" .. line
    if column then
      loc = loc .. ":" .. column
    end
    return loc
  end

  local source_id = get_source_identifier(breakpoint.source)
  local bp_location = make_location(source_id, breakpoint.line, breakpoint.column)
  self.location = self:signal(bp_location, "location")

  -- Update location when actualLine or actualColumn changes
  local function update_location()
    local line = self.actualLine:get() or breakpoint.line
    local column = self.actualColumn:get() or breakpoint.column
    self.location:set(make_location(source_id, line, column))
  end

  self.actualLine:watch(update_location)
  self.actualColumn:watch(update_location)
end

---Register callback for when binding is verified
---@param fn function  -- Called with (verified: boolean)
---@return function unsubscribe
function Binding:onVerified(fn)
  return self.verified:use(fn)
end

---Register callback for when binding is active (frame URI available)
---Passes the frame URI - you may need to fetch the actual Frame object
---@param fn function  -- Called with (frame_uri: string?)
---@return function unsubscribe
function Binding:onActiveFrame(fn)
  return self.active_frame:use(fn)
end

---Register callback for when binding is hit
---Fires on stopped event with reason=breakpoint, cleanup when thread resumes
---Does NOT require fetching the stack - just tracks hit state from DAP events
---@param fn function  -- Called with no arguments
---@return function unsubscribe
function Binding:onHit(fn)
  return self.hit:use(function(is_hit)
    if is_hit then
      return fn()  -- Hit! Return cleanup function
    end
    -- When hit becomes false (resumed), previous cleanup will run
  end)
end

M.Binding = Binding

return M
