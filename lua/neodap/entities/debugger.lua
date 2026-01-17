-- Debugger entity methods for neograph-native
local Ctx = require("neodap.ctx")

---@param Debugger neodap.entities.Debugger
return function(Debugger)
  -- Load sub-modules
  require("neodap.entities.debugger.source")(Debugger)
  require("neodap.entities.debugger.breakpoint")(Debugger)
  require("neodap.entities.debugger.session")(Debugger)

  --------------------------------------------------------------------------------
  -- Context API (debugger.ctx)
  --------------------------------------------------------------------------------

  ---Initialize the ctx property on a debugger instance
  ---@param debugger table
  function Debugger.initCtx(debugger)
    debugger.ctx = Ctx.new(debugger)
  end

  ---Extract entity from query result (handles arrays)
  ---@param result any Query result
  ---@return table? entity
  local function extract_entity(result)
    if type(result) ~= "table" then return nil end
    if result._id then return result end
    if result[1] and result[1]._id then return result[1] end
    return nil
  end

  ---Focus on a URL
  ---Resolves the URL to an entity. If resolution fails, removes the last
  ---path segment and tries again recursively until a match is found.
  ---Pass empty string to clear focus.
  ---@param url string URL to focus on, or "" to clear
  function Debugger:focus(url)
    if type(url) ~= "string" then return end

    -- Empty string clears focus
    if url == "" then
      self.focusedUrl:set(nil)
      return
    end

    -- Try to resolve the URL
    local entity = extract_entity(self:query(url))

    if entity then
      -- Found an entity, store its URI
      self:update({ focusedUrl = entity.uri:get() })
      return
    end

    -- Remove last path segment and try again
    -- Handle both /segment and [index] endings
    local shorter = url:match("^(.+)/[^/]+$") or url:match("^(.+)%[[^%]]+%]$")
    if shorter and shorter ~= url then
      self:focus(shorter)
    end
    -- URL exhausted, do nothing
  end

  ---Resolve the focused entity from focusedUrl
  ---@return table? entity The focused entity (Frame, Thread, or Session)
  function Debugger:_resolveFocused()
    local url = self.focusedUrl:get()
    if not url then return nil end

    local result = self:query(url)
    if result == nil then return nil end

    -- Handle array result
    if type(result) == "table" then
      if result._id then
        return result
      elseif result[1] and result[1]._id then
        return result[1]
      end
    end
    return nil
  end
end
