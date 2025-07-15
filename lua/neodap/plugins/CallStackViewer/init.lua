local nio = require("nio")
local Window = require("neodap.plugins.CallStackViewer.window")
local Renderer = require("neodap.plugins.CallStackViewer.renderer")

local M = {
  name = "CallStackViewer"
}

local state = {
  api = nil,
  current_session = nil,
  current_thread = nil,
  current_stack = nil,
  window = nil,
  renderer = nil,
}

local function setup_commands()
  vim.api.nvim_create_user_command("NeodapCallStack", function()
    M.show()
  end, { desc = "Show call stack in floating window" })
  
  vim.api.nvim_create_user_command("NeodapCallStackHide", function()
    M.hide()
  end, { desc = "Hide call stack window" })
  
  vim.api.nvim_create_user_command("NeodapCallStackToggle", function()
    M.toggle()
  end, { desc = "Toggle call stack window" })
end

local function on_cursor_moved()
  if not state.window or not state.window:is_open() then
    return
  end
  
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  nio.run(function()
    if state.renderer then
      state.renderer:highlight_frame_at_line(bufnr, line)
    end
  end)
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("NeodapCallStackViewer", { clear = true })
  
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = on_cursor_moved,
  })
end

function M.show()
  if not state.current_stack then
    vim.notify("No active debug session with call stack", vim.log.levels.INFO)
    return
  end
  
  if not state.window then
    state.window = Window.new()
    state.renderer = Renderer.new(state.window)
  end
  
  nio.run(function()
    state.window:open()
    state.renderer:render(state.current_stack, state.current_thread)
  end)
end

function M.hide()
  if state.window then
    state.window:close()
  end
end

function M.toggle()
  if state.window and state.window:is_open() then
    M.hide()
  else
    M.show()
  end
end

function M.plugin(api)
  state.api = api
  
  setup_commands()
  setup_autocmds()
  
  api:onSession(function(session)
    state.current_session = session
    
    session:onThread(function(thread)
      thread:onStopped(function(stopped_event)
        nio.run(function()
          state.current_thread = thread
          state.current_stack = thread:stack()
          
          if state.window and state.window:is_open() then
            state.renderer:render(state.current_stack, thread)
          end
        end)
      end)
      
      thread:onResumed(function()
        state.current_stack = nil
        if state.window and state.window:is_open() then
          state.window:clear()
        end
      end)
    end)
    
    session:onTerminated(function()
      if session == state.current_session then
        state.current_session = nil
        state.current_thread = nil
        state.current_stack = nil
        M.hide()
      end
    end)
  end)
end

return M