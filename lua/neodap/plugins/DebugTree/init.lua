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

-- Rich type icons and formatting with Tree-sitter highlight groups
local VariablePresentation = {
  styles = {
    -- JavaScript primitives
    string = { icon = "󰉿", highlight = "@string", truncate = 35 },
    number = { icon = "󰎠", highlight = "@number", truncate = 40 },
    boolean = { icon = "◐", highlight = "@boolean", truncate = 40 },
    undefined = { icon = "󰟢", highlight = "@constant.builtin", truncate = 40 },
    ['nil'] = { icon = "∅", highlight = "@constant.builtin", truncate = 40 },
    null = { icon = "∅", highlight = "@constant.builtin", truncate = 40 },
    
    -- Complex types
    object = { icon = "󰅩", highlight = "@type", truncate = 40 },
    array = { icon = "󰅪", highlight = "@type.builtin", truncate = 40 },
    ['function'] = { icon = "󰊕", highlight = "@function", truncate = 25 },
    
    -- Special types
    date = { icon = "󰃭", highlight = "@type.builtin", truncate = 40 },
    regexp = { icon = "󰑑", highlight = "@string.regex", truncate = 40 },
    map = { icon = "󰘣", highlight = "@type.builtin", truncate = 40 },
    set = { icon = "󰘦", highlight = "@type.builtin", truncate = 40 },
    
    -- Default fallback
    default = { icon = "󰀬", highlight = "@variable", truncate = 40 },
  }
}

-- Entity type highlight mapping
local EntityHighlights = {
  session = "@namespace",
  thread = "@function.call", 
  stack = "@type",
  frame = "@function",
  scope = "@parameter",
  variable = "@variable",
}

-- PresentationHint kind to highlight mapping
local KindHighlights = {
  property = "@property",
  method = "@method",
  class = "@type.builtin",
  data = "@variable",
  event = "@function.builtin",
}

-- Visibility modifiers
local VisibilityPrefixes = {
  private = "🔒",
  protected = "🔐",
  public = "🌐",
  internal = "🏠",
}

-- Attribute indicators
local AttributeIndicators = {
  static = "𝑺",
  constant = "𝑪",
  readOnly = "𝑹",
  rawString = "𝑹",
  hasObjectId = "𝑶",
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

-- NUI Tree nodes already have all required methods via TreeNode metatable
-- No compatibility layer needed anymore!

-- Store plugin instance for asNode methods
local plugin_instance = nil

-- Helper to escape special characters in path segments
local function escapePathSegment(segment)
  -- URL-encode special characters that could break our path structure
  return tostring(segment):gsub("([/:#%%])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

-- Helper to build path-based IDs in URL format
local function buildPathId(parent_path, entity_type, entity_id)
  local base = parent_path or "dap:/"
  
  -- For root level (no parent), start with dap://
  if base == "dap:/" then
    return "dap://" .. entity_type .. "/" .. tostring(entity_id)
  end
  
  -- Otherwise append to parent path
  -- Escape the entity_id to handle special characters (especially for variable names)
  local escaped_id = escapePathSegment(entity_id)
  return base .. "/" .. entity_type .. "/" .. escaped_id
end

-- ========================================
-- API RESOURCE EXTENSIONS
-- ========================================

-- Extend API resources with ResolveChildren method

---@param self api.Session
---@param node NuiTree.Node
function Session:ResolveChildren(node)
  -- Sessions don't have lazy children - threads are maintained by events
  -- This is just here for consistency with the expand interface
  -- The real children (threads) are added via self:onThread() event handler
end

---@param self api.Thread
---@param node NuiTree.Node
function Thread:ResolveChildren(node)
  -- Threads don't have lazy children - stack is added by onStopped event
  -- This is just here for consistency with the expand interface
  -- The real children (stack) are added via self:onStopped() event handler
end

---@param self api.Stack
---@param node NuiTree.Node
function Stack:ResolveChildren(node)
  -- Stack frames are loaded synchronously
  if node._children_loaded then return end
  
  local frames = self:getFrames()
  if frames and plugin_instance.state_tree then
    local index = 0
    for frame in frames:each() do
      index = index + 1
      -- Pass the index and parent path to frame:asNode
      local frame_node = frame:asNode(index, node.id)
      plugin_instance.state_tree:add_node(frame_node, node.id)
    end
    -- CRITICAL: Update the state tree node, not the parameter node
    plugin_instance.state_tree.nodes.by_id[node.id]._children_loaded = true
    -- Don't render here - let the caller do it after we return
  end
end

---@param self api.Frame
---@param node NuiTree.Node
function Frame:ResolveChildren(node)
  -- Frames have lazy-loaded scopes
  if node._children_loaded then return end
  
  local scopes = self:scopes()
  
  if scopes and plugin_instance.state_tree then
    -- Pass the frame's node ID to scope:asNode for prefixing
    for i, scope in ipairs(scopes) do
      local scope_node = scope:asNode(node.id)
      plugin_instance.state_tree:add_node(scope_node, node.id)
    end
    -- CRITICAL: Update the state tree node, not the parameter node
    plugin_instance.state_tree.nodes.by_id[node.id]._children_loaded = true
  end
end

---@param self api.Scope
---@param node NuiTree.Node
function Scope:ResolveChildren(node)
  -- Scopes have lazy-loaded variables
  if node._children_loaded then return end
  
  local variables = self:variables()
  
  if variables and plugin_instance.state_tree then
    for i, variable in ipairs(variables) do
      local var_node = variable:asNode(node.id)  -- Pass parent (scope) ID
      plugin_instance.state_tree:add_node(var_node, node.id)
    end
    -- CRITICAL: Update the state tree node, not the parameter node
    plugin_instance.state_tree.nodes.by_id[node.id]._children_loaded = true
  end
end

---@param self api.Variable
---@param node NuiTree.Node
function Variable:ResolveChildren(node)
  -- Variables with variablesReference > 0 have lazy-loaded children
  if node._children_loaded then return end
  
  -- Only resolve if this variable has children
  local var_ref = (self.ref and self.ref.variablesReference) or 0
  if var_ref == 0 then return end
  
  local children = self:variables()
  
  if children and plugin_instance.state_tree then
    for i, child in ipairs(children) do
      local child_node = child:asNode(node.id)  -- Pass parent (variable) ID
      plugin_instance.state_tree:add_node(child_node, node.id)
    end
    -- CRITICAL: Update the state tree node, not the parameter node
    plugin_instance.state_tree.nodes.by_id[node.id]._children_loaded = true
  end
end


-- ========================================
-- SESSION NODE
-- ========================================

---@param self api.Session
---@return NuiTree.Node
function Session:asNode()
  if self._cached_node then return self._cached_node end

  -- Create display text that shows parent-child relationship
  local display_text = "📡 Session " .. tostring(self.id)
  if self.parent then
    display_text = "📡 Child Session " .. tostring(self.id)
  end

  local node = NuiTree.Node({
    id = "session:" .. tostring(self.id),  -- Keep old format for now
    text = display_text,
    type = "session",
    expandable = true,
    _dap = self,
  })

  -- Autonomous: when threads appear, add them directly to tree
  self:onThread(function(thread)
    plugin_instance.logger:debug("Session " .. self.id .. " got thread event for thread " .. thread.id)
    local thread_node = thread:asNode()
    if plugin_instance.state_tree then
      plugin_instance.state_tree:add_node(thread_node, node.id)
      plugin_instance.state_tree:render() -- This will render all view trees!
    end
  end)
  
  -- IMPORTANT: Also check for existing threads that won't trigger onThread events
  -- This handles threads that already exist when we create the session node
  if self.threads then
    local existing_count = 0
    for thread in self.threads:each() do
      existing_count = existing_count + 1
      plugin_instance.logger:debug("Session " .. self.id .. " has existing thread " .. thread.id)
      local thread_node = thread:asNode()
      if plugin_instance.state_tree then
        plugin_instance.state_tree:add_node(thread_node, node.id)
      end
    end
    if existing_count > 0 then
      plugin_instance.logger:debug("Added " .. existing_count .. " existing threads to session " .. self.id)
      if plugin_instance.state_tree then
        plugin_instance.state_tree:render()
      end
    end
  end
  
  -- Autonomous: when child sessions are created via startDebugging
  -- Note: This requires the session to have a way to notify about child sessions
  -- For now, child sessions will be added when they're created with parent set

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

  -- Get session ID to build hierarchical path
  local session_id = self.session and buildPathId(nil, "session", self.session.id) or nil
  local thread_id = session_id and buildPathId(session_id, "thread", self.id) 
                    or buildPathId(nil, "thread", self.id)

  local node = NuiTree.Node({
    id = thread_id,
    text = getDisplayText(),
    type = "thread",
    expandable = self.stopped,
    _dap = self,
  })

  -- Check if thread is already stopped and has a stack
  if self.stopped then
    local stack = self:stack()
    if stack and plugin_instance.state_tree then
      local stack_node = stack:asNode()
      plugin_instance.state_tree:add_node(stack_node, node.id)
    end
  end

  -- Autonomous: update when stopped/continued
  self:onStopped(function()
    plugin_instance.logger:debug("Thread " .. self.id .. " stopped event")
    node.text = getDisplayText()
    node.expandable = true

    -- Add stack when stopped (if not already added)
    local stack = self:stack()
    if stack and plugin_instance.state_tree then
      -- Generate the actual stack node to get its ID
      local stack_node = stack:asNode()
      -- Check if stack already exists to avoid duplicates
      if not plugin_instance.state_tree.nodes.by_id[stack_node.id] then
        plugin_instance.logger:debug("Adding stack for newly stopped thread " .. self.id)
        plugin_instance.state_tree:add_node(stack_node, node.id)
        
        -- Auto-expand the stack to show frames
        stack_node:expand()
        plugin_instance:autoExpandTopFrame(stack_node)
      end
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

  -- Build hierarchical ID through session -> thread -> stack
  local thread_id = self.thread and self.thread._cached_node and self.thread._cached_node.id
  local stack_id = thread_id and buildPathId(thread_id, "stack", self.thread.id)
                   or buildPathId(nil, "stack", self.thread.id)

  local node = NuiTree.Node({
    id = stack_id,
    text = "📚 Stack (" .. frame_count .. " frames)",
    type = "stack",
    expandable = true,
    _dap = self,
  })


  self._cached_node = node
  return node
end

-- ========================================
-- FRAME NODE
-- ========================================

---@param self api.Frame
---@param index? number The frame's position in the stack (1-based)
---@param parent_path? string Parent stack path for ID generation
---@return NuiTree.Node
function Frame:asNode(index, parent_path)
  -- For frames with index, we need unique nodes per position
  local cache_key = index and ("_cached_node_" .. index) or "_cached_node"
  if self[cache_key] then return self[cache_key] end

  -- Clean up frame name to remove newlines and control characters
  local frame_name = self.ref.name or "Frame " .. tostring(self.ref.id)
  -- Replace newlines and tabs with spaces, trim whitespace
  frame_name = frame_name:gsub("[\n\r\t]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  
  -- Generate hierarchical frame ID
  -- Use frame index as identifier to ensure uniqueness within stack
  local frame_identifier = index or self.ref.id
  local frame_id = parent_path and buildPathId(parent_path, "frame", frame_identifier)
                   or buildPathId(nil, "frame", tostring(self.ref.id) .. ":" .. tostring(index or 0))
  
  -- Add frame number prefix if index is provided
  local display_text = index and ("#" .. index .. " 🖼️  " .. frame_name) or ("🖼️  " .. frame_name)
  
  local node = NuiTree.Node({
    id = frame_id,
    text = display_text,
    type = "frame",
    expandable = true,
    _dap = self,
    _frame_index = index,
  })


  self[cache_key] = node
  return node
end

-- ========================================
-- SCOPE NODE
-- ========================================

---@param self api.Scope
---@param frame_id? string Optional frame ID to prefix the scope ID
---@return NuiTree.Node
function Scope:asNode(frame_id)
  -- Use frame_id as cache key if provided
  local cache_key = frame_id and ("_cached_node_" .. frame_id) or "_cached_node"
  if self[cache_key] then return self[cache_key] end

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

  -- Generate hierarchical scope ID
  local vars_ref = self.variablesReference or self.ref.variablesReference
  local scope_id = frame_id and buildPathId(frame_id, "scope", vars_ref)
                   or buildPathId(nil, "scope", vars_ref)

  local node = NuiTree.Node({
    id = scope_id,
    text = scope_icon .. " " .. scope_name,
    type = "scope",
    expandable = true,
    _dap = self,
    _frame_id = frame_id,  -- Store frame ID for later use
  })


  self[cache_key] = node
  return node
end

-- ========================================
-- VARIABLE NODE
-- ========================================

---@param self api.Variable
---@param parent_id? string Optional parent ID (scope or variable) to prefix the variable ID
---@return NuiTree.Node
function Variable:asNode(parent_id)
  -- Use parent_id as cache key if provided
  local cache_key = parent_id and ("_cached_node_" .. parent_id) or "_cached_node"
  if self[cache_key] then return self[cache_key] end
  
  -- Store scope information if available
  if not self.scope and self.parent and self.parent.name then
    self.scope = self.parent
  end

  -- Get variable type and style
  local var_type = (self.ref and self.ref.type) and self.ref.type:lower() or "default"
  local style = getVariableStyle(var_type)
  
  -- Check for array vs object
  if isArray(self.ref) then
    style = getVariableStyle("array")
  end
  
  -- Check for lazy variables
  local is_lazy = self.ref and self.ref.presentationHint and self.ref.presentationHint.lazy
  
  -- Extract presentation hints
  local hint = self.ref and self.ref.presentationHint
  local kind = hint and hint.kind
  local visibility = hint and hint.visibility
  local attributes = hint and hint.attributes or {}
  
  -- Format the value using sophisticated formatting
  local formatted_value = formatVariableValue(self.ref, style)
  
  -- Clean variable name
  local var_name = self.name or (self.ref and self.ref.name) or "unknown"
  var_name = tostring(var_name):gsub("[\n\r\t]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  
  -- Choose icon based on kind or type
  local icon = is_lazy and "⏳" or style.icon  -- Show loading icon for lazy vars
  
  -- Build node text
  local text = icon .. " " .. var_name .. ": " .. formatted_value
  text = text:gsub("[\n\r]+", " ")  -- Final safety check
  
  local var_ref = (self.ref and self.ref.variablesReference) or 0
  local expandable = var_ref > 0
  
  -- Generate hierarchical variable ID
  local var_id
  if parent_id then
    -- Append variable name to parent path (escaped to handle special chars)
    var_id = buildPathId(parent_id, "variable", var_name)
  else
    -- Fallback for variables without parent context
    local parent_scope_id = ""
    if self.parent and self.parent.variablesReference then
      parent_scope_id = tostring(self.parent.variablesReference) .. ":"
    end
    var_id = buildPathId(nil, "variable", parent_scope_id .. var_name .. ":" .. tostring(var_ref))
  end
  
  local node = NuiTree.Node({
    id = var_id,
    text = text,
    type = "variable",
    expandable = expandable,
    _dap = self,
    _parent_id = parent_id,  -- Store parent ID for reference
    _highlight = style.highlight,  -- Store highlight group for rendering
    _is_lazy = is_lazy,           -- Track lazy status
    _kind = kind,                 -- Store presentationHint.kind
    _visibility = visibility,     -- Store visibility
    _attributes = attributes,     -- Store attributes
    _has_memory = self.ref and self.ref.memoryReference ~= nil,
    _evaluateName = self.ref and self.ref.evaluateName,
  })


  self[cache_key] = node
  return node
end

function DebugTree.plugin(api)
  return BasePlugin.createPlugin(api, DebugTree)
end

function DebugTree:listen()
  -- Initialize instance properties
  self.active_view_trees = {}
  
  -- Set the plugin instance for asNode methods
  plugin_instance = self

  -- Setup session event handlers to initialize reactive nodes
  self:setupSessionHandlers()

  -- Setup commands
  self:setupCommands()
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
    
    -- Check if this session has a parent session
    if session.parent then
      -- Add as child of parent session
      local parent_id = "session:" .. tostring(session.parent.id)
      self.state_tree:add_node(session_node, parent_id)
    else
      -- Add as root session
      self.state_tree:add_node(session_node)
    end

    -- Add any existing threads to the state tree
    self:addExistingChildren(session)
    
    -- Render all views to show new session
    self.state_tree:render()
  end)
end

--- Initialize the state tree that holds all DAP nodes
-- The state tree is a central NUI Tree instance that stores all debug adapter
-- protocol nodes (sessions, threads, stacks, frames, scopes, variables).
-- View trees share references to these nodes but can display different subsets.
-- This architecture allows multiple views of the same debug state without duplication.
function DebugTree:initializeStateTree()
  if self.state_tree then return end -- Already initialized
  
  -- Create a scratch buffer for the state tree (never displayed)
  local state_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(state_bufnr, "[DebugTree-State]")
  
  -- Use real NUI Tree for state management
  -- Benefits over custom implementation:
  -- - Battle-tested tree operations
  -- - Efficient node management
  -- - Proper parent-child relationships
  self.state_tree = NuiTree({
    bufnr = state_bufnr,
    nodes = {},
    get_node_id = function(node) return node.id end,
  })
  
  -- Override render to update all view trees instead
  -- When state changes, all active views are re-rendered
  self.state_tree.render = function(state_tree)
    -- State tree render -> render all active view trees
    for _, view_tree in ipairs(self.active_view_trees) do
      if view_tree.bufnr and vim.api.nvim_buf_is_valid(view_tree.bufnr) then
        -- Restore the view's specific root_ids before rendering
        view_tree.nodes.root_ids = view_tree._view_root_ids
        
        -- View trees already share the nodes structure, just render!
        view_tree:render()
      end
    end
  end

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
    
    -- Note: For frames, scopes will be loaded lazily when the frame is expanded
    -- This prevents duplicate scopes from appearing
    
    -- Make sure the node is in the state tree
    if not self.state_tree.nodes.by_id[root_node.id] then
      self.state_tree:add_node(root_node)
    end
    
    -- Don't pre-expand - let the user expand with 'l' to trigger proper loading
    
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
  self:setupViewTreeKeybindings(view_tree, popup, title)
end


-- ========================================
-- VIEW TREE KEYBINDINGS
-- ========================================

function DebugTree:setupViewTreeKeybindings(view_tree, popup, title)
  local async = require('neodap.tools.async')
  
  -- Primary navigation (vim-like)
  popup:map("n", "l", function() async.run(function() self:Open(view_tree) end) end)     -- Right: open/enter
  popup:map("n", "h", function() self:Close(view_tree) end)                             -- Left: close/back
  popup:map("n", "<CR>", function() self:Toggle(view_tree) end)                         -- Enter: toggle
  popup:map("n", "<Space>", function() self:Toggle(view_tree) end)                      -- Space: toggle (alternative)
  popup:map("n", "o", function() async.run(function() self:Expand(view_tree) end) end)  -- o: expand only
  
  -- Vertical navigation with smart node awareness
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
  
  -- Sibling navigation
  popup:map("n", "H", function() self:PreviousSibling(view_tree) end)
  popup:map("n", "L", function() self:NextSibling(view_tree) end)
  
  -- Smart up/down navigation
  popup:map("n", "gk", function() self:Up(view_tree) end)
  popup:map("n", "gj", function() self:Down(view_tree) end)
  
  popup:map("n", "J", function() self:LastSibling(view_tree) end)   -- Jump to last sibling
  popup:map("n", "K", function() self:FirstSibling(view_tree) end)  -- Jump to first sibling
  
  -- Focus controls
  popup:map("n", "f", function() self:FocusIn(view_tree, popup) end)
  popup:map("n", "F", function() self:FocusOut(view_tree, popup, title) end)
  
  -- Utility keys
  popup:map("n", "r", function() view_tree:render() end)
  
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
  
  -- Debug info
  popup:map("n", "!", function()
    local node = view_tree:get_node()
    if not node then
      vim.notify("No node under cursor", vim.log.levels.WARN)
      return
    end
    
    local debug_info = {}
    table.insert(debug_info, "=== Node Debug Info ===")
    table.insert(debug_info, "")
    table.insert(debug_info, "Node ID: " .. (node.id or "nil"))
    table.insert(debug_info, "Text: " .. (node.text or "nil"))
    table.insert(debug_info, "Type: " .. (node.type or "nil"))
    
    -- Build and show the path
    local path_parts = {}
    local current = node
    while current do
      table.insert(path_parts, 1, current.id)
      local parent_id = current:get_parent_id()
      if parent_id then
        current = view_tree.nodes.by_id[parent_id]
      else
        current = nil
      end
    end
    table.insert(debug_info, "Path: /" .. table.concat(path_parts, "/"))
    table.insert(debug_info, "")
    
    -- Node state
    table.insert(debug_info, "=== Node State ===")
    table.insert(debug_info, "Expandable: " .. tostring(node.expandable))
    table.insert(debug_info, "Expanded: " .. tostring(node:is_expanded()))
    table.insert(debug_info, "Has Children: " .. tostring(node:has_children()))
    table.insert(debug_info, "Depth: " .. tostring(node:get_depth()))
    table.insert(debug_info, "Parent ID: " .. (node:get_parent_id() or "nil"))
    
    -- Child info
    if node._child_ids then
      table.insert(debug_info, "Child Count: " .. #node._child_ids)
    end
    table.insert(debug_info, "")
    
    -- DAP reference
    if node._dap then
      table.insert(debug_info, "=== DAP Reference ===")
      table.insert(debug_info, "Has _dap: true")
      table.insert(debug_info, "Type: " .. type(node._dap))
      
      if node._dap.ref then
        table.insert(debug_info, "")
        table.insert(debug_info, "=== _dap.ref content ===")
        local ref_str = vim.inspect(node._dap.ref, {
          depth = 3,
          indent = "  "
        })
        for line in ref_str:gmatch("[^\n]+") do
          table.insert(debug_info, line)
        end
      else
        table.insert(debug_info, "No ref field")
      end
      
      -- Check for other useful DAP methods
      if node._dap.ResolveChildren then
        table.insert(debug_info, "")
        table.insert(debug_info, "Has ResolveChildren method")
      end
    else
      table.insert(debug_info, "=== DAP Reference ===")
      table.insert(debug_info, "No _dap reference")
    end
    
    -- Special flags
    table.insert(debug_info, "")
    table.insert(debug_info, "=== Special Flags ===")
    table.insert(debug_info, "Is Lazy: " .. tostring(node._is_lazy or false))
    table.insert(debug_info, "Children Loaded: " .. tostring(node._children_loaded or false))
    
    -- Display in a floating window
    local width = 60
    local height = math.min(#debug_info + 2, 40)
    
    local debug_popup = NuiPopup({
      position = "50%",
      size = {
        width = width,
        height = height,
      },
      enter = true,
      focusable = true,
      border = {
        style = "rounded",
        text = {
          top = " Node Debug Info ",
          top_align = "center",
        },
      },
    })
    
    debug_popup:mount()
    
    -- Set content
    vim.api.nvim_buf_set_lines(debug_popup.bufnr, 0, -1, false, debug_info)
    
    -- Make it read-only
    vim.api.nvim_buf_set_option(debug_popup.bufnr, "modifiable", false)
    vim.api.nvim_buf_set_option(debug_popup.bufnr, "buftype", "nofile")
    
    -- Close on q or Esc
    debug_popup:map("n", "q", function() debug_popup:unmount() end)
    debug_popup:map("n", "<Esc>", function() debug_popup:unmount() end)
  end)
  
  -- Help
  popup:map("n", "?", function()
    local help_text = [[
DebugTree Navigation:
  h       - Close (collapse or go to parent)
  l       - Open (expand and enter)
  j/k     - Next/Previous visible node
  <CR>    - Toggle expand/collapse
  <Space> - Toggle expand/collapse
  o       - Expand only (no navigation)
  
Sibling Navigation:
  H/L     - Previous/Next sibling
  K/J     - First/Last sibling
  
Smart Navigation:
  gk      - Up (prev sibling, then parent)
  gj      - Down (child, next sibling, or parent's next)
  
Focus Controls:
  f       - Focus on current subtree
  F       - Unfocus (restore full view)
  
Other:
  r       - Refresh tree
  q       - Quit
  ?       - Show this help
  !       - Show debug info for current node
  
Indicators:
  ⏳      - Lazy variable (click to load)
  ▶/▼    - Collapsed/Expanded node]]
    
    vim.notify(help_text, vim.log.levels.INFO)
  end)
end

-- ========================================
-- VIEW TREE HELPERS
-- ========================================

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
    local has_children = node._child_ids and #node._child_ids > 0
    if has_children or node.expandable then
      if node:is_expanded() then
        line:append("▼ ", "Comment")
      else
        line:append("▶ ", "Comment")
      end
    else
      line:append("  ")
    end

    -- Store cursor position - this is where the content starts
    node._cursor_col = line:content():len()

    -- Add content with proper highlighting
    local text = node.text or ""
    text = text:gsub("[\n\r]+", " ")
    
    -- Get the appropriate highlight group based on node type
    local highlight_group = EntityHighlights[node.type] or "@text"
    
    -- For variables, use more specific highlighting based on the stored highlight
    if node.type == "variable" then
      -- Use kind-based highlighting if available
      if node._kind and KindHighlights[node._kind] then
        highlight_group = KindHighlights[node._kind]
      elseif node._highlight then
        highlight_group = node._highlight
      end
    end
    
    -- Parse variable nodes for better syntax highlighting
    if node.type == "variable" then
      -- Split variable display into parts: icon, name, colon, value
      local icon_end = text:find(" ") or 1
      local icon = text:sub(1, icon_end)
      local rest = text:sub(icon_end + 1)
      
      local colon_pos = rest:find(":")
      if colon_pos then
        local var_name = rest:sub(1, colon_pos - 1)
        local colon_and_value = rest:sub(colon_pos)
        
        -- Add icon with default highlighting
        line:append(icon, "@text.note")
        
        -- Determine variable name highlighting based on DAP metadata
        local name_highlight = "@variable"
        
        -- Analyze variable name patterns for better highlighting
        local var_name_upper = var_name:upper()
        local var_name_lower = var_name:lower()
        
        -- Check for common patterns first
        if var_name:match("^[A-Z][a-zA-Z0-9]*$") then
          -- PascalCase typically indicates a class or constructor
          name_highlight = "@constructor"
        elseif var_name:match("^[A-Z_]+$") then
          -- UPPER_CASE typically indicates constants
          name_highlight = "@constant"
        elseif var_name:match("^_") then
          -- Leading underscore often indicates private
          name_highlight = "@field"
        elseif var_name:match("^%$") then
          -- $ prefix (like in observables)
          name_highlight = "@variable.builtin"
        end
        
        -- Override with DAP presentation hints if available
        if node._kind then
          if node._kind == "method" then
            name_highlight = "@method"
          elseif node._kind == "property" then
            name_highlight = "@property"
          elseif node._kind == "class" then
            name_highlight = "@type"
          elseif node._kind == "event" then
            name_highlight = "@function.builtin"
          end
        end
        
        -- Check attributes for more specific highlighting
        if node._attributes then
          for _, attr in ipairs(node._attributes) do
            if attr == "constant" or attr == "readOnly" then
              name_highlight = "@constant"
              break
            elseif attr == "static" then
              name_highlight = "@variable.builtin"
              break
            end
          end
        end
        
        -- Check visibility for additional context
        if node._visibility then
          if node._visibility == "private" then
            -- Private members often use different highlighting
            if not node._kind then
              name_highlight = "@field"
            end
          elseif node._visibility == "internal" then
            -- Internal/built-in variables
            if var_name:match("^[A-Z]") then
              name_highlight = "@type.builtin"  -- Built-in constructors
            else
              name_highlight = "@variable.builtin"  -- Built-in values
            end
          end
        end
        
        -- Check if this is in a specific scope that gives context
        if node._dap and node._dap.scope then
          local scope_name = node._dap.scope.name
          if scope_name == "Arguments" or scope_name == "Local" then
            -- If it's a function parameter or local variable
            if var_name:match("^[a-z]") and not node._kind then
              name_highlight = "@parameter"
            end
          elseif scope_name == "Global" then
            -- Global variables might use different highlighting
            if not node._kind and not var_name:match("^[A-Z]") then
              name_highlight = "@variable.builtin"
            end
          end
        end
        
        line:append(var_name, name_highlight)
        
        -- Add colon
        line:append(":", "@punctuation.delimiter")
        
        -- Add value with type-specific highlighting
        line:append(colon_and_value:sub(2), highlight_group) -- Remove colon, already added
        
        -- Add memory reference if available
        if node._has_memory and node._dap.ref.memoryReference then
          line:append(" @", "@comment")
          line:append(node._dap.ref.memoryReference, "@number")
        end
      else
        -- Fallback: just highlight the whole thing
        line:append(text, highlight_group)
      end
    else
      -- For non-variable nodes, parse and highlight different parts
      if node.type == "session" then
        -- Highlight session differently: icon + text
        local icon_match = text:match("^(📡%s*)")
        if icon_match then
          line:append(icon_match, "@text.note")
          line:append(text:sub(#icon_match + 1), highlight_group)
        else
          line:append(text, highlight_group)
        end
      elseif node.type == "thread" then
        -- Highlight thread: icon + text + status
        local icon_match = text:match("^([⏸️▶️]%s*)")
        if icon_match then
          line:append(icon_match, "@text.note")
          local rest = text:sub(#icon_match + 1)
          local paren_start = rest:find("%(")
          if paren_start then
            line:append(rest:sub(1, paren_start - 1), highlight_group)
            line:append(rest:sub(paren_start), "@comment")
          else
            line:append(rest, highlight_group)
          end
        else
          line:append(text, highlight_group)
        end
      elseif node.type == "frame" then
        -- Highlight frame: number + icon + function name
        local num_match = text:match("^(#%d+%s*)")
        local icon_match = text:match("🖼️%s*")
        if num_match then
          line:append(num_match, "@number")
          local after_num = text:sub(#num_match + 1)
          if icon_match then
            local icon_start = after_num:find("🖼️")
            if icon_start then
              line:append(after_num:sub(1, icon_start + 1), "@text.note")
              line:append(after_num:sub(icon_start + 2), highlight_group)
            else
              line:append(after_num, highlight_group)
            end
          else
            line:append(after_num, highlight_group)
          end
        else
          line:append(text, highlight_group)
        end
      else
        -- Default highlighting for other entity types
        line:append(text, highlight_group)
      end
    end

    return line
  end
end

-- ========================================
-- TREE INITIALIZATION HELPERS
-- ========================================

function DebugTree:addChildSessions(session)
  -- Add any child sessions created via startDebugging request
  -- These don't trigger onSession events, so we need to add them manually
  if session.children then
    for child_id, child_session in pairs(session.children) do
      local child_node = child_session:asNode()
      self.state_tree:add_node(child_node, "session:" .. tostring(session.id))
      -- Recursively add any grandchild sessions
      self:addChildSessions(child_session)
    end
  end
end

-- ========================================
-- AUTO-EXPANSION LOGIC
-- ========================================

--- Auto-expand the top frame and its non-expensive scopes
---@param stack_node NuiTree.Node The stack node that was just added
function DebugTree:autoExpandTopFrame(stack_node)
  -- First, resolve the stack's children (frames)
  local stack_dap = stack_node._dap
  if stack_dap and stack_dap.ResolveChildren then
    stack_dap:ResolveChildren(stack_node)
  end
  
  -- Find the first frame (top frame)
  local frame_id = nil
  if stack_node._child_ids and #stack_node._child_ids > 0 then
    frame_id = stack_node._child_ids[1]  -- First child is frame #1
  end
  
  if not frame_id then return end
  
  local frame_node = self.state_tree.nodes.by_id[frame_id]
  if not frame_node then return end
  
  -- Expand the top frame
  frame_node:expand()
  
  -- Resolve the frame's children (scopes)
  local frame_dap = frame_node._dap
  if frame_dap and frame_dap.ResolveChildren then
    frame_dap:ResolveChildren(frame_node)
  end
  
  -- Auto-expand non-expensive scopes (Local, Closure)
  if frame_node._child_ids then
    for _, scope_id in ipairs(frame_node._child_ids) do
      local scope_node = self.state_tree.nodes.by_id[scope_id]
      if scope_node and scope_node.text then
        -- Check if it's a non-expensive scope by looking at the text
        local scope_name = scope_node.text:match("^%S+%s+(.+)$") or ""
        if scope_name == "Local" or scope_name == "Closure" then
          scope_node:expand()
          -- Note: We don't resolve scope children here - that happens on-demand
        end
      end
    end
  end
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

-- Smart cursor positioning using stored cursor column
function DebugTree:setCursorToNode(tree, node_id, window)
  local node, line = tree:get_node(node_id)
  if node and line then
    -- Use the stored cursor position if available
    local col = node._cursor_col or 0
    vim.api.nvim_win_set_cursor(window or 0, {line, col})
  end
end

-- ========================================
-- TREE NAVIGATION API
-- ========================================

-- Basic Navigation Methods

function DebugTree:NextSibling(tree)
  local node = tree:get_node()
  if not node then return false end
  
  local parent_id = node:get_parent_id()
  if not parent_id then return false end
  
  local parent = tree.nodes.by_id[parent_id]
  if not parent or not parent._child_ids then return false end
  
  local current_index
  for i, child_id in ipairs(parent._child_ids) do
    if child_id == node:get_id() then
      current_index = i
      break
    end
  end
  
  if current_index and current_index < #parent._child_ids then
    self:setCursorToNode(tree, parent._child_ids[current_index + 1])
    return true
  end
  return false
end

function DebugTree:PreviousSibling(tree)
  local node = tree:get_node()
  if not node then return false end
  
  local parent_id = node:get_parent_id()
  if not parent_id then return false end
  
  local parent = tree.nodes.by_id[parent_id]
  if not parent or not parent._child_ids then return false end
  
  local current_index
  for i, child_id in ipairs(parent._child_ids) do
    if child_id == node:get_id() then
      current_index = i
      break
    end
  end
  
  if current_index and current_index > 1 then
    self:setCursorToNode(tree, parent._child_ids[current_index - 1])
    return true
  end
  return false
end

function DebugTree:FirstSibling(tree)
  local node = tree:get_node()
  if not node then return false end
  
  local parent_id = node:get_parent_id()
  if not parent_id then return false end
  
  local parent = tree.nodes.by_id[parent_id]
  if not parent or not parent._child_ids or #parent._child_ids == 0 then return false end
  
  self:setCursorToNode(tree, parent._child_ids[1])
  return true
end

function DebugTree:LastSibling(tree)
  local node = tree:get_node()
  if not node then return false end
  
  local parent_id = node:get_parent_id()
  if not parent_id then return false end
  
  local parent = tree.nodes.by_id[parent_id]
  if not parent or not parent._child_ids or #parent._child_ids == 0 then return false end
  
  self:setCursorToNode(tree, parent._child_ids[#parent._child_ids])
  return true
end

function DebugTree:Expand(tree, node)
  node = node or tree:get_node()
  if not node then return end
  
  -- Handle lazy variables
  if node._is_lazy then
    self:resolveLazyVariable(node, tree)
    return
  end
  
  if node.expandable and not node:is_expanded() then
    -- Check if we need to load children
    local state_node = self.state_tree.nodes.by_id[node.id]
    local needs_loading = node._dap and node._dap.ResolveChildren and state_node and not state_node._children_loaded
    
    if needs_loading then
      -- Load children asynchronously
      node._dap:ResolveChildren(node)
      -- NUI Tree needs collapse/expand cycle to see new children
      node:collapse()
    end
    
    node:expand()
    tree:render()
  end
end

function DebugTree:Collapse(tree, node)
  node = node or tree:get_node()
  if not node then return end
  
  if node:is_expanded() then
    node:collapse()
    tree:render()
  end
end

function DebugTree:Toggle(tree, node)
  node = node or tree:get_node()
  if not node then return end
  
  if node:is_expanded() then
    self:Collapse(tree, node)
  else
    self:Expand(tree, node)
  end
end

function DebugTree:In(tree)
  local node = tree:get_node()
  if not node then return false end
  
  -- Move to first child if available
  if node:has_children() and node:is_expanded() then
    local child_ids = node:get_child_ids()
    if child_ids and child_ids[1] then
      self:setCursorToNode(tree, child_ids[1])
      return true
    end
  end
  return false
end

function DebugTree:Out(tree)
  local node = tree:get_node()
  if not node then return false end
  
  local parent_id = node:get_parent_id()
  if parent_id then
    self:setCursorToNode(tree, parent_id)
    return true
  end
  return false
end

-- Focus Management Methods

function DebugTree:FocusIn(tree, popup)
  local node = tree:get_node()
  if not node then return end
  
  -- Store original roots if not already stored
  if not tree._original_root_ids then
    tree._original_root_ids = vim.deepcopy(tree._view_root_ids)
  end
  
  -- Focus on this node by making it the only root
  tree._view_root_ids = { node:get_id() }
  tree.nodes.root_ids = tree._view_root_ids
  
  -- Update popup title to show focus
  if popup then
    local title = " DebugTree - Focused: " .. (node.text or "Unknown") .. " "
    popup.border:set_text("top", title, "center")
  end
  
  tree:render()
end

function DebugTree:FocusOut(tree, popup, original_title)
  if tree._original_root_ids then
    tree._view_root_ids = tree._original_root_ids
    tree.nodes.root_ids = tree._view_root_ids
    tree._original_root_ids = nil
    
    -- Restore original title
    if popup and original_title then
      popup.border:set_text("top", " " .. original_title .. " ", "center")
    end
    
    tree:render()
  end
end

function DebugTree:FocusTop(tree, popup, original_title)
  -- Reset to original view roots
  if tree._original_root_ids then
    tree._view_root_ids = tree._original_root_ids
    tree._original_root_ids = nil
  end
  
  -- Use the default root ids for this view
  tree.nodes.root_ids = tree._view_root_ids
  
  if popup and original_title then
    popup.border:set_text("top", " " .. original_title .. " ", "center")
  end
  
  tree:render()
end

-- Composite Navigation Methods

function DebugTree:Open(tree)
  local node = tree:get_node()
  if not node then return end
  
  -- First expand the node
  self:Expand(tree, node)
  
  -- Then move into it
  vim.schedule(function()
    self:In(tree)
  end)
end

function DebugTree:Close(tree)
  local node = tree:get_node()
  if not node then return end
  
  -- If node is expanded, just collapse it
  if node:is_expanded() then
    self:Collapse(tree, node)
  else
    -- Otherwise, go out and collapse parent
    local parent_id = node:get_parent_id()
    if parent_id then
      self:Out(tree)
      local parent = tree.nodes.by_id[parent_id]
      if parent then
        self:Collapse(tree, parent)
      end
    end
  end
end

function DebugTree:Up(tree)
  -- Try previous sibling first, then parent
  if self:PreviousSibling(tree) then return end
  self:Out(tree)
end

function DebugTree:Down(tree)
  -- Try: child -> next sibling -> parent's next sibling (recursively)
  if self:In(tree) then return end
  if self:NextSibling(tree) then return end
  
  -- Go up until we find a parent with a next sibling
  while self:Out(tree) do
    if self:NextSibling(tree) then return end
  end
end

-- Resolve lazy variable by fetching its actual value
function DebugTree:resolveLazyVariable(node, view_tree)
  local variable = node._dap
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
