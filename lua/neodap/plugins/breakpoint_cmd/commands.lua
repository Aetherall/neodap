-- Vim command for DapBreakpoint
local Location = require("neodap.location")
local update = require("neodap.plugins.breakpoint_cmd.update")

local function parse_target(target)
  if not target or target == "" then return Location.from_cursor() end
  local path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  local line, col = target:match("^(%d+):(%d+)$")
  if line then return Location.new(path, tonumber(line), tonumber(col)) end
  line = target:match("^(%d+)$")
  if line then return Location.new(path, tonumber(line)) end
end

local function with_value(args)
  local target, start = nil, 2
  if args[2] and args[2]:match("^%d+:?%d*$") then target, start = args[2], 3 end
  return parse_target(target), table.concat(vim.list_slice(args, start), " ")
end

local function setup(api, debugger, await_adjust, candidates_at, disambiguate)
  update.setup(api, debugger, await_adjust, candidates_at, disambiguate)
  local handlers = {
    toggle = function(a) api.toggle(parse_target(a[2])) end,
    enable = function(a) api.enable(parse_target(a[2])) end,
    disable = function(a) api.disable(parse_target(a[2])) end,
    condition = function(a) api.set_condition(with_value(a)) end,
    log = function(a) api.set_log_message(with_value(a)) end,
    clear = function()
      local bps = {}
      for bp in debugger.breakpoints:iter() do table.insert(bps, bp) end
      for _, bp in ipairs(bps) do bp:remove() end
      for source in debugger.sources:iter() do source:syncBreakpoints() end
    end,
  }
  vim.api.nvim_create_user_command("DapBreakpoint", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local handler = handlers[args[1]]
    if handler then return handler(args) end
    local loc = parse_target(args[1])
    if loc then api.toggle(loc) end
  end, { nargs = "*", desc = "Manage DAP breakpoints" })
end

return { setup = setup }
