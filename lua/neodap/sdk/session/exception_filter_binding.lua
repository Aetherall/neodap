local neostate = require("neostate")

local M = {}

-- =============================================================================
-- EXCEPTION FILTER BINDING
-- =============================================================================

---@class ExceptionFilterBinding : Class
---@field filter ExceptionFilter
---@field session Session
---@field adapter_type string  -- For indexing
---@field filter_id string     -- For indexing
---@field session_id string    -- For indexing
---@field verified Signal<boolean>  -- DAP confirmed the filter
---@field hit Signal<boolean>       -- Stopped on this exception type
---@field message Signal<string?>   -- Error message if not verified
---@field dapId number?             -- DAP breakpoint ID from response
local ExceptionFilterBinding = neostate.Class("ExceptionFilterBinding")

function ExceptionFilterBinding:init(filter, session)
  self.filter = filter
  self.session = session

  -- For collection indexing
  self.adapter_type = filter.adapter_type
  self.filter_id = filter.filter_id
  self.session_id = session.id

  -- URI: dap:session:<session_id>/filter-binding:<filter_id>
  self.uri = "dap:session:" .. session.id .. "/filter-binding:" .. filter.filter_id
  self.key = "filter-binding:" .. filter.filter_id
  self._type = "exception_filter_binding"

  -- DAP verification state
  self.verified = self:signal(false, "verified")
  self.message = self:signal(nil, "message")
  self.hit = self:signal(false, "hit")

  -- DAP breakpoint ID (from setExceptionBreakpoints response)
  self.dapId = nil
end

---Register callback for when binding is verified
---@param fn function  -- Called with (verified: boolean)
---@return function unsubscribe
function ExceptionFilterBinding:onVerified(fn)
  return self.verified:use(fn)
end

---Register callback for when binding is hit (stopped on exception)
---Fires when stopped with reason="exception", cleanup when thread resumes
---@param fn function  -- Called with no arguments
---@return function unsubscribe
function ExceptionFilterBinding:onHit(fn)
  return self.hit:use(function(is_hit)
    if is_hit then
      return fn()
    end
  end)
end

M.ExceptionFilterBinding = ExceptionFilterBinding

return M
