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
-- VARIABLE PRESENTATION CONFIGURATION
-- ========================================

-- Rich type icons and formatting borrowed from Variables4
local VariablePresentation = {
  styles = {
    -- JavaScript primitives
    string = { icon = "󰉿", highlight = "String", truncate = 35 },
    number = { icon = "󰎠", highlight = "Number", truncate = 40 },
    boolean = { icon = "◐", highlight = "Boolean", truncate = 40 },
    undefined = { icon = "󰟢", highlight = "Constant", truncate = 40 },
    ['nil'] = { icon = "∅", highlight = "Constant", truncate = 40 },
    null = { icon = "∅", highlight = "Constant", truncate = 40 },
    
    -- Complex types
    object = { icon = "󰅩", highlight = "Structure", truncate = 40 },
    array = { icon = "󰅪", highlight = "Structure", truncate = 40 },
    ['function'] = { icon = "󰊕", highlight = "Function", truncate = 25 },
    
    -- Special types
    date = { icon = "󰃭", highlight = "Special", truncate = 40 },
    regexp = { icon = "󰑑", highlight = "String", truncate = 40 },
    map = { icon = "󰘣", highlight = "Type", truncate = 40 },
    set = { icon = "󰘦", highlight = "Type", truncate = 40 },
    
    -- Default fallback
    default = { icon = "󰀬", highlight = "Identifier", truncate = 40 },
  }
}

-- Get presentation style for a variable type
local function getVariableStyle(var_type)
  if not var_type then return VariablePresentation.styles.default end
  return VariablePresentation.styles[var_type:lower()] or VariablePresentation.styles.default
end

-- Detect if a value is an array by checking its string representation
local function isArray(ref)
  return ref and ref.type and ref.type:lower() == "object" and 
         ref.value and ref.value:match("^%[.*%]$")
end

-- Format variable value with smart truncation and type-specific handling
local function formatVariableValue(ref, style)
  if not ref then return "undefined" end
  
  local value = ref.value or ""
  local var_type = ref.type and ref.type:lower() or "default"
  
  -- Handle multiline values by inlining
  if type(value) == "string" then
    value = value:gsub("[\r\n]+", " "):gsub("\\[nrt]", " "):gsub("%s+", " ")
    value = value:match("^%s*(.-)%s*$") or ""
    
    -- Smart truncation
    if #value > style.truncate then
      value = value:sub(1, style.truncate - 3) .. "..."
    end
  end
  
  -- Type-specific formatting
  if var_type == "string" then
    return string.format('"%s"', value)
  elseif var_type == "function" then
    -- Extract function signature
    if type(value) == "string" and value:match("^function") then
      local signature = value:match("^function%s*([^{]*)")
      if signature then
        return "ƒ " .. signature:gsub("%s+", " "):sub(1, 20) .. (signature:len() > 20 and "..." or "")
      end
    elseif type(value) == "string" and value:match("^ƒ") then
      -- Already formatted function
      return value
    end
    return "ƒ (...)"
  elseif var_type == "object" and ref.variablesReference and ref.variablesReference > 0 then
    -- Check for array presentation
    if isArray(ref) then
      -- Extract array length if available
      local length = value:match("^%((%d+)%)") or value:match("^Array%((%d+)%)")
      if length then
        return "(" .. length .. ") [...]"
      end
      return "[...]"
    end
    -- Object with children
    return value:match("^%{.*%}$") and value or ("{...}")
  end
  
  return tostring(value)
end

-- ========================================
-- AUTONOMOUS NODE EXTENSIONS
-- ========================================

-- Forward declarations for DAP classes
local Session = require('neodap.api.Session.Session')
local Thread = require('neodap.api.Session.Thread')
local Stack = require('neodap.api.Session.Stack')
local Frame = require('neodap.api.Session.Frame')
local Scope = require('neodap.api.Session.Scope')
local Variable = require('neodap.api.Session.Variable')

---@class (partial) api.Session
---@field asNode fun(self: api.Session): NuiTree.Node Create a tree node for this session
---@field _cached_node NuiTree.Node|nil Cached tree node

---@class (partial) api.Thread  
---@field asNode fun(self: api.Thread): NuiTree.Node Create a tree node for this thread
---@field _cached_node NuiTree.Node|nil Cached tree node

---@class (partial) api.Stack
---@field asNode fun(self: api.Stack): NuiTree.Node Create a tree node for this stack
---@field _cached_node NuiTree.Node|nil Cached tree node

---@class (partial) api.Frame
---@field asNode fun(self: api.Frame): NuiTree.Node Create a tree node for this frame
---@field _cached_node NuiTree.Node|nil Cached tree node

---@class (partial) api.Scope
---@field asNode fun(self: api.Scope): NuiTree.Node Create a tree node for this scope
---@field _cached_node NuiTree.Node|nil Cached tree node

---@class (partial) api.Variable
---@field asNode fun(self: api.Variable): NuiTree.Node Create a tree node for this variable
---@field _cached_node NuiTree.Node|nil Cached tree node

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

-- Store plugin instance for asNode methods
local plugin_instance = nil

-- ========================================
-- SESSION NODE
-- ========================================

---@param self api.Session
---@return NuiTree.Node
function Session:asNode()
  if self._cached_node then return self._cached_node end

  local node = NuiTree.Node({
    id = "session:" .. tostring(self.id),
    text = "📡 Session " .. tostring(self.id),
    type = "session",
    expandable = true,
    _session = self,
  })
  
  -- Add compatibility methods for our custom state tree
  addNodeCompatibilityMethods(node, plugin_instance.state_tree)

  -- Autonomous: when threads appear, add them directly to tree
  self:onThread(function(thread)
    local thread_node = thread:asNode()
    if plugin_instance.state_tree then
      plugin_instance.state_tree:add_node(thread_node, node.id)
      plugin_instance.state_tree:render() -- This will render all view trees!
    end
  end)

  -- Autonomous cleanup
  self:onTerminated(function()
    if plugin_instance.state_tree then
      plugin_instance.state_tree:remove_node(node.id)
      plugin_instance.state_tree:render() -- Update all views
    end
    self._cached_node = nil
  end)

  self._cached_node = node
  return node
end

-- ========================================
-- THREAD NODE
-- ========================================

---@param self api.Thread
---@return NuiTree.Node
function Thread:asNode()
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
  
  addNodeCompatibilityMethods(node, plugin_instance.state_tree)

  -- Autonomous: update when stopped/continued
  self:onStopped(function()
    node.text = getDisplayText()
    node.expandable = true

    -- Add stack when stopped
    local stack = self:stack()
    if stack and plugin_instance.state_tree then
      local stack_node = stack:asNode()
      plugin_instance.state_tree:add_node(stack_node, node.id)
      plugin_instance.state_tree:render() -- Update all views
    end
  end)

  self:onContinued(function()
    node.text = getDisplayText()
    node.expandable = false

    -- Remove stack children when running
    if plugin_instance.state_tree and node._child_ids then
      for _, child_id in ipairs(node._child_ids) do
        plugin_instance.state_tree:remove_node(child_id)
      end
      node._child_ids = nil
      plugin_instance.state_tree:render() -- Update all views
    end
  end)

  self._cached_node = node
  return node
end

-- ========================================
-- STACK NODE
-- ========================================

---@param self api.Stack
---@return NuiTree.Node
function Stack:asNode()
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
  
  addNodeCompatibilityMethods(node, plugin_instance.state_tree)

  -- Autonomous: lazy load frames when first expanded
  node._lazy_load = function()
    if node._children_loaded then return end
    
    local frames = self:getFrames()
    if frames and plugin_instance.state_tree then
      local index = 0
      for frame in frames:each() do
        index = index + 1
        -- Pass the index to frame:asNode
        local frame_node = frame:asNode(index)
        plugin_instance.state_tree:add_node(frame_node, node.id)
      end
      node._children_loaded = true
      plugin_instance.state_tree:render() -- Update all views
    end
  end

  self._cached_node = node
  return node
end

-- ========================================
-- FRAME NODE
-- ========================================

---@param self api.Frame
---@param index? number The frame's position in the stack (1-based)
---@return NuiTree.Node
function Frame:asNode(index)
  -- For frames with index, we need unique nodes per position
  local cache_key = index and ("_cached_node_" .. index) or "_cached_node"
  if self[cache_key] then return self[cache_key] end

  -- Clean up frame name to remove newlines and control characters
  local frame_name = self.ref.name or "Frame " .. tostring(self.ref.id)
  -- Replace newlines and tabs with spaces, trim whitespace
  frame_name = frame_name:gsub("[\n\r\t]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  
  -- Include index in ID to make frames unique even if same function appears multiple times
  local frame_id = index and ("frame:" .. tostring(self.ref.id) .. ":" .. index) or ("frame:" .. tostring(self.ref.id))
  
  -- Add frame number prefix if index is provided
  local display_text = index and ("#" .. index .. " 🖼️  " .. frame_name) or ("🖼️  " .. frame_name)
  
  local node = NuiTree.Node({
    id = frame_id,
    text = display_text,
    type = "frame",
    expandable = true,
    _frame = self,
    _frame_index = index,
  })
  
  addNodeCompatibilityMethods(node, plugin_instance.state_tree)

      -- Autonomous: lazy load scopes when first expanded
      node._lazy_load = function()
        if node._children_loaded then 
          plugin_instance.logger:debug("Frame already has children loaded: " .. node.id)
          return 
        end
        
        -- Wrap in async context to call Frame:scopes()
        require('neodap.tools.async').run(function()
          plugin_instance.logger:debug("Frame lazy load starting for: " .. node.id)
          plugin_instance.logger:debug("Frame object: " .. vim.inspect(self))
          
          local ok, scopes = pcall(function() return self:scopes() end)
          if not ok then
            plugin_instance.logger:error("Failed to get scopes: " .. tostring(scopes))
            return
          end
          
          plugin_instance.logger:debug("Frame scopes result: " .. vim.inspect(scopes))
          
          if scopes and plugin_instance.state_tree then
            plugin_instance.logger:debug("Adding " .. #scopes .. " scopes to frame " .. node.id)
            for i, scope in ipairs(scopes) do
              local scope_node = scope:asNode()
              plugin_instance.logger:debug("Adding scope[" .. i .. "] node: " .. scope_node.id .. " text: " .. scope_node.text)
              plugin_instance.state_tree:add_node(scope_node, node.id)
            end
            node._children_loaded = true
            plugin_instance.state_tree:render() -- Update all views
          else
            plugin_instance.logger:debug("No scopes found or state_tree missing")
          end
        end)
      end

  self[cache_key] = node
  return node
end

-- ========================================
-- SCOPE NODE
-- ========================================

---@param self api.Scope
---@return NuiTree.Node
function Scope:asNode()
  if self._cached_node then return self._cached_node end

  local scope_name = self.name or (self.ref and self.ref.name) or "Unknown"
  -- Clean scope name of newlines
  scope_name = scope_name:gsub("[\n\r\t]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  
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
    text = scope_icon .. " " .. scope_name,
    type = "scope",
    expandable = true,
    _scope = self,
  })
  
  addNodeCompatibilityMethods(node, plugin_instance.state_tree)

      -- Autonomous: lazy load variables when first expanded
      node._lazy_load = function()
        if node._children_loaded then return end
        
        -- Wrap in async context to call Scope:variables()
        require('neodap.tools.async').run(function()
          plugin_instance.logger:debug("Scope lazy load starting for: " .. node.id)
          
          local ok, variables = pcall(function() return self:variables() end)
          if not ok then
            plugin_instance.logger:error("Failed to get variables: " .. tostring(variables))
            return
          end
          
          plugin_instance.logger:debug("Scope variables result: " .. vim.inspect(variables))
          
          if variables and plugin_instance.state_tree then
            plugin_instance.logger:debug("Adding " .. #variables .. " variables to scope " .. node.id)
            for i, variable in ipairs(variables) do
              local var_node = variable:asNode()
              plugin_instance.logger:debug("Adding variable[" .. i .. "] node: " .. var_node.id .. " text: " .. var_node.text)
              plugin_instance.state_tree:add_node(var_node, node.id)
            end
            node._children_loaded = true
            plugin_instance.state_tree:render() -- Update all views
          else
            plugin_instance.logger:debug("No variables found or state_tree missing")
          end
        end)
      end

  self._cached_node = node
  return node
end

-- ========================================
-- VARIABLE NODE
-- ========================================

---@param self api.Variable
---@return NuiTree.Node
function Variable:asNode()
  if self._cached_node then return self._cached_node end

  -- Get variable type and style
  local var_type = (self.ref and self.ref.type) and self.ref.type:lower() or "default"
  local style = getVariableStyle(var_type)
  
  -- Check for array vs object
  if isArray(self.ref) then
    style = getVariableStyle("array")
  end
  
  -- Check for lazy variables
  local is_lazy = self.ref and self.ref.presentationHint and self.ref.presentationHint.lazy
  
  -- Format the value using sophisticated formatting
  local formatted_value = formatVariableValue(self.ref, style)
  
  -- Clean variable name
  local var_name = self.name or (self.ref and self.ref.name) or "unknown"
  var_name = tostring(var_name):gsub("[\n\r\t]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  
  -- Build node text with icon
  local icon = is_lazy and "⏳" or style.icon  -- Show loading icon for lazy vars
  local text = icon .. " " .. var_name .. ": " .. formatted_value
  text = text:gsub("[\n\r]+", " ")  -- Final safety check
  
  local var_ref = (self.ref and self.ref.variablesReference) or 0
  local expandable = var_ref > 0
  
  local node = NuiTree.Node({
    id = "variable:" .. var_name .. ":" .. tostring(var_ref),
    text = text,
    type = "variable",
    expandable = expandable,
    _variable = self,
    _highlight = style.highlight,  -- Store highlight group for rendering
    _is_lazy = is_lazy,           -- Track lazy status
  })
  
  addNodeCompatibilityMethods(node, plugin_instance.state_tree)

      -- Autonomous: lazy load child variables when expanded
      if expandable then
        node._lazy_load = function()
          if node._children_loaded then return end
          
          -- Wrap in async context to call Variable:variables()
          require('neodap.tools.async').run(function()
            plugin_instance.logger:debug("Variable lazy load starting for: " .. node.id)
            
            local ok, children = pcall(function() return self:variables() end)
            if not ok then
              plugin_instance.logger:error("Failed to get child variables: " .. tostring(children))
              return
            end
            
            plugin_instance.logger:debug("Variable children result: " .. vim.inspect(children))
            
            if children and plugin_instance.state_tree then
              plugin_instance.logger:debug("Adding " .. #children .. " child variables to " .. node.id)
              for i, child in ipairs(children) do
                local child_node = child:asNode()
                plugin_instance.logger:debug("Adding child[" .. i .. "] node: " .. child_node.id .. " text: " .. child_node.text)
                plugin_instance.state_tree:add_node(child_node, node.id)
              end
              node._children_loaded = true
              plugin_instance.state_tree:render() -- Update all views
            else
              plugin_instance.logger:debug("No child variables found or state_tree missing")
            end
          end)
        end
      end

  self._cached_node = node
  return node
end

function DebugTree.plugin(api)
  return BasePlugin.createPlugin(api, DebugTree)
end

function DebugTree:listen()
  self.logger:info("Initializing DebugTree plugin - shared-node reactive architecture")

  -- Initialize instance properties
  self.active_view_trees = {}
  
  -- Set the plugin instance for asNode methods
  plugin_instance = self

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
        if frames then
          -- Get first frame from Frames iterator
          for frame in frames:each() do
            current_frame = frame
            break
          end
          if current_frame then break end
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
      wrap = false,  -- Prevent line wrapping, let long lines overflow
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
    -- Single entity view - ensure the entity's node exists
    local root_node = root_entity:asNode()
    
    -- For frames, we need to add scopes as children
    if root_entity.scopes then
      -- It's a frame - add its scopes
      local scopes = root_entity:scopes()
      if scopes then
        for _, scope in ipairs(scopes) do
          local scope_node = scope:asNode()
          self.state_tree:add_node(scope_node, root_node.id)
        end
      end
    end
    
    -- Make sure the node is in the state tree
    if not self.state_tree.nodes.by_id[root_node.id] then
      self.state_tree:add_node(root_node)
    end
    
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

  -- Setup keybindings with vim-style navigation
  local function expandOrDrillIntoNode()
    local node = view_tree:get_node()
    if not node then return end
    
    -- Handle lazy variables
    if node._is_lazy then
      self:resolveLazyVariable(node, view_tree)
      return
    end
    
    -- For all expandable nodes, toggle expansion
    if node:has_children() or node.expandable or node._lazy_load then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
        -- Move to first child after expanding
        if node:has_children() then
          local child_ids = node:get_child_ids()
          if child_ids and #child_ids > 0 then
            vim.schedule(function()
              self:setCursorToNode(view_tree, child_ids[1])
            end)
          end
        end
      end
      view_tree:render()
    end
  end
  
  -- <CR> and l - Expand/drill into node
  popup:map("n", "<CR>", expandOrDrillIntoNode)
  popup:map("n", "l", expandOrDrillIntoNode)
  
  -- h - Navigate to parent level or collapse current node
  popup:map("n", "h", function()
    local node = view_tree:get_node()
    if not node then return end
    
    if node:is_expanded() then
      -- Collapse current node
      node:collapse()
      view_tree:render()
    else
      -- Navigate to parent
      local parent_id = node:get_parent_id()
      if parent_id then
        self:setCursorToNode(view_tree, parent_id)
      end
    end
  end)
  
  -- j - Navigate to next sibling or next visible node
  popup:map("n", "j", function()
    local node = view_tree:get_node()
    if not node then 
      vim.cmd("normal! j")
      return
    end
    
    -- Get all visible nodes in order
    local visible_nodes = self:getVisibleNodes(view_tree)
    local current_id = node:get_id()
    
    for i, node_id in ipairs(visible_nodes) do
      if node_id == current_id and i < #visible_nodes then
        self:setCursorToNode(view_tree, visible_nodes[i + 1])
        return
      end
    end
    
    -- Fallback to normal j
    vim.cmd("normal! j")
  end)
  
  -- k - Navigate to previous sibling or previous visible node
  popup:map("n", "k", function()
    local node = view_tree:get_node()
    if not node then
      vim.cmd("normal! k")
      return
    end
    
    -- Get all visible nodes in order
    local visible_nodes = self:getVisibleNodes(view_tree)
    local current_id = node:get_id()
    
    for i, node_id in ipairs(visible_nodes) do
      if node_id == current_id and i > 1 then
        self:setCursorToNode(view_tree, visible_nodes[i - 1])
        return
      end
    end
    
    -- Fallback to normal k
    vim.cmd("normal! k")
  end)
  
  -- f - Focus on current node (show only its subtree)
  popup:map("n", "f", function()
    local node = view_tree:get_node()
    if not node then return end
    
    -- Store the original root_ids if not already stored
    if not view_tree._original_root_ids then
      view_tree._original_root_ids = vim.deepcopy(view_tree._view_root_ids)
    end
    
    -- Focus on this node by making it the only root
    view_tree._view_root_ids = { node:get_id() }
    view_tree.nodes.root_ids = view_tree._view_root_ids
    
    -- Update popup title to show focus
    local title = " DebugTree - Focused: " .. (node.text or "Unknown") .. " "
    popup.border:set_text("top", title, "center")
    
    view_tree:render()
  end)
  
  -- F - Unfocus (restore original view)
  popup:map("n", "F", function()
    if view_tree._original_root_ids then
      view_tree._view_root_ids = view_tree._original_root_ids
      view_tree.nodes.root_ids = view_tree._view_root_ids
      view_tree._original_root_ids = nil
      
      -- Restore original title
      popup.border:set_text("top", " " .. title .. " ", "center")
      
      view_tree:render()
    end
  end)
  
  -- r - Refresh tree
  popup:map("n", "r", function()
    view_tree:render()
    vim.notify("Tree refreshed", vim.log.levels.INFO)
  end)
  
  -- q - Quit
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
  
  -- ? - Help
  popup:map("n", "?", function()
    local help_text = [[
DebugTree Navigation:
  h       - Navigate to parent / Collapse node
  j       - Navigate to next node
  k       - Navigate to previous node  
  l/<CR>  - Expand node / Drill into
  
Controls:
  f       - Focus on current subtree
  F       - Unfocus (restore full view)
  r       - Refresh tree
  q       - Quit
  ?       - Show this help
  
Features:
  ⏳      - Lazy variable (not yet loaded)
  ▶/▼    - Expandable/Expanded node]]
    
    vim.notify(help_text, vim.log.levels.INFO)
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

    -- Add content (ensure no newlines)
    local text = node.text or ""
    text = text:gsub("[\n\r]+", " ")
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
    for index, frame in ipairs(root_entity.frames) do
      local frame_node = frame:asNode(index)
      self.state_tree:add_node(frame_node, "stack:" .. tostring(root_entity.thread.id))
    end
  end
  -- Frame and deeper levels use lazy loading, so no need to pre-populate
end

-- ========================================
-- NAVIGATION HELPERS
-- ========================================

-- Get all visible nodes in tree order
function DebugTree:getVisibleNodes(tree)
  local visible_nodes = {}
  
  local function traverse(node_id)
    local node = tree.nodes.by_id[node_id]
    if not node then return end
    
    table.insert(visible_nodes, node_id)
    
    if node:is_expanded() and node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        traverse(child_id)
      end
    end
  end
  
  -- Traverse from root nodes
  for _, root_id in ipairs(tree.nodes.root_ids) do
    traverse(root_id)
  end
  
  return visible_nodes
end

-- Smart cursor positioning that finds the first meaningful character
function DebugTree:setCursorToNode(tree, node_id, window)
  local node, line = tree:get_node(node_id)
  if node and line then
    -- Get the line content
    local lines = vim.api.nvim_buf_get_lines(tree.bufnr, line - 1, line, false)
    if lines and lines[1] then
      local line_text = lines[1]
      
      -- Skip past tree structure characters to find actual content
      local pos = 1
      local len = #line_text
      
      -- Skip tree drawing characters and spaces
      while pos <= len do
        local char = line_text:sub(pos, pos)
        local utf8_char = line_text:sub(pos, pos + 2)
        
        -- Check for tree structure characters
        if char == "│" or char == " " or char == "─" then
          pos = pos + 1
        elseif utf8_char == "╰" or utf8_char == "├" then
          pos = pos + 3
        elseif utf8_char == "▶" or utf8_char == "▼" then
          -- Found expand/collapse indicator, position after it + space
          pos = pos + 4  -- Skip the indicator and following space
          break
        else
          -- Found content
          break
        end
      end
      
      -- Ensure we don't go past the line
      if pos > len then pos = len end
      if pos < 1 then pos = 1 end
      
      vim.api.nvim_win_set_cursor(window or 0, {line, pos - 1})
    else
      -- Fallback
      vim.api.nvim_win_set_cursor(window or 0, {line, 0})
    end
  end
end

-- Resolve lazy variable by fetching its actual value
function DebugTree:resolveLazyVariable(node, view_tree)
  local variable = node._variable
  if not variable or not variable.resolve then
    self.logger:warn("Cannot resolve lazy variable - no variable or resolve method")
    return
  end
  
  -- Call the variable's resolve method
  require('neodap.tools.async').run(function()
    local success = variable:resolve()
    if success then
      -- Update node text with resolved value
      local var_type = (variable.ref and variable.ref.type) and variable.ref.type:lower() or "default"
      local style = getVariableStyle(var_type)
      
      if isArray(variable.ref) then
        style = getVariableStyle("array")
      end
      
      local formatted_value = formatVariableValue(variable.ref, style)
      local var_name = variable.name or (variable.ref and variable.ref.name) or "unknown"
      
      node.text = style.icon .. " " .. var_name .. ": " .. formatted_value
      node._is_lazy = false
      
      -- Re-render tree
      view_tree:render()
      
      self.logger:info("Resolved lazy variable: " .. var_name)
    else
      self.logger:warn("Failed to resolve lazy variable")
    end
  end)
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
