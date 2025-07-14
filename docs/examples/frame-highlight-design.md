# FrameHighlight Plugin Design Example

This document demonstrates how to design a Neodap plugin following the architectural guidelines. The FrameHighlight plugin maintains highlights for all frames of stopped threads across buffers without loading them unnecessarily.

## 📋 Requirements Analysis

**Goal**: Highlight all stack frames of stopped threads when their buffers become visible

**Constraints**:
- Must not load buffers proactively
- Should react to buffer visibility changes
- Must clean up when threads resume/exit
- Should handle multiple sessions and threads

## 🎯 Architectural Decision: Pattern Selection

### Why Pure Reactive Pattern?

This plugin requires **pure reactive pattern** because:

1. **No User Actions**: Plugin provides automatic visual feedback without user interaction
2. **System State Changes**: Reacts to thread state (stopped/resumed) and buffer events
3. **Visual Feedback Nature**: Shows what's happening in the system
4. **Continuous Updates**: Must track ongoing system changes

```lua
// ✅ CORRECT: Reactive pattern for system state
thread:onStopped(function()
  self:collectFrameLocations(thread)  // React to thread state
end)

// ✅ CORRECT: Reactive pattern for buffer events  
vim.api.nvim_create_autocmd({"BufEnter"}, {
  callback = function(args)
    self:highlightBuffer(args.buf)  // React to buffer visibility
  end
})
```

## 🏗️ Design Decisions

### 1. **Lazy Buffer Interaction**

**Problem**: We need to track frame locations without loading all buffers

**Solution**: Use URI-based indexing
```lua
-- Index by URI without loading buffer
local uri = location:toUri()
self.frame_locations[uri] = locations

-- Only interact with buffer when it becomes visible
function FrameHighlight:highlightBuffer(bufnr)
  local uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(bufnr))
  local locations = self.frame_locations[uri]  -- O(1) lookup
end
```

### 2. **Thread-Aware State Management**

**Problem**: Need to clean up highlights when specific threads resume

**Solution**: Track thread ownership
```lua
-- Store thread ID with each location
table.insert(self.frame_locations[uri], {
  location = location,
  thread_id = thread.id  -- Track ownership
})

-- Filter by thread ID during cleanup
self.frame_locations[uri] = vim.tbl_filter(function(loc_data)
  return loc_data.thread_id ~= thread.id
end, locations)
```

### 3. **Efficient Event Handling**

**Problem**: Need to apply highlights efficiently without constant polling

**Solution**: React to specific events
```lua
-- Thread events for state changes
thread:onStopped()   -- Collect frame locations
thread:onResumed()   -- Remove highlights
thread:onExited()    -- Clean up

-- Buffer events for visibility
BufEnter            -- Apply highlights when visible
BufWinEnter         -- Handle new windows
```

## 📊 State Management Strategy

### Data Structure
```lua
frame_locations = {
  ["file:///path/to/file.js"] = {
    { location = Location, thread_id = 1 },
    { location = Location, thread_id = 2 }
  },
  ["virtual://abc123/eval"] = {
    { location = Location, thread_id = 3 }
  }
}
```

### Benefits:
- **O(1) lookup** by buffer URI
- **Easy cleanup** by thread ID
- **No buffer loading** required
- **Supports virtual sources**

## 🔄 Lifecycle Management

### Plugin Lifecycle
```
1. Plugin Creation
   ├── Create namespace
   ├── Initialize frame_locations table
   └── Setup reactive listeners

2. Runtime Operation
   ├── Thread Stops → Collect frame locations (by URI)
   ├── Buffer Visible → Apply highlights (if URI matches)
   ├── Thread Resumes → Remove thread's locations
   └── Buffer Hidden → Highlights auto-cleared by Neovim

3. Plugin Destruction
   ├── Clear all highlights
   ├── Remove autocommands
   └── Clean up namespace
```

## ⚡ Performance Considerations

### Optimizations Applied:

1. **No Proactive Buffer Loading**
   - Use `location:toUri()` for indexing
   - Only `location:bufnr()` when buffer is already visible

2. **Efficient Lookups**
   - O(1) URI-based location lookup
   - No iteration over all buffers

3. **Minimal Re-computation**
   - Collect locations once when thread stops
   - Apply highlights only on buffer visibility change

4. **Smart Cleanup**
   - Thread-specific removal without affecting other threads
   - Automatic highlight cleanup when buffer unloads

## 🎨 Implementation Highlights

### Key Methods:

**`collectFrameLocations(thread)`**
- Iterates thread's stack frames
- Groups locations by URI
- Never loads buffers

**`highlightBuffer(bufnr)`**
- Checks if buffer URI has locations
- Applies highlights only if matches exist
- Clears old highlights first

**`removeThreadFrames(thread)`**
- Filters out thread-specific locations
- Updates visible buffers
- Cleans up empty entries

## ✅ Guideline Compliance

### Following Plugin Architecture Guide:

**Pattern Selection**: ✅
- Pure reactive pattern for system state changes
- No intentional patterns (no user actions)

**API Integration**: ✅
- Leverages Location API (`toUri()`, `bufnr()`)
- Uses thread lifecycle events
- Integrates with Neovim autocommands

**Performance**: ✅
- Lazy buffer loading strategy
- Efficient URI-based indexing
- Smart event-driven updates

**Code Quality**: ✅
- Single responsibility methods
- Clear state management
- Proper cleanup on destroy

## 🚀 Benefits of This Design

1. **Memory Efficient**: Doesn't load unnecessary buffers
2. **CPU Efficient**: O(1) lookups, event-driven updates
3. **User Transparent**: Automatic visual feedback
4. **Multi-Session**: Handles frames from all sessions
5. **Clean Architecture**: Clear separation of concerns

## 📝 Lessons for Future Plugins

This design demonstrates:

1. **Reactive patterns** are ideal for visual feedback plugins
2. **URI-based indexing** enables buffer tracking without loading
3. **Thread ownership tracking** allows precise cleanup
4. **Event-driven updates** are more efficient than polling
5. **Lazy loading** improves performance and memory usage

The FrameHighlight plugin showcases how following architectural guidelines results in a clean, efficient, and maintainable implementation that solves complex problems (cross-buffer, multi-thread highlighting) with minimal code.



```lua
local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")

---@class neodap.plugin.FrameHighlightProps
---@field api Api
---@field logger Logger
---@field namespace integer
---@field frame_locations table<string, api.Location[]> -- bufname -> locations
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

  instance:listen()
  instance:setupAutocommands()

  return instance
end

-- Reactive: Track frame locations without loading buffers
function FrameHighlight:listen()
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
  local stack = thread:stack()
  if not stack then return end

  local frames = stack:frames()
  if not frames then return end

  -- Group locations by buffer URI for efficient highlighting
  local locations_by_buffer = {}

  for _, frame in ipairs(frames) do
    local location = frame:location()
    if location then
      -- Get buffer URI without loading the buffer
      local uri = location:toUri()

      if not locations_by_buffer[uri] then
        locations_by_buffer[uri] = {}
      end

      table.insert(locations_by_buffer[uri], {
        location = location,
        thread_id = thread.id
      })
    end
  end

  -- Merge with existing locations
  for uri, locations in pairs(locations_by_buffer) do
    if not self.frame_locations[uri] then
      self.frame_locations[uri] = {}
    end

    for _, loc_data in ipairs(locations) do
      table.insert(self.frame_locations[uri], loc_data)
    end
  end

  self.logger:debug("FrameHighlight: Collected frames for thread", thread.id)

  -- Apply highlights to already visible buffers
  self:highlightVisibleBuffers()
end

-- Remove frame highlights for a specific thread
function FrameHighlight:removeThreadFrames(thread)
  -- Remove locations associated with this thread
  for uri, locations in pairs(self.frame_locations) do
    self.frame_locations[uri] = vim.tbl_filter(function(loc_data)
      return loc_data.thread_id ~= thread.id
    end, locations)

    -- Clean up empty entries
    if #self.frame_locations[uri] == 0 then
      self.frame_locations[uri] = nil
    end
  end

  self.logger:debug("FrameHighlight: Removed frames for thread", thread.id)

  -- Update visible buffers
  self:highlightVisibleBuffers()
end

-- Setup autocommands to react to buffer events
function FrameHighlight:setupAutocommands()
  local group = vim.api.nvim_create_augroup("FrameHighlight", { clear = true })

  -- When a buffer becomes visible, apply highlights
  vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
    group = group,
    callback = function(args)
      self:highlightBuffer(args.buf)
    end
  })

  -- When a buffer is about to be unloaded, we don't need to do anything
  -- The highlights will be cleared automatically
end

-- Highlight a specific buffer if it has frame locations
function FrameHighlight:highlightBuffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then return end

  -- Convert buffer path to URI for comparison
  local uri = vim.uri_from_fname(bufname)

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, self.namespace, 0, -1)

  -- Check if we have frame locations for this buffer
  local locations = self.frame_locations[uri]
  if not locations or #locations == 0 then
    return
  end

  -- Apply highlights for each frame location
  for _, loc_data in ipairs(locations) do
    local location = loc_data.location

    -- Only highlight if buffer matches the location
    if location:bufnr() == bufnr then
      self:applyHighlight(bufnr, location)
    end
  end

  self.logger:debug("FrameHighlight: Applied highlights to buffer", bufname)
end

-- Apply highlight to a specific location
function FrameHighlight:applyHighlight(bufnr, location)
  local line = (location.line or 1) - 1  -- Convert to 0-based
  local col = (location.column or 1) - 1

  -- Ensure line is within buffer bounds
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line >= line_count then return end

  -- Get line content for end column
  local line_content = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
  if not line_content then return end

  local end_col = #line_content

  -- Apply highlight
  vim.api.nvim_buf_add_highlight(
    bufnr,
    self.namespace,
    self.hl_group,
    line,
    col,
    end_col
  )
end

-- Highlight all currently visible buffers
function FrameHighlight:highlightVisibleBuffers()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    self:highlightBuffer(bufnr)
  end
end

-- Cleanup method
function FrameHighlight:destroy()
  -- Clear all highlights
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, self.namespace, 0, -1)
    end
  end

  -- Clear autocommands
  vim.api.nvim_del_augroup_by_name("FrameHighlight")

  self.logger:debug("FrameHighlight: Plugin destroyed")
end

return FrameHighlight
```