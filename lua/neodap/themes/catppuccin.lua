--- Catppuccin Mocha theme for neodap tree UI.
---
--- Usage:
---   neodap.use("neodap.plugins.tree_buffer", { theme = "catppuccin" })

return {
  highlights = {
    -- Expand/collapse chevron icons
    DapTreeExpanded = { fg = "#a6adc8" },   -- Subtext0
    DapTreeCollapsed = { fg = "#585b70" },  -- Surface2

    -- Per-type entity icon highlights
    DapTreeIconDebugger = { fg = "#cba6f7" },   -- Mauve
    DapTreeIconSession = { fg = "#89b4fa" },    -- Blue
    DapTreeIconThread = { fg = "#a6e3a1" },     -- Green
    DapTreeIconStack = { fg = "#74c7ec" },      -- Sapphire
    DapTreeIconFrame = { fg = "#89dceb" },      -- Sky
    DapTreeIconScope = { fg = "#f9e2af" },      -- Yellow
    DapTreeIconVariable = { fg = "#fab387" },   -- Peach
    DapTreeIconBreakpoint = { fg = "#f38ba8" }, -- Red
    DapTreeIconException = { fg = "#eba0ac" },  -- Maroon
    DapTreeIconOutput = { fg = "#94e2d5" },     -- Teal
    DapTreeIconConfig = { fg = "#b4befe" },     -- Lavender

    -- Variable type icon highlights
    DapVarIconString = { fg = "#a6e3a1" },      -- Green
    DapVarIconNumber = { fg = "#fab387" },      -- Peach
    DapVarIconBoolean = { fg = "#f9e2af" },     -- Yellow
    DapVarIconArray = { fg = "#89dceb" },       -- Sky
    DapVarIconObject = { fg = "#cba6f7" },      -- Mauve
    DapVarIconFunction = { fg = "#89b4fa" },    -- Blue
    DapVarIconNull = { fg = "#6c7086" },        -- Overlay1

    -- Frame depth-cycling
    DapFrameLabel = { fg = "#585b70", italic = true },  -- Surface2
    DapFrameSubtle = { fg = "#6c7086" },                -- Overlay1
    DapFrame0 = { fg = "#89dceb" },   -- Sky
    DapFrame1 = { fg = "#74c7ec" },   -- Sapphire
    DapFrame2 = { fg = "#5fb3d9" },
    DapFrame3 = { fg = "#4a9fc6" },
    DapFrame4 = { fg = "#358bb3" },
    DapFrameFocused = { fg = "#a6e3a1" },  -- Green

    -- Source presentationHint
    DapSourceUser = { fg = "#a6adc8" },              -- Subtext0
    DapSourceNormal = { fg = "#6c7086" },            -- Overlay1
    DapSourceInternal = { fg = "#45475a", italic = true }, -- Surface1
  },
}
