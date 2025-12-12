-- Entity classes for neograph-native
local entity = require("neodap.entity")

---@class neodap.entities
local M = {}

-- Create entity classes (each has .new(graph, props) constructor)

---@class neodap.entities.Debugger
M.Debugger = entity.class("Debugger")
M.Config = entity.class("Config")
M.Source = entity.class("Source")
M.SourceBinding = entity.class("SourceBinding")
M.Breakpoint = entity.class("Breakpoint")
M.BreakpointBinding = entity.class("BreakpointBinding")
M.Session = entity.class("Session")
M.Thread = entity.class("Thread")
M.Stack = entity.class("Stack")
M.Frame = entity.class("Frame")
M.Scope = entity.class("Scope")
M.Variable = entity.class("Variable")
M.Output = entity.class("Output")
M.ExceptionFilter = entity.class("ExceptionFilter")
M.ExceptionFilterBinding = entity.class("ExceptionFilterBinding")
M.Stdio = entity.class("Stdio")
M.Threads = entity.class("Threads")
M.Breakpoints = entity.class("Breakpoints")
M.Configs = entity.class("Configs")
M.Sessions = entity.class("Sessions")
M.Targets = entity.class("Targets")
M.ExceptionFiltersGroup = entity.class("ExceptionFiltersGroup")

-- Add common methods to all classes
for _, class in pairs({
  M.Debugger, M.Config, M.Source, M.SourceBinding, M.Breakpoint, M.BreakpointBinding,
  M.Session, M.Thread, M.Stack, M.Frame, M.Scope, M.Variable,
  M.Output, M.ExceptionFilter, M.ExceptionFilterBinding, M.Stdio, M.Threads,
  M.Breakpoints, M.Configs, M.Sessions, M.Targets, M.ExceptionFiltersGroup,
}) do
  entity.add_common_methods(class)
end

-- Load entity-specific methods (only for entities that have method files)
local entity_methods = {
  { "debugger",                  M.Debugger },
  { "config",                    M.Config },
  { "source",                    M.Source },
  { "breakpoint",               M.Breakpoint },
  { "breakpoint_binding",       M.BreakpointBinding },
  { "session",                   M.Session },
  { "thread",                    M.Thread },
  { "stack",                     M.Stack },
  { "frame",                     M.Frame },
  { "scope",                     M.Scope },
  { "variable",                  M.Variable },
  { "output",                    M.Output },
  { "exception_filter",          M.ExceptionFilter },
  { "exception_filter_binding",  M.ExceptionFilterBinding },
}
for _, spec in ipairs(entity_methods) do
  require("neodap.entities." .. spec[1])(spec[2])
end

return M
