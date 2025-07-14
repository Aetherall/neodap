local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local NvimAsync = require("neodap.tools.async")
local Location = require("neodap.api.Location")

---@class neodap.plugin.FrameHighlightProps
---@field api Api
---@field logger Logger
---@field namespace integer
---@field frame_locations table<string, { location: api.Location, thread_id: integer }[]> -- URI -> location data
---@field hl_group string

---@class neodap.plugin.FrameHighlight: neodap.plugin.FrameHighlightProps
---@field new Constructor<neodap.plugin.FrameHighlightProps>
local FrameHighlight = Class()

FrameHighlight.name = "FrameHighlight"
FrameHighlight.description = "Highlight all frames of stopped threads when buffers become visible"

function FrameHighlight.plugin(api)
  local logger = Logger.get()
  
  local instance = FrameHighlight:new({
    api = api,
    logger = logger,
    namespace = vim.api.nvim_create_namespace("neodap_frame_highlight"),
    frame_locations = {},
    hl_group = "NeodapFrameHighlight"
  })
  
  -- Setup highlight group if it doesn't exist
  vim.api.nvim_set_hl(0, instance.hl_group, { 
    default = true, 
    link = "CursorLine" 
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

-- Collect frame locations without loading buffers
function FrameHighlight:collectFrameLocations(thread)
  self.logger:info("FrameHighlight: Collecting frame locations for thread", thread.id)
  
  local stack = thread:stack()
  if not stack then
    self.logger:warn("FrameHighlight: No stack for thread", thread.id)
    return
  end
  
  local frames = stack:frames()
  if not frames then
    self.logger:warn("FrameHighlight: No frames for thread", thread.id)
    return
  end
  
  self.logger:debug("FrameHighlight: Found", #frames, "frames in stack for thread", thread.id)
  
  -- Group locations by buffer URI for efficient highlighting
  local locations_by_uri = {}
  
  for i, frame in ipairs(frames) do
    local location = frame:location()
    if location then
      -- Get buffer URI without loading the buffer
      local uri = location:toUri()
      
      self.logger:debug("FrameHighlight: Frame", i, "location:", {
        key = location.key,
        line = location.line,
        column = location.column,
        uri = uri,
        sourceId = location.sourceId:toString()
      })
      
      if uri and uri ~= "" then
        if not locations_by_uri[uri] then
          locations_by_uri[uri] = {}
        end
        
        table.insert(locations_by_uri[uri], {
          location = location,
          thread_id = thread.id
        })
        
        self.logger:debug("FrameHighlight: Added frame", i, "to URI:", uri)
      else
        self.logger:warn("FrameHighlight: Frame", i, "has empty or nil URI")
      end
    else
      self.logger:warn("FrameHighlight: Frame", i, "has no location")
    end
  end
  
  -- Merge with existing locations
  for uri, locations in pairs(locations_by_uri) do
    if not self.frame_locations[uri] then
      self.frame_locations[uri] = {}
    end
    
    for _, loc_data in ipairs(locations) do
      table.insert(self.frame_locations[uri], loc_data)
    end
    
    self.logger:debug("FrameHighlight: URI", uri, "now has", #self.frame_locations[uri], "total locations")
  end
  
  self.logger:info("FrameHighlight: Collected", vim.tbl_count(locations_by_uri), "URIs with frame locations for thread", thread.id)
  self.logger:debug("FrameHighlight: Total tracked URIs:", vim.tbl_count(self.frame_locations))
  
  -- Apply highlights to already visible buffers
  self:highlightVisibleBuffers()
end

-- Remove frame highlights for a specific thread
function FrameHighlight:removeThreadFrames(thread)
  local removed_count = 0
  
  -- Remove locations associated with this thread
  for uri, locations in pairs(self.frame_locations) do
    local original_count = #locations
    
    self.frame_locations[uri] = vim.tbl_filter(function(loc_data)
      return loc_data.thread_id ~= thread.id
    end, locations)
    
    removed_count = removed_count + (original_count - #self.frame_locations[uri])
    
    -- Clean up empty entries
    if #self.frame_locations[uri] == 0 then
      self.frame_locations[uri] = nil
    end
  end
  
  self.logger:debug("FrameHighlight: Removed", removed_count, "frame locations for thread", thread.id)
  
  -- Update visible buffers
  self:highlightVisibleBuffers()
end

-- Setup autocommands to react to buffer events
function FrameHighlight:setupAutocommands()
  local group = vim.api.nvim_create_augroup("FrameHighlight", { clear = true })
  
  -- When a buffer becomes visible, apply highlights
  vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter", "BufReadPost"}, {
    group = group,
    callback = function(args)
      NvimAsync.run(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          self:highlightBuffer(args.buf)
        end
      end)
    end,
    desc = "Apply frame highlights when buffer becomes visible"
  })
  
  -- When switching windows, ensure highlights are applied
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      NvimAsync.run(function()
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_valid(bufnr) then
          self:highlightBuffer(bufnr)
        end
      end)
    end,
    desc = "Apply frame highlights when entering window"
  })
  
  self.logger:debug("FrameHighlight: Autocommands setup complete")
end

-- Highlight a specific buffer if it has frame locations
function FrameHighlight:highlightBuffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    self.logger:debug("FrameHighlight: Invalid buffer", bufnr)
    return
  end
  
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then
    self.logger:debug("FrameHighlight: Buffer", bufnr, "has no name")
    return
  end
  
  -- Convert buffer path to URI for comparison
  local uri
  if bufname:match("^virtual://") then
    -- Buffer name is already a virtual URI, use it directly
    uri = bufname
  else
    -- File buffer, convert to URI
    uri = vim.uri_from_fname(bufname)
  end
  
  self.logger:debug("FrameHighlight: Highlighting buffer", bufnr, "name:", bufname, "uri:", uri)
  
  -- Clear existing highlights for this buffer
  vim.api.nvim_buf_clear_namespace(bufnr, self.namespace, 0, -1)
  
  -- Check if we have frame locations for this buffer
  local locations = self.frame_locations[uri]
  if not locations or #locations == 0 then
    self.logger:debug("FrameHighlight: No locations found for URI:", uri)
    self.logger:debug("FrameHighlight: Available URIs:", vim.tbl_keys(self.frame_locations))
    return
  end
  
  self.logger:debug("FrameHighlight: Found", #locations, "locations for buffer", bufname)
  
  -- Apply highlights for each frame location
  local applied_count = 0
  local checked_count = 0
  
  for i, loc_data in ipairs(locations) do
    local location = loc_data.location
    checked_count = checked_count + 1
    
    self.logger:debug("FrameHighlight: Checking location", i, "thread:", loc_data.thread_id, "key:", location.key)
    
    -- Verify this location matches the current buffer
    local loc_bufnr = location:bufnr()
    self.logger:debug("FrameHighlight: Location bufnr:", loc_bufnr, "target bufnr:", bufnr)
    
    if loc_bufnr == bufnr then
      self.logger:debug("FrameHighlight: Applying highlight for location:", {
        line = location.line,
        column = location.column,
        key = location.key
      })
      
      if self:applyHighlight(bufnr, location) then
        applied_count = applied_count + 1
        self.logger:debug("FrameHighlight: Successfully applied highlight", applied_count)
      else
        self.logger:warn("FrameHighlight: Failed to apply highlight for location", location.key)
      end
    else
      self.logger:debug("FrameHighlight: Location bufnr mismatch - skipping")
    end
  end
  
  self.logger:info("FrameHighlight: Buffer", bufname, "- checked:", checked_count, "applied:", applied_count, "highlights")
end

-- Apply highlight to a specific location
function FrameHighlight:applyHighlight(bufnr, location)
  local line = (location.line or 1) - 1  -- Convert to 0-based
  local col = (location.column or 1) - 1
  
  self.logger:debug("FrameHighlight: Applying highlight at line:", line + 1, "col:", col + 1, "bufnr:", bufnr)
  
  -- Ensure line is within buffer bounds
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  self.logger:debug("FrameHighlight: Buffer has", line_count, "lines, target line:", line + 1)
  
  if line >= line_count then
    self.logger:warn("FrameHighlight: Line", line + 1, "is beyond buffer bounds (", line_count, "lines)")
    return false
  end
  
  -- Get line content for verification
  local lines = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)
  if #lines == 0 then
    self.logger:warn("FrameHighlight: No lines returned for line", line + 1)
    return false
  end
  
  local line_content = lines[1]
  if not line_content then
    self.logger:warn("FrameHighlight: Line", line + 1, "has no content")
    return false
  end
  
  self.logger:debug("FrameHighlight: Line content:", line_content:sub(1, 50) .. (line_content:len() > 50 and "..." or ""))
  
  -- Apply highlight to entire line
  self.logger:debug("FrameHighlight: Applying highlight with:", {
    bufnr = bufnr,
    namespace = self.namespace,
    hl_group = self.hl_group,
    line = line,
    start_col = 0,
    end_col = -1
  })
  
  local ok, err = pcall(vim.api.nvim_buf_add_highlight,
    bufnr,
    self.namespace,
    self.hl_group,
    line,
    0,  -- Start at beginning of line
    -1  -- Highlight entire line
  )
  
  if not ok then
    self.logger:error("FrameHighlight: Failed to add highlight:", err)
    return false
  end
  
  self.logger:debug("FrameHighlight: Successfully added highlight for line", line + 1)
  return true
end

-- Highlight all currently visible buffers
function FrameHighlight:highlightVisibleBuffers()
  -- Get unique buffers from all windows
  local visible_buffers = {}
  
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if vim.api.nvim_buf_is_valid(bufnr) then
        visible_buffers[bufnr] = true
      end
    end
  end
  
  -- Apply highlights to each visible buffer
  for bufnr, _ in pairs(visible_buffers) do
    self:highlightBuffer(bufnr)
  end
end

-- Get current highlight statistics
function FrameHighlight:getStats()
  local total_locations = 0
  local uri_count = vim.tbl_count(self.frame_locations)
  local thread_ids = {}
  
  for _, locations in pairs(self.frame_locations) do
    total_locations = total_locations + #locations
    for _, loc_data in ipairs(locations) do
      thread_ids[loc_data.thread_id] = true
    end
  end
  
  return {
    total_locations = total_locations,
    uri_count = uri_count,
    thread_count = vim.tbl_count(thread_ids)
  }
end

-- Cleanup method
function FrameHighlight:destroy()
  self.logger:debug("FrameHighlight: Destroying plugin")
  
  -- Clear all highlights from all buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, self.namespace, 0, -1)
    end
  end
  
  -- Clear autocommands
  pcall(vim.api.nvim_del_augroup_by_name, "FrameHighlight")
  
  -- Clear state
  self.frame_locations = {}
  
  self.logger:info("FrameHighlight: Plugin destroyed")
end

return FrameHighlight