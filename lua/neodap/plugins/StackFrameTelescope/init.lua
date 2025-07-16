local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local StackNavigation = require("neodap.plugins.StackNavigation")
local NvimAsync = require("neodap.tools.async")

-- Check if telescope is available
local telescope_available, telescope = pcall(require, "telescope")
if not telescope_available then
  error("StackFrameTelescope requires telescope.nvim plugin")
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local utils = require("telescope.utils")

---@class neodap.plugin.StackFrameTelescopeProps
---@field api Api
---@field logger Logger
---@field stackNavigation neodap.plugin.StackNavigation

---@class neodap.plugin.StackFrameTelescope: neodap.plugin.StackFrameTelescopeProps
---@field new Constructor<neodap.plugin.StackFrameTelescopeProps>
local StackFrameTelescope = Class()

StackFrameTelescope.name = "StackFrameTelescope"
StackFrameTelescope.description = "Telescope integration for browsing stack frames with location preview"

function StackFrameTelescope.plugin(api)
  local logger = Logger.get()
  
  local instance = StackFrameTelescope:new({
    api = api,
    logger = logger,
    stackNavigation = api:getPluginInstance(StackNavigation),
  })
  
  instance:setup_commands()
  instance:listen()
  
  return instance
end

function StackFrameTelescope:setup_commands()
  vim.api.nvim_create_user_command("NeodapStackFrameTelescope", function()
    self:ShowFramePicker()
  end, { desc = "Show stack frame telescope picker" })
end


function StackFrameTelescope:listen()
  self.api:onSession(function(session)
    session:onTerminated(function()
      -- Clean up any telescope windows if needed
    end)
  end, { name = self.name .. ".onSession" })
end

function StackFrameTelescope:get_current_stack()
  -- Use StackNavigation to find the closest frame, then get its stack
  local closest_frame = self.stackNavigation:getSmartClosestFrame()
  if closest_frame then
    return closest_frame.stack, closest_frame.stack.thread
  end
  
  -- Fallback: find any stopped thread
  for session in self.api:eachSession() do
    for thread in session:eachThread({ filter = 'stopped' }) do
      return thread:stack(), thread
    end
  end
  return nil, nil
end

function StackFrameTelescope:show_frame_picker()
  local stack, thread = self:get_current_stack()
  
  if not stack then
    vim.notify("No active debug session with call stack", vim.log.levels.WARN)
    return
  end
  
  local frames = stack:frames()
  if #frames == 0 then
    vim.notify("Empty call stack", vim.log.levels.WARN)
    return
  end
  
  -- Create telescope picker
  pickers.new({}, {
    prompt_title = "Stack Frames",
    finder = self:create_frame_finder(frames),
    sorter = conf.generic_sorter({}),
    previewer = self:create_frame_previewer(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        
        if selection and selection.frame then
          self:JumpToFrame(selection.frame)
        end
      end)
      
      -- Add custom mappings
      map("i", "<C-j>", actions.move_selection_next)
      map("i", "<C-k>", actions.move_selection_previous)
      map("n", "j", actions.move_selection_next)
      map("n", "k", actions.move_selection_previous)
      
      return true
    end,
  }):find()
end

function StackFrameTelescope:create_frame_finder(frames)
  local entries = {}
  
  for i, frame in ipairs(frames) do
    local display_text = self:format_frame_for_display(frame, i)
    
    table.insert(entries, {
      value = frame,
      display = display_text,
      ordinal = display_text,
      frame = frame,
      frame_index = i,
    })
  end
  
  return finders.new_table({
    results = entries,
    entry_maker = function(entry)
      return entry
    end,
  })
end

function StackFrameTelescope:format_frame_for_display(frame, index)
  local parts = {}
  
  -- Frame number
  table.insert(parts, string.format("#%-2d", index - 1))
  
  -- Function name
  local name = frame.ref.name or "<unknown>"
  table.insert(parts, name)
  
  -- Source information
  if frame.ref.source then
    local source_info = ""
    if frame.ref.source.path then
      source_info = vim.fn.fnamemodify(frame.ref.source.path, ":t")
    elseif frame.ref.source.name then
      source_info = frame.ref.source.name
    end
    
    if frame.ref.line then
      source_info = source_info .. ":" .. frame.ref.line
      if frame.ref.column then
        source_info = source_info .. ":" .. frame.ref.column
      end
    end
    
    if source_info ~= "" then
      table.insert(parts, " at " .. source_info)
    end
  end
  
  return table.concat(parts, "")
end

function StackFrameTelescope:create_frame_previewer()
  return previewers.new_buffer_previewer({
    title = "Frame Location",
    define_preview = function(self, entry, status)
      if not entry.frame then
        return
      end
      
      local frame = entry.frame
      local location = frame:location()
      
      if not location then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
          "No source location available",
          "",
          "Frame: " .. (frame.ref.name or "<unknown>"),
          "ID: " .. frame.ref.id,
        })
        return
      end
      
      -- Use NvimAsync to handle async content fetching properly
      NvimAsync.run(function()
        local session = frame.stack.thread.session
        local source = location.source
        
        -- Add debug logging
        local logger = Logger.get()
        logger:debug("StackFrameTelescope: Attempting to manifest location", location.key)
        
        local success, bufnr = pcall(function()
          return location:manifests(session)
        end)
        
        logger:debug("StackFrameTelescope: Manifest result", success, bufnr)
        
        if not success then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
            "Error manifesting source:",
            tostring(bufnr), -- error message
            "",
            "Location: " .. location.key,
            "Frame: " .. (frame.ref.name or "<unknown>"),
          })
          return
        end
        
        if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
          -- Provide more detailed information about what went wrong
          local debug_info = {
            "Could not manifest source",
            "",
            "Location: " .. location.key,
            "Session ID: " .. session.ref.id,
          }
          
          if source then
            table.insert(debug_info, "Source name: " .. (source.ref.name or "nil"))
            table.insert(debug_info, "Source path: " .. (source.ref.path or "nil"))
            if source.ref.sourceReference then
              table.insert(debug_info, "Source reference: " .. source.ref.sourceReference)
            end
          else
            table.insert(debug_info, "No source object available")
          end
          
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, debug_info)
          return
        end
        
        -- Get content from the manifested buffer
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        if not lines or #lines == 0 then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
            "Source buffer is empty",
            "",
            "Location: " .. location.key,
          })
          return
        end
        
        -- Set the content
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        
        -- Try to set the filetype for syntax highlighting
        if source and source.ref.path then
          local filetype = vim.filetype.match({ filename = source.ref.path })
          if filetype then
            vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", filetype)
          end
        elseif source and source.ref.name then
          -- Try to guess filetype from name
          local filetype = vim.filetype.match({ filename = source.ref.name })
          if filetype then
            vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", filetype)
          end
        end
        
        -- Highlight the current line
        local line_num = frame.ref.line
        if line_num and line_num > 0 and line_num <= #lines then
          -- Clear any existing highlights
          vim.api.nvim_buf_clear_namespace(self.state.bufnr, -1, 0, -1)
          
          -- Add line highlight
          vim.api.nvim_buf_add_highlight(
            self.state.bufnr,
            -1,
            "CursorLine",
            line_num - 1,
            0,
            -1
          )
          
          -- Center the preview window on the frame line
          local win_height = vim.api.nvim_win_get_height(status.preview_win)
          local half_height = math.floor(win_height / 2)
          
          -- Calculate the top line to center the frame line in the window
          local top_line = math.max(1, line_num - half_height)
          
          -- Ensure we don't scroll past the end of the buffer
          local max_top_line = math.max(1, #lines - win_height + 1)
          top_line = math.min(top_line, max_top_line)
          
          -- Set cursor to the frame line (with proper column positioning)
          local column = math.max(0, (frame.ref.column or 1) - 1) -- Convert to 0-based
          vim.api.nvim_win_set_cursor(status.preview_win, {line_num, column})
          
          -- Set the window view to center the frame line
          vim.api.nvim_win_call(status.preview_win, function()
            vim.fn.winrestview({
              lnum = line_num,
              col = column,
              topline = top_line,
              coladd = 0,
              curswant = column,
            })
          end)
          
          -- Set a mark for the frame line
          vim.api.nvim_buf_set_mark(self.state.bufnr, "f", line_num, (frame.ref.column or 1) - 1, {})
        end
      end)
    end,
  })
end

function StackFrameTelescope:jump_to_frame(frame)
  if not frame then
    return
  end
  
  local success, error_msg = pcall(function()
    frame:jump()
    self.logger:info("StackFrameTelescope: Jumped to frame", frame.ref.id)
  end)
  
  if not success then
    self.logger:error("StackFrameTelescope: Failed to jump to frame", error_msg)
    vim.notify("Failed to jump to frame: " .. tostring(error_msg), vim.log.levels.ERROR)
  end
end

-- Auto-wrapped version for vim context boundaries
function StackFrameTelescope:JumpToFrame(frame)
  return self:jump_to_frame(frame)
end

function StackFrameTelescope:is_available()
  return telescope_available
end

function StackFrameTelescope:destroy()
  self.logger:debug("StackFrameTelescope: Destroying plugin")
  
  -- Clean up user commands
  pcall(vim.api.nvim_del_user_command, "NeodapStackFrameTelescope")
  
  self.logger:info("StackFrameTelescope: Plugin destroyed")
end

return StackFrameTelescope