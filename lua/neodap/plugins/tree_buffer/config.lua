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
    collapsed = "○", expanded = "◉", leaf = " ",
    vertical = "╎", horizontal = " ", corner = "╰", junction = "├",
    Session = "", Thread = "", Stack = "󰆧", Frame = "",
    Scope = "", Variable = "", Debugger = "", Breakpoint = "",
    BreakpointBinding = "", Stdio = "", Threads = "", Breakpoints = "",
    Sessions = "", Targets = "", Output = "",
  },
  guide_highlights = {
    vertical = "DapTreeGuideVertical", corner = "DapTreeGuideCorner",
    junction = "DapTreeGuideJunction", expanded = "DapTreeExpanded",
    collapsed = "DapTreeCollapsed",
  },
  keybinds = {},
}

local highlights = {
  DapTreeDebugger = { link = "Title" },
  DapTreeSession = { link = "Type" },
  DapTreeThread = { link = "Function" },
  DapTreeStack = { link = "Identifier" },
  DapTreeFrame = { link = "String" },
  DapTreeScope = { link = "Keyword" },
  DapTreeVariable = { link = "Identifier" },
  DapTreeSource = { link = "Directory" },
  DapTreeBreakpoint = { link = "Error" },
  DapTreeBinding = { link = "WarningMsg" },
  DapTreeOutput = { link = "Comment" },
  DapTreeExpression = { link = "Identifier" },
  DapTreeGroup = { link = "Directory" },
  DapTreeCount = { link = "Number" },
  DapTreeType = { link = "Type" },
  DapTreeValue = { link = "String" },
  DapTreeCategory = { link = "Label" },
  DapTreePunctuation = { link = "Delimiter" },
  DapTreeState = { link = "Comment" },
  DapTreeStopped = { link = "WarningMsg" },
  DapTreeRunning = { link = "DiffAdd" },
  DapTreeCurrent = { link = "Special" },
  DapTreeFocused = { link = "CursorLine" },
  DapTreeIcon = { link = "Special" },
  DapTreeLineNum = { link = "LineNr" },
  DapTreeDepth = { link = "Comment" },
  DapTreeGuideVertical = { link = "Comment" },
  DapTreeGuideCorner = { link = "Comment" },
  DapTreeGuideJunction = { link = "Comment" },
  DapTreeExpanded = { link = "Directory" },
  DapTreeCollapsed = { link = "Directory" },
}

local function setup_highlights()
  -- Sort keys for deterministic highlight ID assignment (affects screenshot tests)
  local names = vim.tbl_keys(highlights)
  table.sort(names)
  for _, name in ipairs(names) do
    vim.api.nvim_set_hl(0, name, highlights[name])
  end
end

return {
  default = default,
  highlights = highlights,
  setup_highlights = setup_highlights,
  frame_colors = frame_colors,
}
