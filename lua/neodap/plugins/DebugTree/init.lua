-- DebugTree Plugin - Simple Single-Tree Architecture
-- Each DAP entity maintains autonomous reactive nodes in one shared tree

local BasePlugin = require('neodap.plugins.BasePlugin')
local Logger = require('neodap.tools.logger')
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local NuiPopup = require("nui.popup")

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class DebugTree: BasePlugin
---@field state_tree NuiTree|nil The persistent state tree containing all DAP nodes
---@field active_view_trees NuiTree[] Active view trees that display subsets of state
local DebugTree = BasePlugin:extend()

DebugTree.name = "DebugTree"

-- ========================================
-- AUTONOMOUS NODE EXTENSIONS
-- ========================================

-- Helper function to add compatibility methods to nodes
local function addNodeCompatibilityMethods(node, state_tree)
  -- Map our node structure to NUI Tree's expected structure
  node._id = node.id
  node._is_expanded = node._expanded or false
  node._tree = state_tree  -- Store reference for depth calculation
  
  -- Rename _children to _child_ids for NUI compatibility
  if node._children then
    node._child_ids = node._children
    node._children = nil
  end
  
  -- Add compatibility methods for NUI Tree
  node.get_id = function(self)
    return self._id or self.id
  end
  
  node.has_children = function(self)
    return self._child_ids and #self._child_ids > 0
  end
  
  node.get_child_ids = function(self)
    return self._child_ids or {}
  end
  
  node.is_expanded = function(self)
    return self._is_expanded == true
  end
  
  node.expand = function(self)
    self._is_expanded = true
    if self._lazy_load and not self._children_loaded then
      -- Trigger lazy loading when expanding
      self._lazy_load()
    end
  end
  
  node.collapse = function(self)
    self._is_expanded = false
  end
  
  node.get_depth = function(self)
    -- Calculate depth by traversing up the tree
    local depth = 1
    local current_id = self._parent_id
    while current_id do
      depth = depth + 1
      local parent = self._tree and self._tree.nodes.by_id[current_id]
      if parent then
        current_id = parent._parent_id
      else
        break
      end
    end
    return depth
  end
  
  node.get_parent_id = function(self)
    return self._parent_id
  end
end

local function extendDAPEntitiesWithAsNode(plugin)
  local Session = require('neodap.api.Session.Session')
  local Thread = require('neodap.api.Session.Thread')
  local Stack = require('neodap.api.Session.Stack')
  local Frame = require('neodap.api.Session.Frame')
  local Scope = require('neodap.api.Session.Scope')
  local Variable = require('neodap.api.Session.Variable')

  -- Session.asNode() - Autonomous session node
  if not Session.asNode then
    Session.asNode = function(self)
      if self._cached_node then return self._cached_node end

      local node = NuiTree.Node({
        id = "session:" .. tostring(self.id),
        text = "📡 Session " .. tostring(self.id),
        type = "session",
        expandable = true,
        _session = self,
      })
      
      -- Add compatibility methods for our custom state tree
      addNodeCompatibilityMethods(node, plugin.state_tree)

      -- Autonomous: when threads appear, add them directly to tree
      self:onThread(function(thread)
        local thread_node = thread:asNode()
        if plugin.state_tree then
          plugin.state_tree:add_node(thread_node, node.id)
          plugin.state_tree:render() -- This will render all view trees!
        end
      end)

      -- Autonomous cleanup
      self:onTerminated(function()
        if plugin.state_tree then
          plugin.state_tree:remove_node(node.id)
          plugin.state_tree:render() -- Update all views
        end
        self._cached_node = nil
      end)

      self._cached_node = node
      return node
    end
  end

  -- Thread.asNode() - Autonomous thread node
  if not Thread.asNode then
    Thread.asNode = function(self)
      if self._cached_node then return self._cached_node end

      local function getDisplayText()
        local status_icon = self.stopped and "⏸️" or "▶️"
        local status_text = self.stopped and "stopped" or "running"
        return status_icon .. " Thread " .. tostring(self.id) .. " (" .. status_text .. ")"
      end

      local node = NuiTree.Node({
        id = "thread:" .. tostring(self.id),
        text = getDisplayText(),
        type = "thread",
        expandable = self.stopped,
        _thread = self,
      })
      
      addNodeCompatibilityMethods(node, plugin.state_tree)

      -- Autonomous: update when stopped/continued
      self:onStopped(function()
        node.text = getDisplayText()
        node.expandable = true

        -- Add stack when stopped
        local stack = self:stack()
        if stack and plugin.state_tree then
          local stack_node = stack:asNode()
          plugin.state_tree:add_node(stack_node, node.id)
          plugin.state_tree:render() -- Update all views
        end
      end)

      self:onContinued(function()
        node.text = getDisplayText()
        node.expandable = false

        -- Remove stack children when running
        if plugin.state_tree and node._child_ids then
          for _, child_id in ipairs(node._child_ids) do
            plugin.state_tree:remove_node(child_id)
          end
          node._child_ids = nil
          plugin.state_tree:render() -- Update all views
        end
      end)

      self._cached_node = node
      return node
    end
  end

  -- Stack.asNode() - Autonomous stack node
  if not Stack.asNode then
    Stack.asNode = function(self)
      if self._cached_node then return self._cached_node end

      -- Use the proper API method to get frames
      local frames = self:getFrames()
      local frame_count = frames and frames:count() or 0


      local node = NuiTree.Node({
        id = "stack:" .. tostring(self.thread.id),
        text = "📚 Stack (" .. frame_count .. " frames)",
        type = "stack",
        expandable = true,
        _stack = self,
      })
      
      addNodeCompatibilityMethods(node, plugin.state_tree)

      -- Autonomous: lazy load frames when first expanded
      node._lazy_load = function()
        if node._children_loaded then return end
        
        local frames = self:getFrames()
        if frames and plugin.state_tree then
          for frame in frames:each() do
            plugin.state_tree:add_node(frame:asNode(), node.id)
          end
          node._children_loaded = true
          plugin.state_tree:render() -- Update all views
        end
      end

      self._cached_node = node
      return node
    end
  end

  -- Frame.asNode() - Autonomous frame node
  if not Frame.asNode then
    Frame.asNode = function(self)
      if self._cached_node then return self._cached_node end

      local node = NuiTree.Node({
        id = "frame:" .. tostring(self.ref.id),
        text = "🖼️  " .. (self.ref.name or "Frame " .. tostring(self.ref.id)),
        type = "frame",
        expandable = true,
        _frame = self,
      })
      
      addNodeCompatibilityMethods(node, plugin.state_tree)

      -- Autonomous: lazy load scopes when first expanded
      node._lazy_load = function()
        if node._children_loaded then 
          plugin.logger:debug("Frame already has children loaded: " .. node.id)
          return 
        end
        
        -- Wrap in async context to call Frame:scopes()
        require('neodap.tools.async').run(function()
          plugin.logger:debug("Frame lazy load starting for: " .. node.id)
          plugin.logger:debug("Frame object: " .. vim.inspect(self))
          
          local ok, scopes = pcall(function() return self:scopes() end)
          if not ok then
            plugin.logger:error("Failed to get scopes: " .. tostring(scopes))
            return
          end
          
          plugin.logger:debug("Frame scopes result: " .. vim.inspect(scopes))
          
          if scopes and plugin.state_tree then
            plugin.logger:debug("Adding " .. #scopes .. " scopes to frame " .. node.id)
            for i, scope in ipairs(scopes) do
              local scope_node = scope:asNode()
              plugin.logger:debug("Adding scope[" .. i .. "] node: " .. scope_node.id .. " text: " .. scope_node.text)
              plugin.state_tree:add_node(scope_node, node.id)
            end
            node._children_loaded = true
            plugin.state_tree:render() -- Update all views
          else
            plugin.logger:debug("No scopes found or state_tree missing")
          end
        end)
      end

      self._cached_node = node
      return node
    end
  end

  -- Scope.asNode() - Autonomous scope node
  if not Scope.asNode then
    Scope.asNode = function(self)
      if self._cached_node then return self._cached_node end

      local scope_name = self.name or (self.ref and self.ref.name) or "Unknown"
      local scope_icon = "📁"
      if scope_name == "Local" then
        scope_icon = "📁"
      elseif scope_name == "Global" then
        scope_icon = "🌍"
      elseif scope_name == "Closure" then
        scope_icon = "🔒"
      end

      local node = NuiTree.Node({
        id = "scope:" .. tostring(self.variablesReference or self.ref.variablesReference),
        text = scope_icon .. " " .. (self.name or self.ref.name or "Unknown"),
        type = "scope",
        expandable = true,
        _scope = self,
      })
      
      addNodeCompatibilityMethods(node, plugin.state_tree)

      -- Autonomous: lazy load variables when first expanded
      node._lazy_load = function()
        if node._children_loaded then return end
        
        -- Wrap in async context to call Scope:variables()
        require('neodap.tools.async').run(function()
          plugin.logger:debug("Scope lazy load starting for: " .. node.id)
          
          local ok, variables = pcall(function() return self:variables() end)
          if not ok then
            plugin.logger:error("Failed to get variables: " .. tostring(variables))
            return
          end
          
          plugin.logger:debug("Scope variables result: " .. vim.inspect(variables))
          
          if variables and plugin.state_tree then
            plugin.logger:debug("Adding " .. #variables .. " variables to scope " .. node.id)
            for i, variable in ipairs(variables) do
              local var_node = variable:asNode()
              plugin.logger:debug("Adding variable[" .. i .. "] node: " .. var_node.id .. " text: " .. var_node.text)
              plugin.state_tree:add_node(var_node, node.id)
            end
            node._children_loaded = true
            plugin.state_tree:render() -- Update all views
          else
            plugin.logger:debug("No variables found or state_tree missing")
          end
        end)
      end

      self._cached_node = node
      return node
    end
  end

  -- Variable.asNode() - Autonomous variable node (from Variables4)
  if not Variable.asNode then
    Variable.asNode = function(self)
      if self._cached_node then return self._cached_node end

      -- Use Variables4's sophisticated variable rendering
      local icon = "📄"
      local expandable = (self.ref and self.ref.variablesReference and self.ref.variablesReference > 0)

      -- Determine icon based on type
      local value_type = type(self.ref and self.ref.value)
      if value_type == "table" then
        icon = "📋"
      elseif value_type == "function" then
        icon = "⚡"
      elseif value_type == "boolean" then
        icon = "🔘"
      elseif value_type == "number" then
        icon = "🔢"
      elseif value_type == "string" then
        icon = "📝"
      end

      local display_value = self.ref and self.ref.value or ""
      if type(display_value) == "string" and #display_value > 50 then
        display_value = string.sub(display_value, 1, 47) .. "..."
      end

      local var_name = self.name or (self.ref and self.ref.name) or "unknown"
      local var_ref = (self.ref and self.ref.variablesReference) or 0
      
      local node = NuiTree.Node({
        id = "variable:" .. var_name .. ":" .. tostring(var_ref),
        text = icon .. " " .. var_name .. ": " .. tostring(display_value),
        type = "variable",
        expandable = expandable,
        _variable = self,
      })
      
      addNodeCompatibilityMethods(node, plugin.state_tree)

      -- Autonomous: lazy load child variables when expanded
      if expandable then
        node._lazy_load = function()
          if node._children_loaded then return end
          
          -- Wrap in async context to call Variable:variables()
          require('neodap.tools.async').run(function()
            plugin.logger:debug("Variable lazy load starting for: " .. node.id)
            
            local ok, children = pcall(function() return self:variables() end)
            if not ok then
              plugin.logger:error("Failed to get child variables: " .. tostring(children))
              return
            end
            
            plugin.logger:debug("Variable children result: " .. vim.inspect(children))
            
            if children and plugin.state_tree then
              plugin.logger:debug("Adding " .. #children .. " child variables to " .. node.id)
              for i, child in ipairs(children) do
                local child_node = child:asNode()
                plugin.logger:debug("Adding child[" .. i .. "] node: " .. child_node.id .. " text: " .. child_node.text)
                plugin.state_tree:add_node(child_node, node.id)
              end
              node._children_loaded = true
              plugin.state_tree:render() -- Update all views
            else
              plugin.logger:debug("No child variables found or state_tree missing")
            end
          end)
        end
      end

      self._cached_node = node
      return node
    end
  end
end

function DebugTree.plugin(api)
  return BasePlugin.createPlugin(api, DebugTree)
end

function DebugTree:listen()
  self.logger:info("Initializing DebugTree plugin - shared-node reactive architecture")

  -- Initialize instance properties
  self.active_view_trees = {}
  
  -- Extend all DAP entities with asNode methods, passing plugin instance
  extendDAPEntitiesWithAsNode(self)

  -- Setup session event handlers to initialize reactive nodes
  self:setupSessionHandlers()

  -- Setup commands
  self:setupCommands()

  self.logger:info("DebugTree plugin initialized")
end

-- ========================================
-- SESSION EVENT HANDLERS
-- ========================================

function DebugTree:setupSessionHandlers()
  -- Initialize the persistent state tree
  self:initializeStateTree()

  -- Register for new sessions to add them to the state tree
  self.api:onSession(function(session)
    -- Initialize the session node and add it to the persistent state tree
    local session_node = session:asNode()
    self.state_tree:add_node(session_node)

    -- Add any existing threads to the state tree
    self:addExistingChildren(session)

    self.logger:debug("Added session " .. session.id .. " to persistent state tree")
    
    -- Render all views to show new session
    self.state_tree:render()
  end)
end

function DebugTree:initializeStateTree()
  if self.state_tree then return end -- Already initialized

  local plugin_instance = self -- Capture reference to plugin
  
  -- Create state tree without NUI Tree - just use plain node storage
  -- NUI Tree requires a bufnr, so we'll use a custom data structure
  self.state_tree = {
    nodes = {
      by_id = {},
      root_ids = {},
    },
    add_node = function(state_tree, node, parent_id)
      -- Store the node
      state_tree.nodes.by_id[node.id] = node
      
      plugin_instance.logger:debug("add_node: Adding " .. node.id .. " with parent: " .. (parent_id or "none"))
      
      if parent_id then
        -- Add as child to parent
        local parent = state_tree.nodes.by_id[parent_id]
        if parent then
          if not parent._child_ids then
            parent._child_ids = {}
          end
          table.insert(parent._child_ids, node.id)
          -- CRITICAL: Store parent relationship in the state tree node
          state_tree.nodes.by_id[node.id]._parent_id = parent_id
          plugin_instance.logger:debug("add_node: Set parent relationship " .. node.id .. " -> " .. parent_id)
        else
          plugin_instance.logger:debug("add_node: Parent " .. parent_id .. " not found, adding as root")
          table.insert(state_tree.nodes.root_ids, node.id)
        end
      else
        -- Add as root node
        table.insert(state_tree.nodes.root_ids, node.id)
        plugin_instance.logger:debug("add_node: Added " .. node.id .. " as root node")
      end
    end,
    remove_node = function(state_tree, node_id)
      local node = state_tree.nodes.by_id[node_id]
      if not node then return end
      
      -- Remove from parent's children or root list
      if node._parent_id then
        local parent = state_tree.nodes.by_id[node._parent_id]
        if parent and parent._child_ids then
          for i, child_id in ipairs(parent._child_ids) do
            if child_id == node_id then
              table.remove(parent._children, i)
              break
            end
          end
        end
      else
        -- Remove from root list
        for i, root_id in ipairs(state_tree.nodes.root_ids) do
          if root_id == node_id then
            table.remove(state_tree.nodes.root_ids, i)
            break
          end
        end
      end
      
      -- Remove the node and all descendants
      local function removeDescendants(id)
        local n = state_tree.nodes.by_id[id]
        if n and n._child_ids then
          for _, child_id in ipairs(n._child_ids) do
            removeDescendants(child_id)
          end
        end
        state_tree.nodes.by_id[id] = nil
      end
      removeDescendants(node_id)
    end,
    render = function(state_tree)
      -- State tree render -> render all active view trees
      for _, view_tree in ipairs(plugin_instance.active_view_trees) do
        if view_tree.bufnr and vim.api.nvim_buf_is_valid(view_tree.bufnr) then
          -- Restore the view's specific root_ids before rendering
          view_tree.nodes.root_ids = view_tree._view_root_ids
          
          -- View trees already share the nodes structure, just render!
          view_tree:render()
        end
      end
    end
  }

  -- Add all existing sessions to the state tree
  for session in self.api:eachSession() do
    local session_node = session:asNode()
    self.state_tree:add_node(session_node)
    self:addExistingChildren(session)
  end

end

-- ========================================
-- SIMPLE TREE COMMANDS
-- ========================================

function DebugTree:setupCommands()
  -- Main DebugTree command - shows full session hierarchy
  vim.api.nvim_create_user_command('DebugTree', function()
    self:openDebugTree()
  end, { desc = 'Open full debug session tree' })

  -- Frame-level tree (equivalent to Variables4)
  vim.api.nvim_create_user_command('DebugTreeFrame', function()
    self:openFrameTree()
  end, { desc = 'Open current frame variables tree' })

  -- Stack-level tree
  vim.api.nvim_create_user_command('DebugTreeStack', function()
    self:openStackTree()
  end, { desc = 'Open current thread stack tree' })
end

function DebugTree:openDebugTree()
  -- Create a view tree that shows the complete state tree
  self:createViewTree(nil, "Debug Tree - All Sessions")
end

function DebugTree:openFrameTree()
  local session = self:getCurrentSession()
  if not session then
    vim.notify("No active debug session", vim.log.levels.WARN)
    return
  end

  -- Find current frame
  local current_frame = nil
  for thread in session.threads:each() do
    if thread.stopped then
      local stack = thread:stack()
      if stack then
        local frames = stack:getFrames()
        if frames and #frames > 0 then
          current_frame = frames[1] -- Top frame
          break
        end
      end
    end
  end

  if not current_frame then
    vim.notify("No current frame available", vim.log.levels.WARN)
    return
  end

  self:createViewTree(current_frame, "Debug Tree - Frame Variables")
end

function DebugTree:openStackTree()
  local session = self:getCurrentSession()
  if not session then
    vim.notify("No active debug session", vim.log.levels.WARN)
    return
  end

  -- Find current stack
  local current_stack = nil
  for thread in session.threads:each() do
    if thread.stopped then
      current_stack = thread:stack()
      break
    end
  end

  if not current_stack then
    vim.notify("No current stack available", vim.log.levels.WARN)
    return
  end

  self:createViewTree(current_stack, "Debug Tree - Stack Frames")
end

-- ========================================
-- VIEW TREE CREATION (References State Tree)
-- ========================================

function DebugTree:createViewTree(root_entity, title)
  if not self.state_tree then
    vim.notify("State tree not initialized", vim.log.levels.WARN)
    return
  end

  -- Create popup window
  local popup = NuiPopup({
    enter = true, -- CRITICAL: Focus the popup so keymaps work
    focusable = true,
    position = "50%",
    size = {
      width = "80%",
      height = "70%",
    },
    border = {
      style = "rounded",
      text = {
        top = " " .. title .. " ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  -- Mount popup
  popup:mount()

  -- Debug logging
  self.logger:debug("State tree has " .. vim.tbl_count(self.state_tree.nodes.by_id) .. " nodes")
  self.logger:debug("State tree root_ids: " .. vim.inspect(self.state_tree.nodes.root_ids))
  
  -- Create view tree with initial empty nodes
  local view_tree = NuiTree({
    bufnr = popup.bufnr,
    nodes = {},  -- Start with empty nodes
    get_node_id = function(node) return node.id end,
  })
  
  -- Share the state tree's nodes structure
  view_tree.nodes = self.state_tree.nodes
  
  -- Store the original root_ids for this view
  if root_entity then
    -- Single entity view - show only this entity's subtree
    local root_node = root_entity:asNode()
    view_tree._view_root_ids = { root_node.id }
  else
    -- Full view - show all sessions
    view_tree._view_root_ids = {}
    for _, id in ipairs(self.state_tree.nodes.root_ids) do
      if id:match("^session:") then
        table.insert(view_tree._view_root_ids, id)
      end
    end
  end
  
  -- Set the view's root_ids
  self.logger:debug("View tree root_ids: " .. vim.inspect(view_tree._view_root_ids))
  view_tree.nodes.root_ids = view_tree._view_root_ids
  
  -- Store reference for dynamic updates
  view_tree._debug_tree_root_entity = root_entity
  view_tree._debug_tree_instance = self

  -- Track this view tree for reactive updates
  table.insert(self.active_view_trees, view_tree)

  -- Setup custom rendering with expand/collapse indicators
  self:setupTreeRendering(view_tree)

  -- Initial render
  view_tree:render()

  -- Setup keybindings
  popup:map("n", "<CR>", function()
    local node = view_tree:get_node()
    if node then
      -- Debug logging
      self.logger:debug("Key pressed on node: " .. (node.id or "nil") .. " type: " .. (node.type or "nil"))
      self.logger:debug("Node has _lazy_load: " .. tostring(node._lazy_load ~= nil))
      self.logger:debug("Node _children_loaded: " .. tostring(node._children_loaded))
      self.logger:debug("Node has_children: " .. tostring(node:has_children()))
      
      -- For all expandable nodes, just toggle expansion
      -- The expand() method will handle lazy loading if needed
      if node:has_children() or node.expandable or node._lazy_load then
        self.logger:debug("Toggling expansion for node: " .. node.id .. " (expandable: " .. tostring(node.expandable) .. ", has_lazy_load: " .. tostring(node._lazy_load ~= nil) .. ")")
        -- Toggle expansion
        if node:is_expanded() then
          node:collapse()
        else
          node:expand()
        end
        view_tree:render()
      else
        self.logger:debug("Node has no children and not expandable: " .. node.id)
      end
    else
      self.logger:debug("No node found at cursor position")
    end
  end)

  popup:map("n", "q", function()
    -- Remove from active view trees
    for i, vt in ipairs(self.active_view_trees) do
      if vt == view_tree then
        table.remove(self.active_view_trees, i)
        break
      end
    end
    popup:unmount()
  end)

  popup:map("n", "?", function()
    vim.notify("DebugTree Help:\n<CR> - Expand/Collapse\nq - Quit\n? - This help", vim.log.levels.INFO)
  end)
end


-- ========================================
-- VIEW TREE HELPERS
-- ========================================

function DebugTree:collectSubtreeNodes(nodes_array, root_node)
  -- Add the root node to the array
  table.insert(nodes_array, root_node)
  self.logger:debug("collectSubtreeNodes: Added root node " .. root_node.id)
  
  -- Recursively collect all descendants
  local function collectDescendants(node)
    if node:has_children() then
      local child_ids = node:get_child_ids()
      self.logger:debug("collectSubtreeNodes: Node " .. node.id .. " has " .. #child_ids .. " children")
      for _, child_id in ipairs(child_ids) do
        local child = self.state_tree.nodes.by_id[child_id]
        if child then
          table.insert(nodes_array, child)
          self.logger:debug("collectSubtreeNodes: Added child node " .. child.id .. " (type: " .. (child.type or "nil") .. ")")
          collectDescendants(child)
        else
          self.logger:debug("collectSubtreeNodes: Child " .. child_id .. " not found in state tree")
        end
      end
    else
      self.logger:debug("collectSubtreeNodes: Node " .. node.id .. " has no children")
    end
  end
  
  collectDescendants(root_node)
  self.logger:debug("collectSubtreeNodes: Total collected nodes: " .. #nodes_array)
end

function DebugTree:setupTreeRendering(tree)
  local NuiLine = require("nui.line")

  -- Helper function to calculate node depth
  local function getNodeDepth(node_id)
    local depth = 0
    local current_id = node_id
    while current_id do
      local node = tree.nodes.by_id[current_id]
      if not node or not node._parent_id then
        break
      end
      depth = depth + 1
      current_id = node._parent_id
    end
    return depth
  end

  tree._.prepare_node = function(node)
    local line = NuiLine()

    -- Calculate relative indentation for viewport
    local min_depth = math.huge
    for _, root_id in ipairs(tree.nodes.root_ids) do
      local root_node = tree.nodes.by_id[root_id]
      if root_node then
        local depth = getNodeDepth(root_id)
        min_depth = math.min(min_depth, depth)
      end
    end
    if min_depth == math.huge then
      min_depth = 0
    end
    
    local node_depth = getNodeDepth(node.id)
    local relative_depth = math.max(0, node_depth - min_depth)

    -- Add UTF-8 indent indicators
    for i = 1, relative_depth do
      if i == relative_depth then
        line:append("╰─ ", "Comment")
      else
        line:append("│  ", "Comment")
      end
    end

    -- Add expand/collapse indicator
    local has_children = node._children and #node._children > 0
    if has_children or node.expandable then
      if node:is_expanded() then
        line:append("▼ ", "Comment")
      else
        line:append("▶ ", "Comment")
      end
    else
      line:append("  ")
    end

    -- Add content
    local text = node.text or ""
    line:append(text)

    return line
  end
end

-- ========================================
-- TREE INITIALIZATION HELPERS
-- ========================================

function DebugTree:addExistingChildren(root_entity)
  -- Handle different entity types to add their existing children
  if root_entity.threads then
    -- Session: add existing threads
    for thread in root_entity.threads:each() do
      local thread_node = thread:asNode()
      self.state_tree:add_node(thread_node, "session:" .. tostring(root_entity.id))

      -- If thread is stopped, also add its stack
      if thread.stopped then
        local stack = thread:stack()
        if stack then
          local stack_node = stack:asNode()
          self.state_tree:add_node(stack_node, "thread:" .. tostring(thread.id))
        end
      end
    end
  elseif root_entity.frames then
    -- Stack: add existing frames
    for _, frame in ipairs(root_entity.frames) do
      local frame_node = frame:asNode()
      self.state_tree:add_node(frame_node, "stack:" .. tostring(root_entity.thread.id))
    end
  end
  -- Frame and deeper levels use lazy loading, so no need to pre-populate
end

-- ========================================
-- HELPER METHODS
-- ========================================

function DebugTree:getCurrentSession()

  -- Simple session detection
  for session in self.api:eachSession() do
    for thread in session.threads:each() do
      if thread.stopped then
        return session
      end
    end
  end

  -- Fallback to most recent session
  local latest_session = nil
  for session in self.api:eachSession() do
    if not latest_session or session.id > latest_session.id then
      latest_session = session
    end
  end

  return latest_session
end

return DebugTree
