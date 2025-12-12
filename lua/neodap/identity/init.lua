--- Identity System
---
--- Unified entity identification and navigation.
---
--- URI: Stable identity strings (e.g., "thread:xotat:1")
--- URL: Navigation paths (e.g., "/sessions:xotat/threads:1")
---
--- Both resolve via graph queries. The difference is semantic:
--- - URI: "What is this entity?" → always one result
--- - URL: "How do I get there?" → zero, one, or many results

local uri = require("neodap.uri")
local url = require("neodap.identity.url")

local M = {}

-- Re-export modules
M.uri = uri
M.url = url

--------------------------------------------------------------------------------
-- Debugger Integration
--------------------------------------------------------------------------------

--- Install identity methods on debugger instance
--- Safe to call multiple times (idempotent)
---@param debugger table The debugger to extend
function M.install(debugger)
  -- Guard against double-installation
  -- Use rawget/rawset because neograph returns Signals for any key access
  if rawget(debugger, "_identity_installed") then return end
  rawset(debugger, "_identity_installed", true)

  local wrappers = require("neodap.identity.wrappers")

  --- Query URL (immediate resolution)
  ---@param url_str string
  ---@return table|table[]|nil
  function debugger:query(url_str)
    return url.query(self, url_str)
  end

  --- Watch URL (reactive signal)
  --- TRUE REACTIVITY: Uses neograph views with proper event subscriptions
  ---@param url_str string
  ---@return table? signal
  function debugger:watch(url_str)
    return url.watch(self, url_str, wrappers)
  end

  --- Query URL, always return array
  ---@param url_str string
  ---@return table[] entities
  function debugger:queryAll(url_str)
    local result = url.query(self, url_str)
    if not result then return {} end
    if type(result) ~= "table" or result.uri then
      return { result }
    end
    return result
  end

  --- Unified resolve: auto-detect URI vs URL
  ---@param str string URI or URL string
  ---@return table|table[]|nil
  function debugger:resolve(str)
    if not str or str == "" then return nil end
    -- URL: starts with / or @
    if str:match("^[/@]") then
      return url.query(self, str)
    end
    -- URI: contains colon (type:components)
    if str:find(":") or str == "debugger" then
      return uri.resolve(self, str)
    end
    -- Bare path: treat as URL
    return url.query(self, "/" .. str)
  end
end

return M
