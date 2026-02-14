--- Context API for focus management
---
--- Provides a clean API for managing debug focus.
--- Single focused entity - no per-buffer complexity.
---
--- Usage:
---   debugger.ctx:focus(url)       -- Set focus
---   debugger.ctx.frame:get()      -- Get focused frame
---   debugger.ctx.frame:use(cb)    -- Subscribe to frame changes
---   debugger.ctx:expand(url)      -- Returns signal of expanded URL

local derive = require("neodap.derive")

---@class neodap.Ctx
---@field _debugger table
---@field frame neodap.CtxAccessor
---@field thread neodap.CtxAccessor
---@field session neodap.CtxAccessor
local Ctx = {}
Ctx.__index = Ctx

---@class neodap.CtxAccessor
---@field _ctx neodap.Ctx
---@field _type string "frame"|"thread"|"session"

--------------------------------------------------------------------------------
-- Entity Resolution
--------------------------------------------------------------------------------

---Extract entity from query result
---@param result any
---@return table?
local function extract_entity(result)
  if type(result) ~= "table" then return nil end
  if result._id then return result end
  if result[1] and result[1]._id then return result[1] end
  return nil
end

---Navigate from any entity to target type
---@param entity table
---@param target_type string "frame"|"thread"|"session"
---@return table?
local function navigate_to_type(entity, target_type)
  if not entity then return nil end
  local t = entity:type()

  if target_type == "frame" then
    if t == "Frame" then return entity end
    if t == "Stack" then return entity.topFrame:get() end
    if t == "Thread" then
      local stack = entity.stack:get()
      return stack and stack.topFrame:get()
    end
    if t == "Session" then
      local thread = entity.firstStoppedThread:get() or entity.firstThread:get()
      local stack = thread and thread.stack:get()
      return stack and stack.topFrame:get()
    end
  elseif target_type == "thread" then
    if t == "Frame" then
      local stack = entity.stack:get()
      return stack and stack.thread:get()
    end
    if t == "Stack" then return entity.thread:get() end
    if t == "Thread" then return entity end
    if t == "Session" then
      return entity.firstStoppedThread:get() or entity.firstThread:get()
    end
  elseif target_type == "session" then
    if t == "Frame" then
      local stack = entity.stack:get()
      local thread = stack and stack.thread:get()
      return thread and thread.session:get()
    end
    if t == "Stack" then
      local thread = entity.thread:get()
      return thread and thread.session:get()
    end
    if t == "Thread" then return entity.session:get() end
    if t == "Session" then return entity end
  end

  return nil
end

--------------------------------------------------------------------------------
-- Accessor (frame/thread/session)
--------------------------------------------------------------------------------

local Accessor = {}
Accessor.__index = Accessor

function Accessor.new(ctx, entity_type)
  return setmetatable({
    _ctx = ctx,
    _type = entity_type,
  }, Accessor)
end

---Get focused entity
---@return table? entity
function Accessor:get()
  local url = self._ctx._debugger.focusedUrl:get()
  if not url or url == "" then return nil end

  -- Resolve URI/URL to entity
  local result = self._ctx._debugger:resolve(url)
  local entity = extract_entity(result)
  if not entity then return nil end

  -- Navigate to target type
  return navigate_to_type(entity, self._type)
end

---Subscribe to entity changes
---@param callback fun(entity: table?): fun()?
---@return fun() unsubscribe
function Accessor:use(callback)
  local cleanup = nil
  local disposed = false

  local function runCleanup()
    if cleanup then
      pcall(cleanup)
      cleanup = nil
    end
  end

  local function update()
    if disposed then return end
    runCleanup()
    local entity = self:get()
    local ok, result = pcall(callback, entity)
    if ok and type(result) == "function" then
      cleanup = result
    end
  end

  -- Initial call
  update()

  -- Subscribe to focus changes
  local first_call = true
  local unsub = self._ctx._debugger.focusedUrl:use(function()
    if first_call then
      first_call = false
      return
    end
    update()
  end)

  return function()
    disposed = true
    runCleanup()
    unsub()
  end
end

--------------------------------------------------------------------------------
-- Ctx
--------------------------------------------------------------------------------

---Create a new Ctx
---@param debugger table
---@return neodap.Ctx
function Ctx.new(debugger)
  local self = setmetatable({}, Ctx)
  self._debugger = debugger

  -- Create accessors
  self.frame = Accessor.new(self, "frame")
  self.thread = Accessor.new(self, "thread")
  self.session = Accessor.new(self, "session")

  return self
end

---Get a frame suitable for expression evaluation.
---Handles stale frames: if the focused frame belongs to a stack that is no
---longer the thread's current stack, falls back to the current top frame.
---Returns nil if no stopped frame is available.
---@return table? frame
function Ctx:evaluationFrame()
  local frame = self.frame:get()
  if not frame then
    -- No focused frame — try focused thread's top frame
    local thread = self.thread:get()
    if not thread or not thread:isStopped() then return nil end
    local stack = thread.stack:get()
    return stack and stack.topFrame:get()
  end

  -- Validate frame belongs to the thread's current stack (not stale)
  local thread = frame:thread()
  if thread then
    local current_stack = thread.stack:get()
    if current_stack and current_stack ~= frame.stack:get() then
      -- Frame is stale — use top frame from current stack
      return current_stack.topFrame:get()
    end
  end
  return frame
end

---Focus a thread's top frame and return it.
---Loads the current stack via thread.stack rollup, gets the top frame,
---and sets focus to it.
---@param thread table Thread entity
---@return table? frame The focused frame, or nil if no stack/frame
function Ctx:focusThread(thread)
  local stack = thread.stack:get()
  if not stack then return nil end
  local frame = stack.topFrame:get()
  if not frame then return nil end
  self:focus(frame.uri:get())
  return frame
end

---Get the Config entity of the focused session, or nil.
---@return table? config
function Ctx:focusedConfig()
  local session = self.session:get()
  return session and session.config:get()
end

---Check if a session is in the focused session's context.
---Returns true if: no focus, focused is terminated, same session tree, or same Config.
---@param session table Session entity to check
---@return boolean
function Ctx:isInFocusedContext(session)
  local focused = self.session:get()
  if not focused then return true end
  if focused.state:get() == "terminated" then return true end
  if focused:isInSameTreeAs(session) then return true end
  local focused_config = focused.config:get()
  local session_config = session.config:get()
  return focused_config ~= nil and session_config ~= nil and focused_config == session_config
end

---Set focus
---Resolves URL to entity, with recursive fallback on failure.
---@param url string URL to focus on, or "" to clear
function Ctx:focus(url)
  if type(url) ~= "string" then return end

  -- Empty string clears focus
  if url == "" then
    self._debugger.focusedUrl:set("")
    return
  end

  -- Try to resolve the URI/URL, with recursive fallback
  local function tryResolve(u)
    local result = self._debugger:resolve(u)
    local entity = extract_entity(result)

    if entity then
      -- Found an entity, store its URI
      self._debugger:update({ focusedUrl = entity.uri:get() })
      return true
    end

    -- Remove last path segment and try again
    local shorter = u:match("^(.+)/[^/]+$") or u:match("^(.+)%[[^%]]+%]$")
    if shorter and shorter ~= u then
      return tryResolve(shorter)
    end

    return false
  end

  tryResolve(url)
end

---Expand @markers in URL to concrete URIs
---Returns a signal that reactively updates when focus changes
---
---Example:
---  ctx:expand("@session/threads"):get() -> "session:xotat/threads"
---  ctx:expand("@frame"):get() -> "frame:xotat:42"
---
---@param url string URL with @markers to expand
---@return table signal Signal with :get() and :use() methods
function Ctx:expand(url)
  local debugger = self._debugger

  local function resolve_marker(marker)
    if marker == "@session" then return self.session:get() end
    if marker == "@thread" then return self.thread:get() end
    if marker == "@frame" then return self.frame:get() end
    local offset = marker:match("^@frame([%+%-]%d+)$")
    if not offset then return nil end
    local frame = self.frame:get()
    if not frame then return nil end
    local stack = frame.stack:get()
    return stack and stack:frameAtIndex(frame.index:get() + tonumber(offset))
  end

  return derive.from({ debugger.focusedUrl }, function()
    local marker, rest = url:match("^(@[%w%+%-]+)(.*)")
    if not marker then return url end

    -- @debugger is special: expands to debugger URI or root path
    if marker == "@debugger" then
      return rest == "" and "debugger" or rest:sub(2)
    end

    local entity = resolve_marker(marker)
    if not entity then return nil end

    local entity_uri = entity.uri:get()
    if rest and rest ~= "" then return entity_uri .. rest end
    return entity_uri
  end)
end

return Ctx
