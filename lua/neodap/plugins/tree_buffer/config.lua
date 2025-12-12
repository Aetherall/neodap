-- Tree buffer configuration and highlights

-- Frame highlight color palettes (Catppuccin-inspired)
local frame_colors = {
  context = { fg = "#a6e3a1", bg = "#1e3a1e" },
  blues = {
    [0] = { fg = "#89dceb", bg = "#1e4a5c" },
    [1] = { fg = "#74c7ec", bg = "#1a3f4d" },
    [2] = { fg = "#5fb3d9", bg = "#16343f" },
    [3] = { fg = "#4a9fc6", bg = "#122931" },
    [4] = { fg = "#358bb3", bg = "#0e1e23" },
  },
  purples = {
    [0] = { fg = "#f5c2e7", bg = "#4a2040" },
    [1] = { fg = "#dda8d3", bg = "#3d1a36" },
    [2] = { fg = "#c58ebf", bg = "#30142c" },
    [3] = { fg = "#ad74ab", bg = "#230e22" },
    [4] = { fg = "#955a97", bg = "#160818" },
  },
}

local default = {
  indent = 2,
  show_root = false, -- Show root node (Debugger, Session, etc.) - hidden by default
  icons = {
    collapsed = "", expanded = "", leaf = " ",
    vertical = "│", horizontal = " ", corner = "╰", junction = "├",
    Session = "", Thread = "", Stack = "󰆧", Frame = "",
    Scope = "", Variable = "", Debugger = "", Breakpoint = "",
    BreakpointBinding = "", Stdio = "", Threads = "", Breakpoints = "",
    Sessions = "", Targets = "", Output = "", Config = "", Configs = "",
    ExceptionFilter = "", ExceptionFilterBinding = "",
    ExceptionFilters = "", ExceptionFiltersGroup = "",
    ExceptionFilterBindings = "",
  },
  -- Per-type highlight groups for entity icons in the tree
  -- Set a type to false to use the generic "DapTreeIcon" fallback
  icon_highlights = {
    Session = "DapTreeIconSession",
    Thread = "DapTreeIconThread",
    Stack = "DapTreeIconStack",
    Frame = "DapTreeIconFrame",
    Scope = "DapTreeIconScope",
    Variable = "DapTreeIconVariable",
    Breakpoint = "DapTreeIconBreakpoint",
    BreakpointBinding = "DapTreeIconBreakpoint",
    ExceptionFilter = "DapTreeIconException",
    ExceptionFilterBinding = "DapTreeIconException",
    ExceptionFilters = "DapTreeIconException",
    ExceptionFiltersGroup = "DapTreeIconException",
    ExceptionFilterBindings = "DapTreeIconException",
    Stdio = "DapTreeIconOutput",
    Output = "DapTreeIconOutput",
    Debugger = "DapTreeIconDebugger",
    Threads = "DapTreeIconThread",
    Breakpoints = "DapTreeIconBreakpoint",
    Sessions = "DapTreeIconSession",
    Targets = "DapTreeIconSession",
    Config = "DapTreeIconConfig",
    Configs = "DapTreeIconConfig",
  },
  guide_highlights = {
    vertical = "DapTreeGuideVertical", corner = "DapTreeGuideCorner",
    junction = "DapTreeGuideJunction", expanded = "DapTreeExpanded",
    collapsed = "DapTreeCollapsed",
  },
  -- Variable type icons: category -> { icon, hl }
  -- Variables get a type-specific icon instead of the generic  icon.
  -- Type classification is automatic (see classify_var_type).
  -- Set a category to false to fall back to the generic Variable icon.
  var_type_icons = {
    string   = { icon = "󰀬", hl = "DapVarIconString" },
    number   = { icon = "", hl = "DapVarIconNumber" },
    boolean  = { icon = "◩", hl = "DapVarIconBoolean" },
    array    = { icon = "", hl = "DapVarIconArray" },
    object   = { icon = "", hl = "DapVarIconObject" },
    ["function"] = { icon = "󰊕", hl = "DapVarIconFunction" },
    null     = { icon = "󰟢", hl = "DapVarIconNull" },
  },
  -- Theme: string (built-in name), table (custom theme), or nil/false (no theme).
  -- Built-in themes: "catppuccin", "onedark", "links"
  -- No theme (nil/false): uses link-based highlights that follow your colorscheme.
  theme = nil,
  -- Icon set: string (built-in name), table (custom), or nil/false (use defaults).
  -- Built-in icon sets: "nerd" (default), "emoji" (no special font needed)
  icon_set = nil,
  keybinds = {},
  layouts = {},
  components = {},   -- User component overrides: { [name] = { [entity_type] = fn } }
  highlights = {},   -- User highlight overrides: { [group_name] = { fg = ..., ... } }
}

local highlights = {
  -- Tree-structural highlights
  DapTreeDebugger = { link = "Title" },
  DapTreeStack = { link = "Identifier" },
  DapTreeGroup = { link = "Directory" },
  DapTreeCount = { link = "Number" },
  DapTreePunctuation = { link = "Delimiter" },
  DapTreeFocused = { link = "CursorLine" },
  DapTreeIcon = { link = "Special" },
  DapTreeDepth = { link = "Comment" },
  DapTreeGuideVertical = { link = "Comment" },
  DapTreeGuideCorner = { link = "Comment" },
  DapTreeGuideJunction = { link = "Comment" },
  DapTreeExpanded = { link = "Directory" },
  DapTreeCollapsed = { link = "Comment" },
  -- Per-type entity icon highlights (link-based, follows colorscheme)
  -- Use theme = "catppuccin" or "onedark" for hardcoded colors.
  DapTreeIconDebugger = { link = "Special" },
  DapTreeIconSession = { link = "Function" },
  DapTreeIconThread = { link = "String" },
  DapTreeIconStack = { link = "Type" },
  DapTreeIconFrame = { link = "Identifier" },
  DapTreeIconScope = { link = "Keyword" },
  DapTreeIconVariable = { link = "Constant" },
  DapTreeIconBreakpoint = { link = "DiagnosticError" },
  DapTreeIconException = { link = "DiagnosticWarn" },
  DapTreeIconOutput = { link = "Type" },
  DapTreeIconConfig = { link = "Special" },
  -- Variable type icon highlights (link-based, follows colorscheme)
  DapVarIconString = { link = "String" },
  DapVarIconNumber = { link = "Number" },
  DapVarIconBoolean = { link = "Boolean" },
  DapVarIconArray = { link = "Type" },
  DapVarIconObject = { link = "Structure" },
  DapVarIconFunction = { link = "Function" },
  DapVarIconNull = { link = "Comment" },
  -- Frame depth-cycling (link-based defaults)
  DapFrameLabel = { link = "Comment" },
  DapFrameSubtle = { link = "Comment" },
  DapFrame0 = { link = "Identifier" },
  DapFrame1 = { link = "Identifier" },
  DapFrame2 = { link = "Identifier" },
  DapFrame3 = { link = "Identifier" },
  DapFrame4 = { link = "Identifier" },
  DapFrameFocused = { link = "String" },
  -- Source presentationHint (link-based defaults)
  DapSourceUser = { link = "Normal" },
  DapSourceNormal = { link = "Comment" },
  DapSourceInternal = { link = "Comment" },
  -- Help float
  DapHelpKey = { link = "Special", default = true },
  DapHelpSection = { link = "Title", default = true },
}

--- Apply highlight groups, with optional user overrides
---@param user_highlights? table<string, table> User highlight overrides (applied after defaults)
local function setup_highlights(user_highlights)
  -- Merge user highlights over defaults
  local effective = highlights
  if user_highlights and next(user_highlights) then
    effective = vim.tbl_deep_extend("force", highlights, user_highlights)
  end
  -- Sort keys for deterministic highlight ID assignment (affects screenshot tests)
  local names = vim.tbl_keys(effective)
  table.sort(names)
  for _, name in ipairs(names) do
    vim.api.nvim_set_hl(0, name, effective[name])
  end
end

return {
  default = default,
  highlights = highlights,
  setup_highlights = setup_highlights,
  frame_colors = frame_colors,
}
