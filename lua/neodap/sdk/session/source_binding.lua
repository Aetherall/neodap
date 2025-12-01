local neostate = require("neostate")
local uri_module = require("neodap.sdk.uri")

local M = {}

-- =============================================================================
-- SOURCE BINDING
-- =============================================================================

---@class SourceBinding : Class
---Represents a session-specific reference to a global Source
local SourceBinding = neostate.Class("SourceBinding")

function SourceBinding:init(source, session, sourceReference, adapterData)
  self.source = source
  self.session = session
  self.sourceReference = sourceReference or 0  -- DAP sourceReference (session-specific)
  self.adapterData = adapterData                -- DAP adapterData (session-specific)

  -- URI: dap:session:<session_id>/source-binding:<correlation_key>
  self.uri = "dap:session:" .. session.id .. "/source-binding:" .. uri_module.encode_segment(source.correlation_key)
  self.key = "source-binding:" .. source.correlation_key
  self._type = "source_binding"
end

-- =============================================================================
-- BREAKPOINT HOOKS
-- =============================================================================

---Get breakpoint bindings for THIS session at this source
---@return table Filtered collection of breakpoint bindings
function SourceBinding:breakpoint_bindings()
  if not self._breakpoint_bindings then
    -- Filter source's breakpoint_bindings to this session only
    self._breakpoint_bindings = self.source:breakpoint_bindings():where(
      "by_session_id",
      self.session.id,
      "BreakpointBindings:SourceBinding:" .. self.session.id .. ":" .. self.source.correlation_key
    )
  end
  return self._breakpoint_bindings
end

---Register callback for breakpoint bindings in THIS session at this source
---@param fn function  -- Called with (binding)
---@return function unsubscribe
function SourceBinding:onBreakpointBinding(fn)
  return self:breakpoint_bindings():each(fn)
end

---Register callback for breakpoints that have bindings in THIS session
---Since there's 1:1 mapping between breakpoint and binding per session,
---we derive this from breakpoint_bindings
---@param fn function  -- Called with (breakpoint)
---@return function unsubscribe
function SourceBinding:onBreakpoint(fn)
  return self:breakpoint_bindings():each(function(binding)
    return fn(binding.breakpoint)
  end)
end

-- =============================================================================
-- FRAME HOOKS
-- =============================================================================

---Get frames for THIS session at this source
---@return table Filtered collection of frames
function SourceBinding:frames()
  if not self._frames then
    self._frames = self.source:frames():where(
      "by_session_id",
      self.session.id,
      "Frames:SourceBinding:" .. self.session.id .. ":" .. self.source.correlation_key
    )
  end
  return self._frames
end

---Get active (current) frames for THIS session at this source
---@return table Filtered collection of frames
function SourceBinding:active_frames()
  if not self._active_frames then
    self._active_frames = self:frames():where(
      "by_is_current",
      true,
      "ActiveFrames:SourceBinding:" .. self.session.id .. ":" .. self.source.correlation_key
    )
  end
  return self._active_frames
end

---Get top frames (index 0) for THIS session at this source
---@return table Filtered collection of frames
function SourceBinding:top_frames()
  if not self._top_frames then
    self._top_frames = self:frames():where(
      "by_index",
      0,
      "TopFrames:SourceBinding:" .. self.session.id .. ":" .. self.source.correlation_key
    )
  end
  return self._top_frames
end

---Register callback for frames in THIS session at this source
---@param fn function  -- Called with (frame)
---@return function unsubscribe
function SourceBinding:onFrame(fn)
  return self:frames():each(fn)
end

---Register callback for active frames in THIS session at this source
---@param fn function  -- Called with (frame)
---@return function unsubscribe
function SourceBinding:onActiveFrame(fn)
  return self:active_frames():each(fn)
end

---Register callback for top frames in THIS session at this source
---Useful for highlighting the current execution line
---@param fn function  -- Called with (frame)
---@return function unsubscribe
function SourceBinding:onTopFrame(fn)
  return self:top_frames():each(fn)
end

M.SourceBinding = SourceBinding

return M
