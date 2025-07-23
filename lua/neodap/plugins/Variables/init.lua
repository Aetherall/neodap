-- Direct NUI Implementation for Variables Plugin
-- This is a proof of concept showing how simple it would be

local Class = require('neodap.tools.class')
local NuiSplit = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local IdGenerator = require('neodap.plugins.Variables.id_generator')
local VisualImprovements = require('neodap.plugins.Variables.visual_improvements')
local BreadcrumbNav = require('neodap.plugins.Variables.breadcrumb_navigation')

---@class VariablesTreeNuiProps
---@field api Api
---@field current_frame? Frame
---@field windows table<number, {split: NuiSplit, tree: NuiTree}>
---@field breadcrumb_mode boolean
---@field breadcrumb BreadcrumbNav?

---@class VariablesTreeNui: VariablesTreeNuiProps
---@field new Constructor<VariablesTreeNuiProps>
local VariablesTreeNui = Class()

VariablesTreeNui.name = "Variables"

---@param api Api
---@return VariablesTreeNui
function VariablesTreeNui.create(api)
  local instance = VariablesTreeNui:new({
    api = api,
    current_frame = nil,
    windows = {},
    breadcrumb_mode = false,
    breadcrumb = nil,
  })

  instance:init()
  return instance
end

function VariablesTreeNui.plugin(api)
  return VariablesTreeNui.create(api)
end

function VariablesTreeNui:init()
  -- Initialize breadcrumb navigation
  self.breadcrumb = BreadcrumbNav.create(self)
  self.breadcrumb_mode = false

  -- Setup DAP event handlers
  self:setupEventHandlers()

  -- Create user commands
  self:setupCommands()
end

function VariablesTreeNui:setupEventHandlers()
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function()
        local stack = thread:stack()
        self.current_frame = stack and stack:top() or nil
        self:RefreshAllWindows()
      end)

      thread:onContinued(function()
        self.current_frame = nil
        self:RefreshAllWindows()
      end)
    end)
  end)
end

function VariablesTreeNui:setupCommands()
  vim.api.nvim_create_user_command("VariablesShow", function()
    self:Show()
  end, { desc = "Show variables window" })

  vim.api.nvim_create_user_command("VariablesClose", function()
    self:Close()
  end, { desc = "Close variables window" })

  vim.api.nvim_create_user_command("VariablesToggle", function()
    self:Toggle()
  end, { desc = "Toggle variables window" })

  vim.api.nvim_create_user_command("VariablesBreadcrumb", function()
    self:ToggleBreadcrumbMode()
  end, { desc = "Toggle breadcrumb navigation mode" })
end

function VariablesTreeNui:Show()
  local tabpage = vim.api.nvim_get_current_tabpage()

  -- Check if already open
  local win = self.windows[tabpage]
  if win and vim.api.nvim_win_is_valid(win.split.winid) then
    vim.api.nvim_set_current_win(win.split.winid)
    return
  end

  -- Create split window
  local split = NuiSplit({
    relative = "editor",
    position = "left",
    size = "30%",
    buf_options = {
      buftype = "nofile",
      bufhidden = "hide",
      swapfile = false,
      modifiable = false,
    },
    win_options = {
      wrap = false,      -- Disable line wrapping
      linebreak = false,
      cursorline = true, -- Highlight current line
      number = false,
      relativenumber = false,
      sidescrolloff = 5, -- Keep 5 columns visible when scrolling horizontally
      scrolloff = 3,     -- Keep 3 lines visible when scrolling vertically
    },
  })

  split:mount()

  -- Create tree
  local tree = NuiTree({
    bufnr = split.bufnr,
    nodes = self:getRootNodes(),
    get_node_id = function(node) return node.id end,
    prepare_node = function(node)
      return self:prepareNodeLine(node)
    end,
  })

  -- Setup keybindings
  self:setupKeybindings(split, tree)

  -- Store reference
  self.windows[tabpage] = {
    split = split,
    tree = tree,
  }

  -- Initial render
  tree:render()

  -- Set buffer name for display
  vim.api.nvim_buf_set_name(split.bufnr, "Variables")
end

function VariablesTreeNui:setupKeybindings(split, tree)
  local map = function(key, fn, desc)
    vim.keymap.set("n", key, fn, {
      buffer = split.bufnr,
      nowait = true,
      silent = true,
      desc = desc or ""
    })
  end

  if self.breadcrumb_mode then
    -- Breadcrumb mode keybindings
    self.breadcrumb:setupKeybindings(split, tree)
  else
    -- Standard tree mode keybindings
    map("<CR>", function() self:ToggleNode(tree) end, "Toggle node")
    map("o", function() self:ToggleNode(tree) end, "Toggle node")
    map("<Space>", function() self:ToggleNode(tree) end, "Toggle node")
  end

  -- Common keybindings for both modes
  map("q", function() self:Close() end, "Close variables")
  map("B", function() self:ToggleBreadcrumbMode() end, "Toggle breadcrumb mode")

  -- Auto-close on leave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = split.bufnr,
    callback = function()
      -- Optional: auto-close on leave
      -- self:close()
    end,
  })
end

function VariablesTreeNui:prepareNodeLine(node)
  -- Use the enhanced visual improvements
  return VisualImprovements.prepareNodeLine(node, {
    useTreeGuides = true -- Enable tree guides for better depth perception
  })
end

function VariablesTreeNui:ToggleNode(tree)
  local node = tree:get_node()
  if not node then return end

  if not node.loaded or node:has_children() then
    if node:is_expanded() then
      node:collapse()
    else
      -- Load children if needed
      if not node.loaded then
        self:loadNodeChildren(tree, node)
        node.loaded = true
      end
      node:expand()

      -- Auto-scroll to ensure visibility after expansion
      self:ensureNodeVisibility(tree, node)
    end
    tree:render()
  end
end

function VariablesTreeNui:loadNodeChildren(tree, node)
  if not self.current_frame then
    return
  end

  local children = {}

  -- Load based on node type
  if node.type == "scope" then
    -- Load variables for scope
    local variables = self.current_frame:variables(node.variablesReference)
    if variables then
      for _, var in ipairs(variables) do
        table.insert(children, self:createVariableNode(var, node.id))
      end
    end
  elseif node.type == "variable" and node.variableReference then
    -- Load child variables
    local variables = self.current_frame:variables(node.variableReference)
    if variables then
      for _, var in ipairs(variables) do
        table.insert(children, self:createVariableNode(var, node.id))
      end
    end
  end

  -- Add children to tree
  tree:set_nodes(children, node.id)

  -- After loading children, ensure visibility if needed
  vim.defer_fn(function()
    self:ensureNodeVisibility(tree, node)
  end, 50)
end

function VariablesTreeNui:createVariableNode(var, parent_id)
  -- Check if this is an array index
  local index = tonumber("0" .. var.name)
  local id = IdGenerator.forVariable(parent_id, var, index)
  local is_expandable = var.variablesReference and var.variablesReference > 0

  -- For expandable items, we'll fetch preview data asynchronously
  local node = NuiTree.Node({
    id = id,
    name = var.name,                              -- PURE variable name for navigation
    text = VisualImprovements.formatVariableDisplay(var),  -- Formatted display text
    type = "variable",
    varType = var.type, -- Store for icon selection
    is_expandable = is_expandable,
    variableReference = var.variablesReference,
    variable = var,               -- Store the variable for preview updates
    preview = nil,                -- Will be populated by FetchPreviewData
    loaded = false,
  }, is_expandable and {} or nil) -- Empty children if expandable

  -- Fetch preview data for expandable items (after a small delay to let UI render)
  if is_expandable and self.current_frame and (var.type == "Object" or var.type == "Array") then
    vim.defer_fn(function()
      self:FetchPreviewData(node, var, parent_id)
    end, 100)
  end

  return node
end

-- Deprecated: Use VisualImprovements.formatVariableDisplay instead
function VariablesTreeNui:formatVariable(var)
  return VisualImprovements.formatVariableDisplay(var)
end

function VariablesTreeNui:getRootNodes()
  if not self.current_frame then
    return {
      NuiTree.Node({
        id = "no-debug",
        name = "No active debug session",
        text = "No active debug session",
        type = "info",
      })
    }
  end

  local nodes = {}
  local scopes = self.current_frame:scopes()
  if scopes then
    for _, scope in ipairs(scopes) do
      local id = IdGenerator.forScope(scope.ref)
      local node = NuiTree.Node({
        id = id,
        name = scope.ref.name,
        text = scope.ref.name,
        type = "scope",
        variablesReference = scope.ref.variablesReference,
        expensive = scope.ref.expensive,
        loaded = false,
      }, {}) -- Empty children, will load on expand

      table.insert(nodes, node)
    end
  end

  return nodes
end

function VariablesTreeNui:RefreshAllWindows()
  for tabpage, win in pairs(self.windows) do
    if vim.api.nvim_tabpage_is_valid(tabpage) and
        vim.api.nvim_win_is_valid(win.split.winid) then
      if self.breadcrumb_mode then
        -- Use breadcrumb navigation refresh
        self.breadcrumb:RefreshView(tabpage)
      else
        -- Standard tree refresh
        local nodes = self:getRootNodes()
        win.tree = NuiTree({
          bufnr = win.split.bufnr,
          nodes = nodes,
          get_node_id = function(node) return node.id end,
          prepare_node = function(node)
            return self:prepareNodeLine(node)
          end,
        })
        win.tree:render()
        -- Update keybindings for standard mode
        self:setupKeybindings(win.split, win.tree)
      end
    else
      -- Clean up invalid windows
      self.windows[tabpage] = nil
    end
  end
end

function VariablesTreeNui:ToggleBreadcrumbMode()
  self.breadcrumb_mode = not self.breadcrumb_mode

  if self.breadcrumb_mode then
    -- Switch to breadcrumb mode
    self.breadcrumb:initialize()
  else
    -- Switch back to tree mode - cleanup breadcrumb splits
    self.breadcrumb:cleanup()
  end

  -- Refresh all windows with new mode
  self:RefreshAllWindows()

  -- Show mode status
  local mode_text = self.breadcrumb_mode and "Breadcrumb" or "Tree"
  vim.notify("Variables navigation: " .. mode_text .. " mode", vim.log.levels.INFO)
end

function VariablesTreeNui:Close()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local win = self.windows[tabpage]

  if win then
    -- Close breadcrumb split if it exists
    if self.breadcrumb_mode then
      self.breadcrumb:closeBreadcrumbSplit(tabpage)
    end
    
    win.split:unmount()
    self.windows[tabpage] = nil
  end
end

function VariablesTreeNui:Toggle()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local win = self.windows[tabpage]

  if win and vim.api.nvim_win_is_valid(win.split.winid) then
    self:Close()
  else
    self:Show()
  end
end

function VariablesTreeNui:ensureNodeVisibility(tree, node)
  -- Get the current window and buffer
  local tabpage = vim.api.nvim_get_current_tabpage()
  local win = self.windows[tabpage]
  if not win or not vim.api.nvim_win_is_valid(win.split.winid) then
    return
  end

  local winid = win.split.winid
  local bufnr = win.split.bufnr

  -- Get window dimensions
  local win_height = vim.api.nvim_win_get_height(winid)
  local cursor_pos = vim.api.nvim_win_get_cursor(winid)
  local current_line = cursor_pos[1]

  -- Calculate the node's depth and potential expanded size
  local node_depth = node:get_depth()
  local estimated_child_count = self:estimateChildCount(node)

  -- Calculate where the expanded content will end
  local content_end_line = current_line + estimated_child_count

  -- Get current window view
  local win_view = vim.fn.winsaveview()
  local topline = win_view.topline
  local botline = topline + win_height - 1

  -- Determine if we need to adjust the view
  if content_end_line > botline then
    -- Content will extend below visible area
    -- Calculate optimal scroll position based on depth
    local offset = self:calculateScrollOffset(node_depth, estimated_child_count, win_height)

    -- Set new view position
    local new_topline = math.max(1, current_line - offset)
    vim.api.nvim_win_set_cursor(winid, { current_line, 0 })
    vim.api.nvim_command(string.format("normal! %dzt", offset))
  elseif current_line < topline + 3 then
    -- Node is too close to top, ensure some context above
    local new_topline = math.max(1, current_line - 3)
    vim.api.nvim_win_call(winid, function()
      vim.cmd(string.format("normal! %dgg", new_topline))
      vim.cmd("normal! zt")
      vim.api.nvim_win_set_cursor(0, { current_line, 0 })
    end)
  end
end

function VariablesTreeNui:estimateChildCount(node)
  -- Estimate based on node type and available information
  if node.type == "scope" then
    -- Scopes typically have multiple variables
    return 10 -- Conservative estimate
  elseif node.variable then
    local var = node.variable
    -- Try to extract count from value
    if var.type == "Array" then
      local count = var.value and var.value:match("%((%d+)%)") or var.value:match("Array%[(%d+)%]")
      return count and math.min(tonumber(count), 20) or 5
    elseif var.type == "Object" then
      local count = var.value and var.value:match("%((%d+)%)") or var.value:match("{(%d+)}")
      return count and math.min(tonumber(count), 15) or 5
    end
  end
  -- Default for unknown expandable nodes
  return 5
end

function VariablesTreeNui:calculateScrollOffset(depth, child_count, win_height)
  -- Calculate optimal offset based on depth and content size
  -- Deeper nodes get more aggressive scrolling to show their context

  -- Base offset: try to show parent and some children
  local base_offset = 3

  -- Adjust for depth (deeper = more offset)
  local depth_factor = math.min(depth * 2, 10)

  -- Adjust for content size
  local content_factor = 0
  if child_count > win_height * 0.5 then
    -- Large content: position near top to maximize visible children
    content_factor = 5
  elseif child_count > win_height * 0.3 then
    -- Medium content: balanced positioning
    content_factor = 3
  end

  -- Calculate final offset
  local offset = base_offset + depth_factor + content_factor

  -- Ensure we don't scroll too much (keep at least 1/4 of window for context)
  return math.min(offset, math.floor(win_height * 0.75))
end

function VariablesTreeNui:FetchPreviewData(node, var, parent_id)
  if not self.current_frame or not var.variablesReference then
    return
  end

  -- Fetch first few children for preview
  local variables = self.current_frame:variables(var.variablesReference)
  if variables then
    -- Create preview data with first few items
    local previewItems = {}
    local maxItems = 3 -- Show first 3 items in preview

    for i, childVar in ipairs(variables) do
      if i > maxItems then
        table.insert(previewItems, "...")
        break
      end

      -- Format preview item
      local itemText
      if var.type == "Array" then -- Check parent type
        -- For arrays, just show the value
        itemText = VisualImprovements.formatValue(childVar.value, childVar.type, 15)
      else
        -- For objects, show key: value
        itemText = childVar.name .. ": " .. VisualImprovements.formatValue(childVar.value, childVar.type, 15)
      end

      table.insert(previewItems, itemText)
    end

    -- Update node display with preview
    if #previewItems > 0 then
      local preview
      if var.type == "Array" then
        preview = "[" .. table.concat(previewItems, ", ") .. "]"
      else
        preview = "{" .. table.concat(previewItems, ", ") .. "}"
      end

      -- Store preview separately and update display text only
      node.preview = preview
      var.preview = preview  -- Also update the variable for consistency
      node.text = VisualImprovements.formatVariableDisplay(var)
      -- node.name stays as pure variable name for navigation!

      -- Re-render if we have a window
      for _, win in pairs(self.windows) do
        if win.tree then
          win.tree:render()
          break
        end
      end
    end
  end
end

return VariablesTreeNui
