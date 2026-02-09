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
    Sessions = "", Targets = "", Output = "", Config = "", Configs = "",
  },
  guide_highlights = {
    vertical = "DapTreeGuideVertical", corner = "DapTreeGuideCorner",
    junction = "DapTreeGuideJunction", expanded = "DapTreeExpanded",
    collapsed = "DapTreeCollapsed",
  },
  keybinds = {},
  layouts = {},
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
  DapTreeCollapsed = { link = "Directory" },
  -- Frame depth-cycling (overrides default=true from presentation/init.lua)
  DapFrameLabel = { fg = "#585b70", italic = true },
  DapFrameSubtle = { fg = "#6c7086" },
  DapFrame0 = { fg = "#89dceb" },
  DapFrame1 = { fg = "#74c7ec" },
  DapFrame2 = { fg = "#5fb3d9" },
  DapFrame3 = { fg = "#4a9fc6" },
  DapFrame4 = { fg = "#358bb3" },
  DapFrameFocused = { fg = "#a6e3a1" },
  -- Source presentationHint (overrides default=true from presentation/init.lua)
  DapSourceUser = { fg = "#a6adc8" },
  DapSourceNormal = { link = "Comment" },
  DapSourceInternal = { fg = "#45475a", italic = true },
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
