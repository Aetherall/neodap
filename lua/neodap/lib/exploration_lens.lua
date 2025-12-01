-- exploration_lens.lua
-- Context-aware exploration state management for tree windows
--
-- The Exploration Lens sits above TreeWindow and manages context-relative
-- exploration state (focus + expansion). When context changes, it:
-- 1. BURNs the pattern into the old context's entities (materializes state)
-- 2. TRANSPOSEs the pattern to the new context (applies state)
--
-- This allows user exploration to "follow" context changes while preserving
-- state at previous contexts.

local neostate = require("neostate")

---@class ExplorationLens
---@field window TreeWindow The tree window being managed
---@field context_signal Signal Signal that provides current context entity
---@field pattern { focus: string?, expansion: table<string, boolean> } Relative exploration state
---@field context_vuri string? Current context's vuri
---@field context_entity_uri string? Current context's entity URI
---@field pending_path string[]? Remaining path segments for async navigation
---@field pending_retries number Retry counter for async navigation
---@field _subscriptions function[] Cleanup functions
---@field _focus_sub function? Focus signal subscription
local ExplorationLens = {}
ExplorationLens.__index = ExplorationLens

local MAX_PENDING_RETRIES = 5

---Create a new ExplorationLens
---@param window TreeWindow The tree window to manage
---@param context_signal Signal Signal that provides current context entity
---@param opts? { on_render?: function } Optional callbacks
---@return ExplorationLens
function ExplorationLens:new(window, context_signal, opts)
  opts = opts or {}

  local self = setmetatable({}, ExplorationLens)

  self.window = window
  self.context_signal = context_signal
  self.on_render = opts.on_render

  -- Pattern: relative exploration state
  self.pattern = {
    focus = nil,       -- Relative focus path from context (e.g., "Locals/myVar")
    expansion = {},    -- Relative path -> expanded (true) or collapsed (false)
  }

  -- Current context tracking
  self.context_vuri = nil
  self.context_entity_uri = nil

  -- Async navigation state
  self.pending_path = nil
  self.pending_retries = 0

  -- Subscriptions for cleanup
  self._subscriptions = {}

  -- Initialize with current context
  local initial_entity = context_signal:get()
  if initial_entity then
    self.context_entity_uri = initial_entity.uri
    self.context_vuri = self:_compute_context_vuri(initial_entity.uri)
  end

  -- Watch context signal for changes
  local unsub_context = context_signal:watch(function(entity)
    if entity then
      self:_on_context_change(entity)
    end
  end)
  table.insert(self._subscriptions, unsub_context)

  -- Watch focus changes to update pattern
  self._focus_sub = window.focus:watch(function(new_vuri)
    self:_on_focus_change(new_vuri)
  end)
  table.insert(self._subscriptions, self._focus_sub)

  -- Watch for tree rebuilds to retry pending navigation
  local unsub_rebuild = window:on_rebuild(function()
    self:_on_tree_rebuild()
  end)
  table.insert(self._subscriptions, unsub_rebuild)

  return self
end

---Compute the vuri for a context entity
---@param entity_uri string Entity URI
---@return string? vuri
function ExplorationLens:_compute_context_vuri(entity_uri)
  -- Look for entity in window items
  for _, item in ipairs(self.window._window_items) do
    if item.uri == entity_uri and item._virtual then
      return item._virtual.uri
    end
  end

  -- Not in window - compute from path to root
  local path = self.window.store:path_to_root(entity_uri, self.window.edge_types[1])
  if #path == 0 then return nil end

  -- Truncate at root
  local truncated = {}
  for i = 1, #path do
    table.insert(truncated, path[i])
    if path[i] == self.window.root_uri then
      break
    end
  end

  -- Build vuri from path (reverse: root first)
  local keys = {}
  for i = #truncated, 1, -1 do
    local entity = self.window.store:get(truncated[i])
    table.insert(keys, entity and entity.key or truncated[i])
  end

  return table.concat(keys, "/")
end

---Check if a vuri is under the current context
---@param vuri string
---@return boolean
function ExplorationLens:_is_under_context(vuri)
  if not self.context_vuri or not vuri then
    return false
  end
  -- Check if vuri equals context or starts with context/
  return vuri == self.context_vuri or
         vuri:sub(1, #self.context_vuri + 1) == self.context_vuri .. "/"
end

---Get relative path from context vuri
---@param vuri string Full vuri
---@return string? Relative path (without leading slash) or nil if not under context
function ExplorationLens:_get_relative_path(vuri)
  if not self.context_vuri then return nil end

  if vuri == self.context_vuri then
    return ""
  end

  local prefix = self.context_vuri .. "/"
  if vuri:sub(1, #prefix) == prefix then
    return vuri:sub(#prefix + 1)
  end

  return nil
end

---Handle focus changes
---@param new_vuri string? New focus vuri
function ExplorationLens:_on_focus_change(new_vuri)
  if not new_vuri then return end

  -- Only update pattern if focus is under context
  if self:_is_under_context(new_vuri) then
    local relative = self:_get_relative_path(new_vuri)
    if relative then
      self.pattern.focus = relative
    end
  end
end

---Sync pattern from current window state (captures expansion relative to context)
function ExplorationLens:_sync_pattern_from_window()
  if not self.context_vuri then return end

  -- Build expansion pattern from current window state
  self.pattern.expansion = {}

  for _, item in ipairs(self.window._window_items) do
    if item._virtual then
      local vuri = item._virtual.uri

      -- Check if under context (but not context itself)
      if self:_is_under_context(vuri) and vuri ~= self.context_vuri then
        local relative = self:_get_relative_path(vuri)
        if relative and relative ~= "" then
          local entity_uri = item.uri
          local signal = self.window.collapsed[entity_uri]
          if signal then
            -- Store expansion state (inverted from collapsed)
            self.pattern.expansion[relative] = not signal:get()
          end
        end
      end
    end
  end
end

---Handle context change
---@param new_entity table New context entity
function ExplorationLens:_on_context_change(new_entity)
  local new_entity_uri = new_entity.uri
  local old_context_vuri = self.context_vuri
  local old_context_entity_uri = self.context_entity_uri

  -- Skip if same context
  if new_entity_uri == old_context_entity_uri then
    return
  end

  -- Sync pattern from current window state before changing context
  -- This captures any expansion changes the user made
  self:_sync_pattern_from_window()

  -- Compute new context vuri (may need to wait for window rebuild)
  local new_context_vuri = self:_compute_context_vuri(new_entity_uri)

  -- BURN: Materialize pattern at old context
  if old_context_vuri then
    self:_burn_pattern(old_context_vuri)
  end

  -- Update context tracking
  self.context_entity_uri = new_entity_uri
  self.context_vuri = new_context_vuri

  -- TRANSPOSE: Apply pattern to new context
  if new_context_vuri then
    self:_apply_pattern(new_context_vuri)
  else
    -- New context not yet in window - store for retry after rebuild
    self.pending_path = self.pattern.focus and self:_split_path(self.pattern.focus) or nil
    self.pending_retries = 0
  end
end

---Burn pattern into old context (materialize state)
---@param context_vuri string Context vuri to burn into
function ExplorationLens:_burn_pattern(context_vuri)
  -- Iterate through window items under old context
  for _, item in ipairs(self.window._window_items) do
    if item._virtual then
      local vuri = item._virtual.uri

      -- Check if under old context
      if vuri == context_vuri or vuri:sub(1, #context_vuri + 1) == context_vuri .. "/" then
        -- Get relative path
        local relative
        if vuri == context_vuri then
          relative = ""
        else
          relative = vuri:sub(#context_vuri + 2)
        end

        -- Check if we have expansion state for this path
        if relative ~= "" and self.pattern.expansion[relative] ~= nil then
          local entity_uri = item.uri
          local expanded = self.pattern.expansion[relative]

          -- Get or create collapse signal and set state
          if not self.window.collapsed[entity_uri] then
            self.window.collapsed[entity_uri] = neostate.Signal(not expanded)
            self.window.collapsed[entity_uri]:set_parent(self.window)
          else
            self.window.collapsed[entity_uri]:set(not expanded)
          end
        end
      end
    end
  end
end

---Apply pattern to new context (transpose state)
---@param context_vuri string Context vuri to apply to
function ExplorationLens:_apply_pattern(context_vuri)
  -- Apply expansion state
  for relative_path, expanded in pairs(self.pattern.expansion) do
    local target_vuri = context_vuri .. "/" .. relative_path

    -- Find entity in window
    for _, item in ipairs(self.window._window_items) do
      if item._virtual and item._virtual.uri == target_vuri then
        local entity_uri = item.uri

        -- Set collapse state
        if not self.window.collapsed[entity_uri] then
          self.window.collapsed[entity_uri] = neostate.Signal(not expanded)
          self.window.collapsed[entity_uri]:set_parent(self.window)
        else
          self.window.collapsed[entity_uri]:set(not expanded)
        end
        break
      end
    end
  end

  -- Apply focus with graceful degradation
  self:_transpose_focus(context_vuri)
end

---Transpose focus to new context with graceful degradation
---@param context_vuri string New context vuri
function ExplorationLens:_transpose_focus(context_vuri)
  if not self.pattern.focus or self.pattern.focus == "" then
    -- No relative focus, focus on context itself
    self.window:focus_on(context_vuri)
    return
  end

  local parts = self:_split_path(self.pattern.focus)

  -- Try progressively shorter paths
  for i = #parts, 0, -1 do
    local target_vuri
    if i == 0 then
      target_vuri = context_vuri
    else
      local partial = table.concat(parts, "/", 1, i)
      target_vuri = context_vuri .. "/" .. partial
    end

    -- Check if this vuri exists in window
    local found = false
    for _, item in ipairs(self.window._window_items) do
      if item._virtual and item._virtual.uri == target_vuri then
        found = true
        break
      end
    end

    if found then
      self.window:focus_on(target_vuri)

      -- If we didn't get full path, store pending for async retry
      if i < #parts then
        self.pending_path = {}
        for j = i + 1, #parts do
          table.insert(self.pending_path, parts[j])
        end
        self.pending_retries = 0
      else
        self.pending_path = nil
      end

      return
    end
  end

  -- Nothing found, focus on context
  self.window:focus_on(context_vuri)
  self.pending_path = parts
  self.pending_retries = 0
end

---Handle tree rebuild (retry pending navigation)
function ExplorationLens:_on_tree_rebuild()
  if not self.pending_path or #self.pending_path == 0 then
    return
  end

  self.pending_retries = self.pending_retries + 1
  if self.pending_retries > MAX_PENDING_RETRIES then
    -- Give up
    self.pending_path = nil
    self.pending_retries = 0
    return
  end

  -- Update context vuri (might have changed after rebuild)
  if self.context_entity_uri then
    self.context_vuri = self:_compute_context_vuri(self.context_entity_uri)
  end

  if not self.context_vuri then
    return
  end

  -- Try to navigate remaining path
  local current_vuri = self.window.focus:get()
  if not current_vuri then
    current_vuri = self.context_vuri
  end

  -- Try to find next segment
  local next_segment = self.pending_path[1]
  local target_vuri = current_vuri .. "/" .. next_segment

  -- Check if target exists
  local found = false
  for _, item in ipairs(self.window._window_items) do
    if item._virtual and item._virtual.uri == target_vuri then
      found = true
      break
    end
  end

  if found then
    -- Move forward
    table.remove(self.pending_path, 1)
    self.window:focus_on(target_vuri)

    if #self.pending_path == 0 then
      -- Done!
      self.pending_path = nil
      self.pending_retries = 0
    end

    -- Trigger render if callback provided
    if self.on_render then
      vim.schedule(self.on_render)
    end
  end
  -- If not found, will retry on next rebuild
end

---Split a path into segments
---@param path string Path like "Locals/myVar/field1"
---@return string[] Segments
function ExplorationLens:_split_path(path)
  if not path or path == "" then
    return {}
  end

  local parts = {}
  for part in path:gmatch("[^/]+") do
    table.insert(parts, part)
  end
  return parts
end

---Cleanup
function ExplorationLens:dispose()
  for _, unsub in ipairs(self._subscriptions) do
    if type(unsub) == "function" then
      pcall(unsub)
    end
  end
  self._subscriptions = {}
end

---Get current pattern (for debugging/testing)
---@return { focus: string?, expansion: table<string, boolean>, context_vuri: string? }
function ExplorationLens:get_state()
  return {
    focus = self.pattern.focus,
    expansion = vim.tbl_extend("force", {}, self.pattern.expansion),
    context_vuri = self.context_vuri,
    context_entity_uri = self.context_entity_uri,
    pending_path = self.pending_path,
  }
end

return ExplorationLens
