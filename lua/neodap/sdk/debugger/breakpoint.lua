local neostate = require("neostate")
local neoword = require("neoword")

local M = {}

-- =============================================================================
-- BREAKPOINT
-- =============================================================================

---@class Breakpoint : Class
local Breakpoint = neostate.Class("Breakpoint")

function Breakpoint:init(debugger, source, line, opts)
  opts = opts or {}

  self.debugger = debugger
  self.source = source
  self.line = line
  self.column = opts.column  -- Optional column position

  -- Generate stable ID from source + line (+ column if provided)
  -- Use correlation_key for both local and virtual sources
  local source_id = source.correlation_key or source.path or source.name or "unknown"
  local id_seed = source_id .. ":" .. line
  if opts.column then
    id_seed = id_seed .. ":" .. opts.column
  end
  self.id = neoword.generate(id_seed)

  -- URI: dap:breakpoint:<id>
  self.uri = "dap:breakpoint:" .. self.id
  self.key = self.id
  self._type = "breakpoint"

  self.condition = self:signal(opts.condition, "condition")
  self.logMessage = self:signal(opts.logMessage, "logMessage")
  self.hitCondition = self:signal(opts.hitCondition, "hitCondition")
  self.enabled = self:signal(opts.enabled ~= false, "enabled") -- Default true

  -- Filtered bindings collection for this breakpoint
  self.bindings = debugger.bindings:where(
    "by_breakpoint_id",
    self.id,
    "Bindings:BP:" .. self.id
  )
  self.bindings:set_parent(self)

  -- State tracking: "unbound" | "bound" | "hit"
  -- Reactively computed from bindings using aggregation
  local has_hit = self.bindings:some(function(binding)
    return binding.hit
  end)

  local has_bound = self.bindings:some(function(binding)
    return binding.verified
  end)

  self.state = neostate.Signal("unbound", "state")
  self.state:set_parent(self)

  -- Update state reactively when aggregates change
  has_hit:watch(function(is_hit)
    if is_hit then
      self.state:set("hit")
    else
      -- Check if any binding is bound
      if has_bound:get() then
        self.state:set("bound")
      else
        self.state:set("unbound")
      end
    end
  end)

  has_bound:watch(function(is_bound)
    -- Only update if not currently hit
    if not has_hit:get() then
      if is_bound then
        self.state:set("bound")
      else
        self.state:set("unbound")
      end
    end
  end)

  -- When breakpoint properties change, update all bindings
  local function sync_to_bindings()
    for binding in self.bindings:iter() do
      binding.session:_sync_breakpoints_to_dap()
    end
  end

  self.condition:watch(sync_to_bindings)
  self.logMessage:watch(sync_to_bindings)
  self.hitCondition:watch(sync_to_bindings)
  self.enabled:watch(sync_to_bindings)
end

---Toggle enabled state
function Breakpoint:toggle()
  self.enabled:set(not self.enabled:get())
end

---Enable breakpoint
function Breakpoint:enable()
  self.enabled:set(true)
end

---Disable breakpoint
function Breakpoint:disable()
  self.enabled:set(false)
end

---Register callback for bindings (existing + future)
---@param fn function  -- Called with (binding)
---@return function unsubscribe
function Breakpoint:onBinding(fn)
  return self.bindings:each(fn)
end

---Register callback for verified bindings only
---Cleanup runs when binding becomes unverified OR is removed
---@param fn function  -- Called with (binding)
---@return function unsubscribe
function Breakpoint:onVerifiedBinding(fn)
  return self.bindings:each(function(binding)
    return binding.verified:use(function(verified)
      if verified then
        return fn(binding)  -- Return cleanup function to .use()
      end
    end)
  end)
end

---Register callback for when ANY binding has an active frame URI
---@param fn function  -- Called with (frame_uri, binding)
---@return function unsubscribe
function Breakpoint:onActiveFrame(fn)
  return self.bindings:each(function(binding)
    return binding:onActiveFrame(function(frame_uri)
      if frame_uri then
        return fn(frame_uri, binding)  -- Return cleanup function
      end
    end)
  end)
end

---Register callback for when ANY binding is hit
---Fires when binding becomes hit, cleanup when unhit
---Does NOT require fetching stacks - just tracks hit state
---@param fn function  -- Called with (binding)
---@return function unsubscribe
function Breakpoint:onHit(fn)
  return self.bindings:each(function(binding)
    return binding:onHit(function()
      return fn(binding)  -- Return cleanup function
    end)
  end)
end

---Register callback for sessions this breakpoint is bound to
---@param fn function  -- Called with (session)
---@return function unsubscribe
function Breakpoint:onSession(fn)
  return self:onBinding(function(binding)
    return fn(binding.session)  -- Return cleanup function
  end)
end

M.Breakpoint = Breakpoint

return M
