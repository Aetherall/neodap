--- Emoji icon set for neodap tree UI.
---
--- Uses emoji and Unicode symbols instead of Nerd Font icons.
--- No special font required - works in any terminal with emoji support.
---
--- Note: Emojis are typically 2 cells wide in terminals, so entity lines
--- will be slightly wider than with the default Nerd Font icons.
---
--- Usage:
---   neodap.use("neodap.plugins.tree_buffer", { icon_set = "emoji" })

return {
  icons = {
    -- Structural (single-width Unicode, keeps alignment tight)
    collapsed = "▸", expanded = "▾", leaf = " ",

    -- Entity type icons (emojis)
    Debugger = "🐛",
    Session = "⚡",
    Thread = "🧵",
    Stack = "📚",
    Frame = "📍",
    Scope = "🔍",
    Variable = "💎",
    Breakpoint = "🔴",
    BreakpointBinding = "🔴",
    ExceptionFilter = "⚠️",
    ExceptionFilterBinding = "⚠️",
    Stdio = "💬",
    Output = "💬",
    Config = "⚙️",
    Configs = "⚙️",
    Sessions = "⚡",
    Threads = "🧵",
    Breakpoints = "🔴",
    Targets = "🎯",
    ExceptionFilters = "⚠️",
    ExceptionFiltersGroup = "⚠️",
    ExceptionFilterBindings = "⚠️",
  },
  var_type_icons = {
    string   = { icon = "📝", hl = "DapVarIconString" },
    number   = { icon = "🔢", hl = "DapVarIconNumber" },
    boolean  = { icon = "✅", hl = "DapVarIconBoolean" },
    array    = { icon = "📋", hl = "DapVarIconArray" },
    object   = { icon = "📦", hl = "DapVarIconObject" },
    ["function"] = { icon = "⚡", hl = "DapVarIconFunction" },
    null     = { icon = "❌", hl = "DapVarIconNull" },
  },
}
