local neo = require("neograph")
local scoped = require("neodap.scoped")
local schema = require("neodap.schema")
local entities = require("neodap.entities")
local uri = require("neodap.uri")

---@alias neodap.Plugin fun(debugger: neodap.entities.Debugger, config?: table): any

---@class neodap.SDK
local M = {}

---@class neodap.Config
---@field adapters? table<string, table> Map DAP type names to adapter configs
local defaults = {
  adapters = {},
}

---@type neodap.Config
M.config = {}

-- Re-export entity classes
M.Debugger = entities.Debugger
M.Source = entities.Source
M.SourceBinding = entities.SourceBinding
M.Breakpoint = entities.Breakpoint
M.BreakpointBinding = entities.BreakpointBinding
M.Session = entities.Session
M.Thread = entities.Thread
M.Stack = entities.Stack
M.Frame = entities.Frame
M.Scope = entities.Scope
M.Variable = entities.Variable

-- Internal: create a debugger instance with its own scope
local function create_debugger_instance(graph, parent_scope)
  local debugger_scope = scoped.Scope.new(parent_scope)

  -- Create root debugger entity
  local debugger = entities.Debugger.new(graph, {
    uri = uri.debugger(),
  })

  -- Attach scope to debugger for cleanup
  debugger._scope = debugger_scope

  -- Create UI group entities (one-to-one intermediate nodes for tree display)
  for _, spec in ipairs({
    { entities.Breakpoints,           uri.breakpointsGroup(),      "breakpointsGroups" },
    { entities.Sessions,              uri.sessionsGroup(),         "sessionsGroups" },
    { entities.Targets,               uri.targets(),               "targets" },
    { entities.Configs,               uri.configsGroup(),          "configsGroups" },
    { entities.ExceptionFiltersGroup, uri.exceptionFiltersGroup(), "exceptionFiltersGroups" },
  }) do
    debugger[spec[3]]:link(spec[1].new(graph, { uri = spec[2] }))
  end

  ---Use a plugin with this debugger (scoped)
  ---@param plugin neodap.Plugin
  ---@param config? table Optional plugin configuration
  ---@return any
  function debugger:use(plugin, config)
    local result
    scoped.withScope(debugger_scope, function()
      result = plugin(debugger, config)
    end)
    return result
  end

  ---Dispose this debugger and all its subscriptions
  function debugger:dispose()
    debugger_scope:cancel()
  end

  -- Install identity methods (query, watch, queryAll, resolve)
  require("neodap.identity").install(debugger)

  -- Install presentation registry (components, actions)
  require("neodap.presentation").install(debugger)

  -- Initialize ctx API
  entities.Debugger.initCtx(debugger)

  return debugger
end

-- The main debugger instance (created on setup)
---@type neodap.entities.Debugger?
M.debugger = nil

---@type table?
M.graph = nil

---Setup neodap with the main debugger
---@param opts? neodap.Config
---@return neodap.entities.Debugger
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

  -- Create graph with neograph-native, wrapped with scoped reactivity
  M.graph = scoped.wrap(neo.create(schema.schema))

  -- Create the main debugger
  M.debugger = create_debugger_instance(M.graph, scoped.root())

  return M.debugger
end

---Create an isolated debugger (for testing/demos)
---@param opts? neodap.Config
---@return neodap.entities.Debugger
function M.createDebugger(opts)
  opts = vim.tbl_deep_extend("force", defaults, opts or {})

  -- Create isolated graph with neograph-native, wrapped with scoped reactivity
  local graph = scoped.wrap(neo.create(schema.schema))

  return create_debugger_instance(graph, scoped.root())
end

---Use a plugin with the main debugger
---@param plugin neodap.Plugin
---@param config? table Optional plugin configuration
---@return any
function M.use(plugin, config)
  return M.debugger:use(plugin, config)
end

---Dispose everything
function M.dispose()
  scoped.root():cancel()
end

-- Lazy-loaded plugin re-exports for convenience
-- Usage: debugger:use(neodap.plugins.dap)
M.plugins = setmetatable({}, {
  __index = function(t, name)
    local ok, plugin = pcall(require, "neodap.plugins." .. name)
    if ok then
      t[name] = plugin
      return plugin
    end
    error("Unknown plugin: " .. name)
  end,
})

return M
