---@class Source : Class
---@field debugger Debugger
---@field correlation_key string  -- Stable ID for deduplication across sessions
---@field path string?  -- Local file path
---@field name string?  -- Display name
---@field sourceReference number  -- DAP sourceReference (0 = local file, >0 = fetch via DAP)
---@field checksums table?  -- DAP checksums for content verification
---@field content Signal<string?>  -- Lazy loaded for virtual sources

local neostate = require("neostate")
local neoword = require("neoword")

local M = {}

-- =============================================================================
-- HELPER: Compute correlation key for source deduplication
-- =============================================================================

---Compute stable correlation key from DAP source data
---Local files: use absolute path
---Virtual sources: use "name:neoword(checksum)"
---TODO: Support adapter-specific parse_source_id(dap_source) for custom correlation
---@param data { path?: string, name?: string, checksums?: table }
---@return string correlation_key
local function compute_correlation_key(data)
  -- Local files: use path as correlation key
  if data.path then
    return data.path
  end

  -- Virtual sources: use name + checksum
  local checksum_str = nil
  if data.checksums and #data.checksums > 0 then
    -- Use first checksum as stable seed for neoword
    local first_checksum = data.checksums[1]
    checksum_str = first_checksum.checksum
  end

  if checksum_str then
    return data.name .. ":" .. neoword.generate(checksum_str)
  else
    -- No checksum available, just use name (less precise)
    return data.name or "unknown"
  end
end

-- =============================================================================
-- SOURCE
-- =============================================================================

---@class Source : Class
local Source = neostate.Class("Source")

function Source:init(debugger, data)
  self.debugger = debugger
  self.path = data.path
  self.name = data.name
  self.sourceReference = data.sourceReference or 0
  self.checksums = data.checksums

  -- Compute stable correlation key for deduplication
  self.correlation_key = compute_correlation_key(data)

  -- EntityStore fields: use correlation_key for deduplication
  -- Note: self:uri() method returns display URI (path for local, dap:source for virtual)
  -- self.uri field is stable entity URI for EntityStore
  self.uri = "dap:source:" .. self.correlation_key
  self.key = self.correlation_key
  self._type = "source"

  -- Lazy-loaded content (for virtual sources)
  self._content = self:signal(nil, "content")
end

---Check if this is a virtual source (content must be fetched via DAP)
---A source is virtual if sourceReference > 0 (DAP spec)
---@return boolean
function Source:is_virtual()
  return self.sourceReference > 0
end

---Get the navigable URI for this source
---For virtual sources: dap:source:<correlation_key>
---For local sources: just the path (works with vim.cmd.edit and uri.resolve)
---Note: Different from self.uri which is always the entity store URI
---@return string
function Source:location_uri()
  if self:is_virtual() then
    return "dap:source:" .. self.correlation_key
  else
    return self.path or ""
  end
end

---Get all frames at this source (across ALL sessions!)
---@return table Filtered collection of frames
function Source:frames()
  if not self._frames then
    self._frames = self.debugger.frames:where(
      "by_source_id",
      self.correlation_key,
      "Frames:Source:" .. self.correlation_key
    )
  end
  return self._frames
end

---Get only active (current) frames at this source
---@return table Filtered collection of frames
function Source:active_frames()
  if not self._active_frames then
    self._active_frames = self:frames():where(
      "by_is_current",
      true,
      "ActiveFrames:Source:" .. self.correlation_key
    )
  end
  return self._active_frames
end

---Get only top frames (index 0) at this source
---@return table Filtered collection of frames
function Source:top_frames()
  if not self._top_frames then
    self._top_frames = self:frames():where(
      "by_index",
      0,
      "TopFrames:Source:" .. self.correlation_key
    )
  end
  return self._top_frames
end

---Get all breakpoints in this source (works for both local and virtual sources)
---@return table Filtered collection of breakpoints
function Source:breakpoints()
  if not self._breakpoints then
    -- Use correlation_key index for both local and virtual sources
    self._breakpoints = self.debugger.breakpoints:where(
      "by_source_correlation_key",
      self.correlation_key,
      "Breakpoints:Source:" .. self.correlation_key
    )
  end
  return self._breakpoints
end

---Get all breakpoint bindings in this source (across ALL sessions)
---@return table Filtered collection of breakpoint bindings
function Source:breakpoint_bindings()
  if not self._breakpoint_bindings then
    self._breakpoint_bindings = self.debugger.bindings:where(
      "by_source_correlation_key",
      self.correlation_key,
      "BreakpointBindings:Source:" .. self.correlation_key
    )
  end
  return self._breakpoint_bindings
end

-- =============================================================================
-- LIFECYCLE HOOKS
-- =============================================================================

---Register callback for frames entering this source (existing + future)
---@param fn function  -- Called with (frame)
---@return function unsubscribe
function Source:onFrame(fn)
  return self:frames():each(fn)
end

---Register callback for active frames at this source (existing + future)
---@param fn function  -- Called with (frame)
---@return function unsubscribe
function Source:onActiveFrame(fn)
  return self:active_frames():each(fn)
end

---Register callback for top frames at this source (existing + future)
---Useful for highlighting the current execution line in a file
---@param fn function  -- Called with (frame)
---@return function unsubscribe
function Source:onTopFrame(fn)
  return self:top_frames():each(fn)
end

---Register callback for breakpoints in this source (existing + future)
---@param fn function  -- Called with (breakpoint)
---@return function unsubscribe
function Source:onBreakpoint(fn)
  return self:breakpoints():each(fn)
end

---Register callback for breakpoint bindings in this source (existing + future)
---@param fn function  -- Called with (binding)
---@return function unsubscribe
function Source:onBreakpointBinding(fn)
  return self:breakpoint_bindings():each(fn)
end

---Get possible breakpoint locations for this source
---Aggregates across all sessions via debugger
---@param pos integer|integer[]  -- Start position (0-indexed line, or {line, col})
---@param end_pos? integer[]     -- Optional end position {line, col} for range query
---@return string? error, { pos: integer[], end_pos?: integer[] }[]? locations
function Source:breakpointLocations(pos, end_pos)
  return self.debugger:breakpointLocations({ path = self.path }, pos, end_pos)
end

---Invalidate cached content (forces re-fetch on next access)
---@private
function Source:_invalidate_content()
  self._content:set(nil)
end

---Fetch source content (for virtual sources)
---Returns cached content if already loaded
---Uses first available session binding to fetch content
---@return string? error, string? content
function Source:fetch_content()
  -- Local files don't use DAP source request
  if not self:is_virtual() then
    local err = "Source has local path, read file directly: " .. (self.path or "")
    return err, nil
  end

  -- Check if already loaded
  if self._content:get() then
    return nil, self._content:get()
  end

  -- Find a binding to use for fetching (prefer first non-terminated session)
  local binding = nil
  local bindings_view = self.debugger.source_bindings:where(
    "by_source_correlation_key",
    self.correlation_key
  )

  for b in bindings_view:iter() do
    if b.session.state:get() ~= "terminated" then
      binding = b
      break
    end
  end

  -- Fallback to any binding if all sessions terminated
  if not binding then
    for b in bindings_view:iter() do
      binding = b
      break
    end
  end

  if not binding then
    local err = "No session binding available for source: " .. self.correlation_key
    return err, nil
  end

  -- Fetch from DAP using the binding's session and sourceReference
  local result, err = neostate.settle(binding.session.client:request("source", {
    sourceReference = binding.sourceReference
  }))

  if err then
    return err, nil
  end

  local content = result and result.content or ""
  self._content:set(content)

  return nil, content
end

M.Source = Source

-- Export correlation key computation for use by session event handlers
M.compute_correlation_key = compute_correlation_key

-- Backwards compatibility
function M.create(debugger, data)
  return Source:new(debugger, data)
end

return M
