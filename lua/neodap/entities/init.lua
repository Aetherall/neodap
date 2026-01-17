-- Entity classes for neograph-native
local entity = require("neodap.entity")

---@class neodap.entities
local M = {}

-- Create entity classes (each has .new(graph, props) constructor)

---@class neodap.entities.Debugger
M.Debugger = entity.class("Debugger")
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
M.Stdio = entity.class("Stdio")
M.Threads = entity.class("Threads")
M.Breakpoints = entity.class("Breakpoints")
M.Sessions = entity.class("Sessions")
M.Targets = entity.class("Targets")

-- Add common methods to all classes
for _, class in pairs({
  M.Debugger, M.Source, M.SourceBinding, M.Breakpoint, M.BreakpointBinding,
  M.Session, M.Thread, M.Stack, M.Frame, M.Scope, M.Variable,
  M.Output, M.ExceptionFilter, M.Stdio, M.Threads, M.Breakpoints, M.Sessions, M.Targets,
}) do
  entity.add_common_methods(class)
end

-- Load entity-specific methods
require("neodap.entities.debugger")(M.Debugger)
require("neodap.entities.source")(M.Source)
require("neodap.entities.source_binding")(M.SourceBinding)
require("neodap.entities.breakpoint")(M.Breakpoint)
require("neodap.entities.breakpoint_binding")(M.BreakpointBinding)
require("neodap.entities.session")(M.Session)
require("neodap.entities.thread")(M.Thread)
require("neodap.entities.stack")(M.Stack)
require("neodap.entities.frame")(M.Frame)
require("neodap.entities.scope")(M.Scope)
require("neodap.entities.variable")(M.Variable)
require("neodap.entities.output")(M.Output)
require("neodap.entities.exception_filter")(M.ExceptionFilter)
require("neodap.entities.stdio")(M.Stdio)
require("neodap.entities.breakpoints")(M.Breakpoints)
require("neodap.entities.sessions")(M.Sessions)
require("neodap.entities.targets")(M.Targets)

return M
