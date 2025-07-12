local SessionManager = require("neodap.session.manager")
local BreakpointManager = require("neodap.api.Breakpoint.BreakpointManager")
local Api = require("neodap.api.Session.Api")

function setup()
  local sessions = SessionManager.create()
  local api = Api.register(sessions)
  local breakpoints = BreakpointManager.create(api)
  return {
    sessions = sessions,
    api = api,
    breakpoints = breakpoints
  }
end

return {
  setup = setup,
}