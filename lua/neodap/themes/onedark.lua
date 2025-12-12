--- One Dark theme for neodap tree UI.
---
--- Based on Atom's One Dark color palette.
---
--- Usage:
---   neodap.use("neodap.plugins.tree_buffer", { theme = "onedark" })

return {
  highlights = {
    -- Expand/collapse chevron icons
    DapTreeExpanded = { fg = "#abb2bf" },   -- Foreground
    DapTreeCollapsed = { fg = "#5c6370" },  -- Comment grey

    -- Per-type entity icon highlights
    DapTreeIconDebugger = { fg = "#c678dd" },   -- Purple
    DapTreeIconSession = { fg = "#61afef" },    -- Blue
    DapTreeIconThread = { fg = "#98c379" },     -- Green
    DapTreeIconStack = { fg = "#56b6c2" },      -- Cyan
    DapTreeIconFrame = { fg = "#61afef" },      -- Blue
    DapTreeIconScope = { fg = "#e5c07b" },      -- Yellow
    DapTreeIconVariable = { fg = "#d19a66" },   -- Dark yellow / Orange
    DapTreeIconBreakpoint = { fg = "#e06c75" }, -- Red
    DapTreeIconException = { fg = "#be5046" },  -- Dark red
    DapTreeIconOutput = { fg = "#56b6c2" },     -- Cyan
    DapTreeIconConfig = { fg = "#c678dd" },     -- Purple

    -- Variable type icon highlights
    DapVarIconString = { fg = "#98c379" },      -- Green
    DapVarIconNumber = { fg = "#d19a66" },      -- Dark yellow / Orange
    DapVarIconBoolean = { fg = "#e5c07b" },     -- Yellow
    DapVarIconArray = { fg = "#56b6c2" },       -- Cyan
    DapVarIconObject = { fg = "#c678dd" },      -- Purple
    DapVarIconFunction = { fg = "#61afef" },    -- Blue
    DapVarIconNull = { fg = "#5c6370" },        -- Comment grey

    -- Frame depth-cycling
    DapFrameLabel = { fg = "#5c6370", italic = true },  -- Comment grey
    DapFrameSubtle = { fg = "#636d83" },
    DapFrame0 = { fg = "#61afef" },   -- Blue
    DapFrame1 = { fg = "#56a0d8" },
    DapFrame2 = { fg = "#4b91c1" },
    DapFrame3 = { fg = "#4082aa" },
    DapFrame4 = { fg = "#357393" },
    DapFrameFocused = { fg = "#98c379" },  -- Green

    -- Source presentationHint
    DapSourceUser = { fg = "#abb2bf" },                -- Foreground
    DapSourceNormal = { fg = "#636d83" },
    DapSourceInternal = { fg = "#4b5263", italic = true },
  },
}
