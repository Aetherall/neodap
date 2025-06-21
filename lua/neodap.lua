local M = {}

function M.setup()
  local Manager = require("neodap.session.manager")
  local Api = require("neodap.api.Api")

  local manager = Manager.create()
  local api = Api.register(manager)

  return manager, api
end

return M
