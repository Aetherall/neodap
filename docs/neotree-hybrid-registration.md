# Neo-tree Hybrid Self-Registration Architecture

## Overview

The hybrid self-registration approach allows the NeodapNeotreeVariableSource plugin to automatically integrate with Neo-tree while respecting user preferences and configurations. This document explores the design, implementation, trade-offs, and edge cases of this approach.

## Core Concept

The plugin intelligently decides whether to auto-configure itself based on whether the user has already explicitly configured it in their Neo-tree setup.

```lua
-- Simplified logic flow
if user_has_configured_neodap_source then
  -- Respect user configuration, just register the source
  manager.register(NeodapNeotreeVariableSource)
else
  -- Auto-configure with sensible defaults
  manager.register(NeodapNeotreeVariableSource)
  neotree.setup(enhanced_config_with_defaults)
end
```

## Implementation Strategy

### 1. Detection Logic

**How we detect if user has configured us:**

```lua
local config = neotree.get_config() or {}
local sources = config.sources or {}
local user_has_configured_us = vim.tbl_contains(sources, self.name)
```

**Assumptions:**
- If the source name appears in `config.sources`, user has explicitly configured it
- If not, we assume zero configuration and auto-setup

### 2. Default Configuration

**Sensible defaults for zero-config experience:**

```lua
[self.name] = {
  window = {
    position = "float",
    mappings = {
      ["<cr>"] = "toggle_node",
      ["<space>"] = "toggle_node", 
      ["o"] = "toggle_node",
      ["q"] = "close_window",
      ["<esc>"] = "close_window",
    },
  },
  popup = {
    size = { height = "60%", width = "50%" },
    position = "50%", -- center
  },
}
```

**Rationale:**
- **Floating window**: Less intrusive than sidebar, works well for debugging
- **Reasonable size**: 60% height, 50% width - visible but not overwhelming
- **Standard keymaps**: Familiar Neo-tree navigation patterns
- **Easy exit**: Both `q` and `<esc>` to close

### 3. Timing and Lifecycle

**When registration happens:**
```lua
function NeodapNeotreeVariableSource:init()
  -- ... other initialization ...
  self:setupNeotreeIntegration()  -- Immediate async registration
end

function NeodapNeotreeVariableSource:setupNeotreeIntegration()
  vim.schedule(function()
    -- Registration logic here
  end)
end
```

**Why `vim.schedule`:**
- Ensures Neo-tree is fully loaded
- Avoids race conditions with plugin loading order
- Allows Neo-tree's own initialization to complete

## Pros and Cons Analysis

### ✅ Advantages

#### **1. Zero-Configuration Experience**
- Plugin "just works" out of the box
- New users don't need to understand Neo-tree configuration
- Reduces barrier to entry for debugging workflows

#### **2. Respects User Preferences**
- Power users who have configured Neo-tree aren't overridden
- Preserves existing configurations and customizations
- User remains in control of their setup

#### **3. Progressive Enhancement**
- Works at multiple levels of user expertise
- Beginners get automatic setup
- Advanced users get full control

#### **4. Graceful Degradation**
- If Neo-tree isn't available, plugin continues to work
- No hard dependencies on specific Neo-tree versions
- Safe error handling throughout

### ❌ Disadvantages

#### **1. Detection Complexity**
- Logic to detect user configuration could be brittle
- Depends on Neo-tree's internal API (`get_config()`)
- False positives/negatives in detection

#### **2. Configuration Conflicts**
- Our defaults might conflict with user's global Neo-tree settings
- Hard to predict interaction with other plugins
- Could override user's preferred window positions

#### **3. Persistence Issues**
- No way to "unregister" sources once registered
- Source remains available for entire session
- User can't easily disable auto-registration

#### **4. Timing Dependencies**
- Relies on plugin loading order
- `vim.schedule` might not be sufficient for all cases
- Race conditions with user's own configuration

## Alternative Approaches

### 1. **Pure Self-Registration**
```lua
-- Always register with defaults, ignore user config
manager.register(NeodapNeotreeVariableSource)
neotree.setup(our_defaults)
```

**Pros:** Simple, predictable
**Cons:** Overrides user preferences, potentially destructive

### 2. **Conditional Registration**
```lua
-- Only register when DAP session is active
self.api:onSession(function(session)
  self:registerWithNeotree()
end)
```

**Pros:** More targeted, less resource usage
**Cons:** Delayed availability, user confusion

### 3. **Lazy Registration**
```lua
-- Register on first attempt to use
-- e.g., when user runs :Neotree float neodap.plugins.NeodapNeotreeVariableSource
```

**Pros:** On-demand, minimal overhead
**Cons:** Poor discoverability, requires knowledge of command

### 4. **Manual Only**
```lua
-- Require explicit user configuration
-- Document setup requirements
```

**Pros:** Maximum user control, predictable
**Cons:** Higher barrier to entry, more setup friction

## Edge Cases and Considerations

### 1. **Neo-tree Not Installed**
```lua
local neotree_ok, neotree = pcall(require, "neo-tree")
if not neotree_ok then
  -- Gracefully skip integration
  return
end
```

**Behavior:** Plugin continues to work, just without Neo-tree integration

### 2. **Neo-tree Version Incompatibility**
```lua
if neotree.get_config then
  config = neotree.get_config() or {}
else
  -- Fallback for older Neo-tree versions
  config = {}
end
```

**Approach:** Defensive programming with fallbacks

### 3. **User Modifies Config After Plugin Load**
**Current behavior:** Our registration persists, user changes may not take effect
**Potential solution:** Watch for config changes and re-register

### 4. **Multiple Neodap Instances**
**Issue:** Multiple API instances could try to register the same source
**Current solution:** Class-level `_current_instance` - last one wins
**Better solution:** Instance-specific source names or singleton pattern

### 5. **Plugin Loading Order**
**Issue:** If our plugin loads before Neo-tree
**Solution:** `vim.schedule` and defensive `pcall` usage

### 6. **Configuration Merging Conflicts**
```lua
-- What if user has:
neotree.setup({
  sources = { "filesystem" },
  default_component_configs = { ... }
})

-- And we try to merge:
{
  sources = { "filesystem", "neodap.plugins.NeodapNeotreeVariableSource" },
  ["neodap.plugins.NeodapNeotreeVariableSource"] = { ... }
}
```

**Risk:** Could override user's global defaults
**Mitigation:** Only add source-specific configuration, avoid global changes

## Recommended Improvements

### 1. **Better Detection Logic**
```lua
-- Instead of just checking sources list, check for source-specific config
local user_has_configured_us = config[self.name] ~= nil
```

### 2. **Configuration Validation**
```lua
-- Validate that our defaults don't conflict with user settings
local function validate_config_compatibility(user_config, our_defaults)
  -- Check for conflicts and warn user
end
```

### 3. **Opt-out Mechanism**
```lua
-- Allow user to disable auto-registration
-- Via global variable or plugin option
if vim.g.neodap_disable_neotree_autoconfig then
  return
end
```

### 4. **Better User Feedback**
```lua
-- More informative messages
if auto_registered then
  vim.notify("🐛 Neodap auto-configured Neo-tree. Use :h neodap-neotree to customize", vim.log.levels.INFO)
end
```

### 5. **Cleanup on Plugin Destruction**
```lua
function NeodapNeotreeVariableSource:destroy()
  -- Ideally unregister from Neo-tree, but API doesn't support it
  -- Clear our instance reference
  NeodapNeotreeVariableSource._current_instance = nil
end
```

## Testing Strategy

### 1. **Zero-Config Scenario**
- Fresh Neo-tree installation with no user configuration
- Plugin should auto-register and provide working defaults
- `:Neotree float neodap.plugins.NeodapNeotreeVariableSource` should work

### 2. **User-Configured Scenario**
```lua
-- User has pre-configured Neo-tree with our source
require("neo-tree").setup({
  sources = { "filesystem", "neodap.plugins.NeodapNeotreeVariableSource" },
  ["neodap.plugins.NeodapNeotreeVariableSource"] = {
    window = { position = "left" }  -- User prefers sidebar
  }
})
```
- Plugin should respect user's configuration
- Should not override user's window position preference

### 3. **Neo-tree Unavailable Scenario**
- Neo-tree not installed or failed to load
- Plugin should continue working without errors
- No Neo-tree integration, but other functionality intact

### 4. **Late Neo-tree Loading**
- Neo-tree loads after our plugin
- Registration should still work via `vim.schedule`
- No race condition errors

## Conclusion

The hybrid self-registration approach offers a good balance between convenience and user control. However, it comes with complexity trade-offs that need careful consideration.

**Recommendation:** Proceed with hybrid approach but implement the suggested improvements for robustness and user experience.

**Key principles:**
1. **Fail gracefully** - Never break user's setup
2. **Respect user preferences** - Don't override explicit configurations  
3. **Provide escape hatches** - Allow users to disable auto-behavior
4. **Clear feedback** - Inform users what the plugin is doing automatically

The goal is to make debugging with Neo-tree "just work" while maintaining the flexibility that power users expect.