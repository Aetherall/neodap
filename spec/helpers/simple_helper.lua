-- Minimal test helper focusing on boilerplate reduction

local Manager = require("neodap.session.manager")
local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")
local Session = require("neodap.session.session")
local nio = require("nio")
local Api = require("neodap.api.SessionApi")

local SimpleHelper = {}

--- Standard prepare function with optional plugins
--- @param plugins? table Array of plugins to register
--- @return table api, function start
function SimpleHelper.prepare(plugins)
  local manager = Manager.create()
  local adapter = ExecutableTCPAdapter.create({
    executable = {
      cmd = "js-debug",
      cwd = vim.fn.getcwd(),
    },
    connection = {
      host = "::1",
    },
  })

  local api = Api.register(manager)

  -- Register plugins if provided
  if plugins then
    for _, plugin in ipairs(plugins) do
      plugin.plugin(api)
    end
  end

  local function start(fixture)
    local session = Session.create({
      manager = manager,
      adapter = adapter,
    })

    nio.run(function()
    ---@diagnostic disable-next-line
      session:start({
        configuration = {
          type = "pwa-node",
          program = vim.fn.fnamemodify("spec/fixtures/" .. fixture, ":p"),
          cwd = vim.fn.getcwd(),
        },
        request = "launch",
      })
    end)

    return session
  end

  return api, start
end

--- Safe key sending that avoids fast event context errors
--- @param keys string Key sequence
--- @param mode? string Mode (default: 'x')
function SimpleHelper.send_keys(keys, mode)
  mode = mode or 'x'
  vim.schedule(function()
    local processed = vim.api.nvim_replace_termcodes(keys, true, false, true)
    vim.api.nvim_feedkeys(processed, mode, false)
  end)
  nio.sleep(200) -- Standard UI delay
end

--- Enter debug mode safely
function SimpleHelper.enter_debug_mode()
  SimpleHelper.send_keys('<leader>dm')
end

--- Exit debug mode safely
function SimpleHelper.exit_debug_mode()
  SimpleHelper.send_keys('<Esc>')
end

--- Perform stepping operations safely
--- @param step_type string 'over'|'into'|'out'|'prev_frame'
function SimpleHelper.step(step_type)
  local key_map = {
    over = '<Down>',
    into = '<Right>',
    out = '<Up>',
    prev_frame = '<Left>'
  }

  local key = key_map[step_type]
  if not key then
    error("Invalid step type: " .. step_type)
  end

  SimpleHelper.send_keys(key)
  nio.sleep(300) -- Extra time for step operations
end

--- Standard session with breakpoint setup
--- @param api table API object
--- @param fixture string Fixture file
--- @param breakpoint_lines table Array of line numbers
--- @param callback function Called when breakpoint is hit
--- @return any ready_event
function SimpleHelper.session_with_breakpoints(api, fixture, breakpoint_lines, callback)
  local ready = nio.control.event()

  api:onSession(function(session)
    if session.ref.id == 1 then return end

    session:onInitialized(function()
      local breakpoints = {}
      for _, line in ipairs(breakpoint_lines) do
        table.insert(breakpoints, { line = line })
      end

      session.ref.calls:setBreakpoints({
        source = {
          path = vim.fn.fnamemodify("spec/fixtures/" .. fixture, ":p")
        },
        breakpoints = breakpoints
      }):wait()
    end, { once = true })

    session:onThread(function(thread)
      thread:onStopped(function(body)
        if body.reason == "breakpoint" then
          nio.run(function()
            nio.sleep(100)
            callback(thread, body, session)
            ready.set(true)
          end)
        end
      end, { once = true })
    end)
  end)

  return ready
end

return SimpleHelper
