local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local NvimAsync = require("neodap.tools.async")

---@class neodap.plugin.FrameHighlightProps
---@field api Api
---@field logger Logger
---@field namespace integer
---@field highlights table<integer, {location: api.Location, frame_index: integer}[]> -- thread_id -> frame data
---@field top_frame_hl_group string
---@field other_frame_hl_group string

---@class neodap.plugin.FrameHighlight: neodap.plugin.FrameHighlightProps
---@field new Constructor<neodap.plugin.FrameHighlightProps>
local FrameHighlight = Class()

FrameHighlight.name = "FrameHighlight"
FrameHighlight.description = "Highlight all frames of stopped threads when buffers become visible"

function FrameHighlight.plugin(api)
  local logger = Logger.get("Plugin:FrameHighlight")
  
  local instance = FrameHighlight:new({
    api = api,
    logger = logger,
    namespace = vim.api.nvim_create_namespace("neodap_frame_highlight"),
    highlights = {},
    top_frame_hl_group = "NeodapTopFrameHighlight",
    other_frame_hl_group = "NeodapOtherFrameHighlight"
  })
  
  -- Setup highlight groups
  vim.api.nvim_set_hl(0, instance.top_frame_hl_group, { 
    default = true, 
    bg = "#FF8C00", -- Orange background for top frame
    blend = 90,
  })
  
  vim.api.nvim_set_hl(0, instance.other_frame_hl_group, { 
    default = true, 
    bg = "#20B2AA", -- Bluish-green background for other frames
    blend = 90,
  })
  
  instance:listen()
  instance:setupAutocommands()
  
  return instance
end

-- Reactive: Track frame locations without loading buffers
function FrameHighlight:listen()
  self.logger:debug("FrameHighlight: Setting up reactive listeners")
  
  self.api:onSession(function(session)
    session:onThread(function(thread)
      
      -- When thread stops, collect frame locations
      thread:onStopped(function()
        self:collectFrameLocations(thread)
      end, { name = self.name .. ".onStopped" })
      
      -- When thread resumes, remove its frame highlights
      thread:onResumed(function()
        self:removeThreadFrames(thread)
      end, { name = self.name .. ".onResumed" })
      
      -- When thread exits, clean up
      thread:onExited(function()
        self:removeThreadFrames(thread)
      end, { name = self.name .. ".onExited" })
      
    end, { name = self.name .. ".onThread" })
  end, { name = self.name .. ".onSession" })
end

-- Collect frame locations and apply highlights directly
function FrameHighlight:collectFrameLocations(thread)
  self.logger:debug("FrameHighlight: Collecting frame locations for thread", thread.id)
  
  local stack = thread:stack()
  if not stack then
    return
  end
  
  local frames = stack:frames()
  if not frames then
    return
  end
  
  -- Collect all locations from frames with their indices
  local frame_data = {}
  for i, frame in ipairs(frames) do
    local location = frame:location()
    if location then
      table.insert(frame_data, {
        location = location,
        frame_index = i
      })
    end
  end
  
  -- Store frame data for this thread
  self.highlights[thread.id] = frame_data
  self.logger:debug("FrameHighlight: Stored", #frame_data, "locations for thread", thread.id)
  
  -- Apply highlights to all stored locations
  self:HighlightAllVisibleLocations()
end

-- Highlight all stored locations that are currently visible
function FrameHighlight:HighlightAllVisibleLocations()
  self.logger:debug("FrameHighlight: Highlighting all visible locations")
  
  for thread_id, frame_data in pairs(self.highlights) do
    for _, data in ipairs(frame_data) do
      local location = data.location
      local frame_index = data.frame_index
      
      -- Use orange for top frame (index 1), bluish-green for others
      local hl_group = frame_index == 1 and self.top_frame_hl_group or self.other_frame_hl_group
      
      location:highlight(self.namespace, hl_group)
      
      self.logger:debug("FrameHighlight: Highlighted frame", frame_index, "with", hl_group, "at", location.key)
    end
  end
end



-- Remove frame highlights for a specific thread
function FrameHighlight:removeThreadFrames(thread)
  local frame_data = self.highlights[thread.id]
  if not frame_data then
    self.logger:debug("FrameHighlight: No locations to remove for thread", thread.id)
    return
  end
  
  -- Unhighlight all locations for this thread
  for _, data in ipairs(frame_data) do
    data.location:unhighlight(self.namespace)
  end
  
  -- Remove from storage
  self.highlights[thread.id] = nil
  self.logger:debug("FrameHighlight: Removed", #frame_data, "locations for thread", thread.id)
end

-- Setup autocommands to react to buffer events
function FrameHighlight:setupAutocommands()
  local group = vim.api.nvim_create_augroup("FrameHighlight", { clear = true })
  
  -- When a buffer becomes visible, apply highlights to all stored locations
  vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter", "BufReadPost"}, {
    group = group,
    callback = function()
      self:HighlightAllVisibleLocations()
    end,
    desc = "Apply frame highlights when buffer becomes visible"
  })
  
  self.logger:debug("FrameHighlight: Autocommands setup complete")
end

-- Cleanup method
function FrameHighlight:destroy()
  self.logger:debug("FrameHighlight: Destroying plugin")
  
  -- Unhighlight all stored locations
  for _, frame_data in pairs(self.highlights) do
    for _, data in ipairs(frame_data) do
      data.location:unhighlight(self.namespace)
    end
  end
  
  -- Clear autocommands
  pcall(vim.api.nvim_del_augroup_by_name, "FrameHighlight")
  
  -- Clear state
  self.highlights = {}
  
  self.logger:debug("FrameHighlight: Plugin destroyed")
end

return FrameHighlight