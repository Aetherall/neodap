# Neodap Plugin Architecture Guide

This guide captures architectural insights and best practices for designing high-quality Neodap plugins, distilled from successful implementations like ToggleBreakpoint and StackNavigation.

## 🎯 Core Architectural Principles

### 1. **User Intent Preservation**
- **Never modify user decisions automatically** - breakpoints should stay where users place them
- **Provide intelligent assistance** during user actions, not automatic changes
- **Respect explicit user actions** - same action should produce consistent results

### 2. **Mathematical Precision Over Heuristics**
- Use `Location:distance()` for optimal selection instead of complex fallback strategies
- Finite hierarchical distances: `10,000,000 >> 1,000 >> 1` (source >> line >> column)
- Deterministic algorithms that produce predictable results

### 3. **Leverage Architecture, Don't Reimplement**
- Use existing APIs and iterators with smart filtering
- Push complexity to the right abstraction level
- Build on Location/Source/Session foundations

## 🔄 Pattern Selection: Reactive vs Intentional

### When to Use **Reactive Patterns**

**Use for system state that changes independently of user actions:**

```lua
// ✅ CORRECT: Visual feedback that should reflect reality
breakpoint:onBinding(function(binding)
  binding:onUpdated(function(dapBreakpoint)
    location:mark(ns, marks.bound)  // Update visual to match actual state
  end)
end)

// ✅ CORRECT: Automatic cleanup of system resources
thread:onResumed(function(body)
  self.thread_positions[thread.id] = nil  // Auto-clear ephemeral state
end)
```

**Characteristics:**
- **System Events**: Thread state changes, binding updates, session lifecycle
- **Visual Feedback**: UI elements that should reflect actual system state
- **Resource Cleanup**: Automatic memory/state management
- **User Expectation**: "Show me what's really happening"

### When to Use **Intentional Patterns**

**Use for user-driven actions and decisions:**

```lua
// ✅ CORRECT: User-triggered navigation
function StackNavigation:up()
  local closest = self:getClosestFrame()  // Use intelligence for assistance
  local parent = closest and closest:up()
  if parent then parent:jump() end        // Only act when user requests
end

// ✅ CORRECT: Smart breakpoint placement
function ToggleBreakpoint:toggle(location)
  local adjusted = self:adjust(location)  // Intelligent suggestion
  // Act on suggestion, don't auto-modify existing breakpoints
end
```

**Characteristics:**
- **User Actions**: Explicit requests for navigation, toggling, modification
- **Decision Assistance**: Use session info for smart suggestions
- **Predictable Behavior**: Same action produces consistent results
- **User Expectation**: "Help me do what I want intelligently"

### ❌ **Anti-Patterns to Avoid**

```lua
// ❌ BAD: Auto-modifying user breakpoints
api:onSession(function(session)
  session:onInitialized(function()
    for breakpoint in breakpoints:each() do
      autoAdjustBreakpoint(session, breakpoint)  // User didn't ask for this!
    end
  end)
end)

// ❌ BAD: Complex fallback strategies instead of mathematical selection
if exactMatch then
  return exactMatch
elseif sameFileMatch then
  return sameFileMatch
elseif primaryThread then
  return primaryThread
else
  return fallback  // Use distance calculation instead!
end
```

## 🏗️ Plugin Structure Patterns

### Standard Plugin Class Structure

```lua
local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local SomeApi = require("neodap.plugins.SomeApi")

---@class neodap.plugin.MyPluginProps
---@field api Api
---@field logger Logger

---@class neodap.plugin.MyPlugin: neodap.plugin.MyPluginProps
---@field new Constructor<neodap.plugin.MyPluginProps>
local MyPlugin = Class()

MyPlugin.name = "MyPlugin"
MyPlugin.description = "Brief description of plugin purpose"

function MyPlugin.plugin(api)
  local logger = Logger.get()

  local instance = MyPlugin:new({
    api = api,
    logger = logger,
    dependencyApi = api:getPluginInstance(SomeApi),
  })
  
  -- Call listen() only if reactive state tracking is needed
  -- instance:listen()
  
  return instance
end

-- User intent methods
function MyPlugin:primaryAction(location)
  -- Use NvimAsync.run() for async operations
  -- Leverage mathematical selection algorithms
  -- Respect user intent, provide intelligent assistance
end

-- Optional: listen() method for reactive state tracking
function MyPlugin:listen()
  self.api:onSession(function(session)
    -- Minimal reactive tracking only when necessary
  end, { name = self.name .. ".onSession" })
end

return MyPlugin
```

## 🔍 API Integration Strategies

### Leverage Existing Iterators with Smart Filtering

```lua
// ✅ PREFERRED: Use API-level filtering
for session in self.api:eachSession() do
  for thread in session:eachThread({ filter = 'stopped' }) do
    for frame in stack:eachFrame({ sourceId = target.sourceId }) do
      // Efficient, filtered iteration
    end
  end
end

// ❌ AVOID: Manual filtering in plugin logic
for session in self.api:eachSession() do
  for thread in session:eachThread() do
    if thread.stopped then  // Manual check - push to API level
      // ...
    end
  end
end
```

### Distance-Based Mathematical Selection

```lua
function MyPlugin:findClosest(target)
  local closest = nil
  local closest_distance = math.huge
  
  for candidate in self:getAllCandidates() do
    local location = candidate:location()
    if location then
      local distance = location:distance(target)
      if distance < closest_distance then
        closest_distance = distance
        closest = candidate
      end
    end
  end
  
  return closest
end
```

### Location-Centric Operations

```lua
// ✅ Always work with Location objects
local cursor_location = Location.fromCursor()
local target_location = Location.fromSource(source, { line = 10, column = 5 })

// ✅ Use Location methods for operations
if location1:sameLine(location2) then
  // Same source and line
end

local distance = location1:distance(location2)
local adjusted = location:adjusted({ column = 0 })

// ✅ Use polymorphic session methods
local source = session:getSource(location)  // Works with Location or SourceIdentifier
```

## ⚡ Performance Optimization Guidelines

### 1. **Smart Filtering at API Level**
- Use iterator filters: `{ filter = 'stopped' }`, `{ sourceId = target.sourceId }`
- Avoid manual filtering in plugin logic
- Push complexity to the right abstraction level

### 2. **Finite Distance Calculations**
```lua
function Location:distance(other)
  -- Use finite hierarchical weights for stability
  if not self.sourceId:equals(other.sourceId) then
    return 10000000  // Large but finite
  end
  
  if self.line ~= other.line then
    return 1000 + math.abs((self.column or 0) - (other.column or 0))
  end
  
  return math.abs((self.column or 0) - (other.column or 0))
end
```

### 3. **Dynamic Discovery vs Caching**
- **Prefer dynamic discovery** for ephemeral state (thread positions, cursor location)
- **Use caching** only for expensive, stable computations
- Modern APIs are often fast enough for real-time discovery

### 4. **Throttled Operations**
```lua
// For high-frequency events like cursor movement
local lastCheck = 0
local throttleMs = 500

vim.api.nvim_create_autocmd({"CursorMoved"}, {
  callback = function()
    local now = vim.loop.hrtime() / 1000000
    if now - lastCheck < throttleMs then return end
    lastCheck = now
    
    self:checkCursorPosition()
  end
})
```

## 🎨 Design Pattern Examples

### Example 1: ToggleBreakpoint Pattern (Intentional + Smart Assistance)

```lua
function ToggleBreakpoint:adjust(location)
  local loc = location:adjusted({ column = 0 })  // Safe default
  
  // Use ALL available session info for intelligent suggestion
  for session in self.api:eachSession() do
    local source = session:getSource(location)
    if source then
      for candidate in source:breakpointLocations({ line = location.line }) do
        if candidate:distance(location) < loc:distance(location) then
          loc = candidate  // Mathematical selection
        end
      end
    end
  end
  
  return loc  // Return suggestion, don't auto-apply
end

function ToggleBreakpoint:toggle(location)
  local target = location or Location.fromCursor()
  local adjusted = self:adjust(target)  // Use intelligence when user acts
  
  local existing = self.breakpointApi.getBreakpoints():atLocation(adjusted):first()
  if existing then
    self.breakpointApi.removeBreakpoint(existing)  // Respect user intent
  else
    self.breakpointApi.setBreakpoint(adjusted)
  end
end
```

### Example 2: StackNavigation Pattern (Pure Intentional + Mathematical Selection)

```lua
function StackNavigation:getClosestFrame(location)
  local target = location or Location.fromCursor()
  local closest = nil
  local closest_distance = math.huge
  
  // Efficient filtered iteration
  for session in self.api:eachSession() do
    for thread in session:eachThread({ filter = 'stopped' }) do
      for frame in stack:eachFrame({ sourceId = target.sourceId }) do
        local distance = frame:location():distance(target)
        if distance < closest_distance then
          closest_distance = distance
          closest = frame
        end
      end
    end
  end
  
  return closest
end

function StackNavigation:up()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    local parent = closest and closest:up()
    if parent then parent:jump() end  // Only act on user request
  end)
end
```

### Example 3: VirtualText Pattern (Reactive Feedback)

```lua
// Reactive pattern for visual feedback
BP.onBreakpoint(function(breakpoint)
  breakpoint:onBinding(function(binding)
    local location = binding:getActualLocation()
    
    binding:onHit(function(_, resumed)
      location:mark(ns, marks.hit)    // Immediate visual feedback
      resumed.wait()
      location:mark(ns, marks.bound)  // Restore after resume
    end)
    
    binding:onUpdated(function()
      location:unmark(ns)
      location = binding:getActualLocation()  // Update to actual position
      location:mark(ns, marks.bound)
    end)
  end)
end)
```

## 🚫 Common Anti-Patterns

### 1. **Over-Engineering State Management**
```lua
// ❌ Complex state tracking for ephemeral data
self.thread_positions = {}  // Don't track what you can discover
self.cursor_positions = {}  // Use Location.fromCursor() instead
self.frame_cache = {}       // Use dynamic discovery with smart filtering
```

### 2. **Manual Implementation of Existing APIs**
```lua
// ❌ Reimplementing distance calculations
function calculateDistance(loc1, loc2)
  // Complex custom logic...
end

// ✅ Use built-in mathematical precision
local distance = location1:distance(location2)
```

### 3. **Complex Fallback Strategies**
```lua
// ❌ Multiple fallback strategies
if strategy1() then return strategy1()
elseif strategy2() then return strategy2()
elseif strategy3() then return strategy3()
else return fallback() end

// ✅ Single mathematical algorithm
return findClosestByDistance(target)
```

### 4. **Mixing Reactive and Intentional Patterns**
```lua
// ❌ Auto-modifying user decisions
function onSessionChange()
  adjustUserBreakpoints()  // Don't change user intent automatically
end

// ✅ Assist during user actions
function userToggleAction(location)
  local suggestion = getIntelligentSuggestion(location)
  // Apply suggestion only when user acts
end
```

## 🔧 Debugging and Logging

### Structured Logging Pattern
```lua
local log = Logger.get()

// Use consistent logging levels
log:debug("PluginName: Detailed execution flow", variable)
log:info("PluginName: Important operational events")
log:warn("PluginName: Recoverable issues")
log:error("PluginName: Serious problems requiring attention")

// Include relevant context
log:debug("StackNavigation: Found closest frame at distance", distance, "key:", frame.location.key)
```

### Error Handling
```lua
function MyPlugin:safeOperation()
  if not self:preconditionsOk() then
    self.logger:debug("MyPlugin: Preconditions not met, skipping operation")
    return nil
  end
  
  local result = self:performOperation()
  if not result then
    self.logger:warn("MyPlugin: Operation failed, using fallback")
    return self:fallbackOperation()
  end
  
  return result
end
```

## 🎯 Quality Checklist

When implementing a new plugin, ensure:

### Architecture
- [ ] **Clear pattern selection**: Reactive for system state, intentional for user actions
- [ ] **Mathematical precision**: Distance-based selection over heuristic fallbacks
- [ ] **API leverage**: Use existing iterators and filtering instead of reimplementing
- [ ] **Location-centric**: Work with Location objects, not raw coordinates

### Code Quality
- [ ] **Minimal lines**: Achieve functionality with least code complexity
- [ ] **Single responsibility**: Each method does one thing clearly
- [ ] **Predictable behavior**: Same input produces same output
- [ ] **Error handling**: Graceful degradation with informative logging

### Performance
- [ ] **Smart filtering**: Use API-level filters for efficient iteration
- [ ] **Finite calculations**: Avoid `math.huge`, use hierarchical finite weights
- [ ] **Appropriate caching**: Cache only expensive, stable computations
- [ ] **Throttled operations**: Limit high-frequency event processing

### User Experience
- [ ] **Intent preservation**: Never auto-modify user decisions
- [ ] **Intelligent assistance**: Provide smart suggestions during user actions
- [ ] **Deterministic results**: Consistent behavior builds user trust
- [ ] **Cross-session awareness**: Handle multi-session scenarios gracefully

## 🔮 Future Considerations

### Extensibility Patterns
- Design for composition rather than inheritance
- Emit events for other plugins to consume
- Expose subsystems for advanced usage
- Maintain stable public APIs

### Session Management
- Consider cross-session buffer persistence
- Handle session lifecycle events appropriately
- Use session-aware but session-independent algorithms
- Design for multi-session scenarios from the start

By following these patterns and principles, plugins will achieve the same architectural excellence demonstrated by ToggleBreakpoint and StackNavigation: minimal code, mathematical precision, intelligent assistance, and respect for user intent.