-- Variables2 Plugin - Unified Node Architecture
-- Main plugin that orchestrates the tree manager and UI manager

local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')

local ApiExtensions = require('neodap.plugins.Variables2.api_extensions')
local TreeManager = require('neodap.plugins.Variables2.tree_manager')
local UIManager = require('neodap.plugins.Variables2.ui_manager')

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class Variables2PluginProps
---@field api Api
---@field tree_manager TreeManager
---@field ui_manager UIManager
---@field current_frame? Frame
---@field logger Logger



---@class Variables2Plugin: Variables2PluginProps
---@field new Constructor<Variables2PluginProps>
local Variables2Plugin = Class()

Variables2Plugin.name = "Variables2"

-- ========================================
-- PLUGIN INITIALIZATION
-- ========================================

function Variables2Plugin.plugin(api)
  local extensions = ApiExtensions.initializeApiExtensions()
  -- self.logger:info("API extensions loaded - Variables and Scopes are now NuiTree.Nodes")

  local instance = Variables2Plugin:new({
    api = api,
    logger = Logger.get("Variables2"),
    ui_manager = UIManager.new(),
    tree_manager = TreeManager.new(),
    current_frame = nil, -- No frame initially
  })

  instance:initialize()

  return instance
end

function Variables2Plugin:initialize()
  self.logger:info("Initializing Variables2 plugin with unified node architecture")

  -- Set up DAP event handlers
  self:setupEventHandlers()

  -- Create user commands
  self:setupCommands()

  self.logger:info("Variables2 plugin initialized successfully")
end

-- ========================================
-- EVENT HANDLERS
-- ========================================

function Variables2Plugin:setupEventHandlers()
  -- Listen for session events
  self.api:onSession(function(session)
    self.logger:debug("New debug session started")

    -- Listen for thread events in this session
    session:onThread(function(thread)
      self.logger:debug("New thread in session")

      -- Listen for stop events on this thread
      thread:onStopped(function(stopped_event)
        self.logger:debug("Thread stopped, updating current frame")
        local stack = thread:stack()

        if not stack then return end

        local top = stack:top()
        self:UpdateCurrentFrame(top)
      end)

      -- Listen for continue events
      thread:onContinued(function()
        self.logger:debug("Thread continued, clearing current frame")
        self:ClearCurrentFrame()
      end)
    end)

    -- Listen for session termination
    session:onTerminated(function()
      self.logger:debug("Debug session terminated")
      self:ClearCurrentFrame()
    end)
  end)
end

-- ========================================
-- FRAME MANAGEMENT (Async Methods)
-- ========================================

-- Update the current frame and refresh UI
function Variables2Plugin:UpdateCurrentFrame(frame)
  self.current_frame = frame
  self.logger:debug("Updated current frame")

  -- Refresh the UI if window is open
  if self.ui_manager:isWindowOpen() then
    self:RefreshVariablesTree()
  end
end

-- Clear the current frame
function Variables2Plugin:ClearCurrentFrame()
  self.current_frame = nil
  self.logger:debug("Cleared current frame")

  -- Clear the tree
  if self.ui_manager:isWindowOpen() then
    self.ui_manager:updateTree({})
  end
end

-- Refresh the variables tree from current frame
function Variables2Plugin:RefreshVariablesTree()
  if not self.current_frame then
    self.logger:debug("No current frame to refresh from")
    self.ui_manager:updateTree({})
    return
  end

  self.logger:debug("Refreshing variables tree")

  -- Build tree using enhanced API objects (they're already nodes!)
  local tree_nodes = self.tree_manager:buildTree(self.current_frame)

  -- Update UI directly - no conversion needed!
  self.ui_manager:updateTree(tree_nodes)

  self.logger:debug("Variables tree refreshed with " .. #tree_nodes .. " nodes")
end

-- ========================================
-- USER COMMANDS
-- ========================================

function Variables2Plugin:setupCommands()
  -- Main commands
  vim.api.nvim_create_user_command("Variables2Show", function()
    self:ShowWindow()
  end, { desc = "Show Variables2 window" })

  vim.api.nvim_create_user_command("Variables2Hide", function()
    self:HideWindow()
  end, { desc = "Hide Variables2 window" })

  vim.api.nvim_create_user_command("Variables2Toggle", function()
    self:ToggleWindow()
  end, { desc = "Toggle Variables2 window" })

  vim.api.nvim_create_user_command("Variables2Refresh", function()
    self:RefreshVariablesTree()
  end, { desc = "Refresh Variables2 tree" })

  -- Debug commands
  vim.api.nvim_create_user_command("Variables2Status", function()
    self:ShowStatus()
  end, { desc = "Show Variables2 status" })

  vim.api.nvim_create_user_command("Variables2Cache", function()
    self:ShowCacheStats()
  end, { desc = "Show Variables2 cache statistics" })

  self.logger:debug("User commands registered")
end

-- ========================================
-- PUBLIC API METHODS (Async)
-- ========================================

-- Show the variables window
function Variables2Plugin:ShowWindow()
  self.ui_manager:showWindow()

  -- If we have a current frame, populate the tree
  if self.current_frame then
    self:RefreshVariablesTree()
  end
end

-- Hide the variables window
function Variables2Plugin:HideWindow()
  self.ui_manager:hideWindow()
end

-- Toggle window visibility
function Variables2Plugin:ToggleWindow()
  self.ui_manager:toggleWindow()

  -- If we just showed the window and have a frame, populate it
  if self.ui_manager:isWindowOpen() and self.current_frame then
    self:RefreshVariablesTree()
  end
end

-- Focus the variables window
function Variables2Plugin:FocusWindow()
  if not self.ui_manager:isWindowOpen() then
    self:ShowWindow()
  else
    self.ui_manager:focusWindow()
  end
end

-- ========================================
-- DEBUG AND STATUS METHODS
-- ========================================

-- Show plugin status
function Variables2Plugin:ShowStatus()
  local status = {
    "Variables2 Plugin Status:",
    "========================",
    "",
    "Current frame: " .. (self.current_frame and "Yes" or "No"),
    "Window open: " .. (self.ui_manager:isWindowOpen() and "Yes" or "No"),
    "Active tree: " .. (self.ui_manager:getActiveTree() and "Yes" or "No"),
    "",
  }

  -- Add frame info if available
  if self.current_frame then
    local scopes = self.current_frame:scopes()
    table.insert(status, "Scopes available: " .. #scopes)

    for _, scope in ipairs(scopes) do
      table.insert(status, "  - " .. scope.ref.name)
    end
  end

  -- Print status
  for _, line in ipairs(status) do
    print(line)
  end
end

-- Show cache statistics
function Variables2Plugin:ShowCacheStats()
  local stats = self.tree_manager:getCacheStats()

  print("Variables2 Cache Statistics:")
  print("===========================")
  print("Total cached nodes: " .. stats.total_cached_nodes)
  print("Expanded nodes: " .. stats.expanded_nodes)
  print("Cache size: " .. stats.cache_size)
end

-- Clear all caches
function Variables2Plugin:ClearCaches()
  self.tree_manager:clearCache()
  self.logger:info("Cleared all caches")
end

-- ========================================
-- DEMONSTRATION METHODS
-- ========================================

-- Demonstrate the unified node architecture
function Variables2Plugin:DemonstrateUnifiedNodes()
  if not self.current_frame then
    print("No debug session active - start debugging to see unified nodes")
    return
  end

  print("Variables2: Demonstrating Unified Node Architecture")
  print("=================================================")

  -- Get scopes - they're already NuiTree.Nodes!
  local scopes = self.current_frame:scopes()

  for _, scope in ipairs(scopes) do
    print("\nScope: " .. scope.ref.name)
    print("  Node ID: " .. scope:get_id())                            -- NuiTree.Node method
    print("  Display: " .. scope:formatTreeNodeDisplay())             -- Our extension
    print("  Expandable: " .. tostring(scope:isTreeNodeExpandable())) -- Our extension

    -- Get variables - they're also NuiTree.Nodes!
    local variables = scope:GetTreeNodeChildren() -- Async method

    if variables then
      for i, variable in ipairs(variables) do
        if i > 3 then break end -- Limit output

        print("  Variable: " .. variable.ref.name)
        print("    Node ID: " .. variable:get_id())                            -- NuiTree.Node method
        print("    Display: " .. variable:formatTreeNodeDisplay())             -- Our extension
        print("    Can expand: " .. tostring(variable:is_expandable()))        -- NuiTree.Node method
        print("    Expandable: " .. tostring(variable:isTreeNodeExpandable())) -- Our extension
      end
    end
  end

  print("\n✓ All objects are both API objects AND NuiTree.Nodes!")
  print("✓ Zero conversion overhead - direct tree usage!")
  print("✓ Unified interface - one object, two behaviors!")
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return Variables2Plugin
