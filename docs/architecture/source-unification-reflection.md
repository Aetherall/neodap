# Source Architecture Reflection: VirtualSource vs FileSource

## Executive Summary

This document reflects on the current `VirtualSource` and `FileSource` separation in the neodap architecture and questions whether this distinction is necessary from the DAP adapter's perspective. The analysis concludes that a unified `Source` class with strategy patterns would better align with the DAP specification and reduce architectural complexity.

## Current Architecture Problems

### 1. Artificial Classification During Instantiation

The current logic forces an arbitrary choice between source types:

```lua
-- Current logic in Session:getSourceFor()
if source.sourceReference and source.sourceReference > 0 then
  return VirtualSource.instanciate(session, source)
elseif source.path and source.path ~= '' then  
  return FileSource.instanciate(session, source)
end
```

**Problem**: What happens when a DAP source has both `path` AND `sourceReference`? The current system forces us to choose arbitrarily, potentially losing important information.

### 2. Duplicated Breakpoint Logic

```lua
-- BreakpointManager has to handle both types
if source:isFile() then
  sourceBreakpoints = self.breakpoints:atPath(source:absolutePath())
else
  sourceBreakpoints = self.breakpoints:atSource(source:identifier())
end
```

This conditional logic appears throughout the codebase, creating maintenance burden and potential inconsistencies.

### 3. API Inconsistencies

- `FileSource:identifier()` originally returned a string, `VirtualSource:identifier()` returns a SourceIdentifier object
- Different methods for similar concepts (`absolutePath()` vs `identifier()`)
- Breakpoint manager needs conditional logic everywhere
- Two different collection methods: `atPath()` and `atSource()`

### 4. Fragile Edge Cases

The current architecture struggles with:
- Sources with both path and sourceReference (hybrid sources)
- Sources that change between file and virtual over time
- Complex debugging scenarios (sourcemaps, transpiled code, hot reload)
- Dynamic content that might have file backing but requires DAP content retrieval

## DAP Specification Perspective

From the DAP adapter's viewpoint, there's really just one concept: **`dap.Source`**. The DAP spec defines a source as having:

- `path?` - Optional file path
- `sourceReference?` - Optional reference for content retrieval  
- `name?` - Display name
- `origin?` - Source origin description
- Other optional metadata

**Crucially**: A DAP source can have:
1. **Only `path`** (traditional file)
2. **Only `sourceReference`** (generated/virtual content)
3. **Both `path` AND `sourceReference`** (file with additional virtual content)
4. **Neither** (edge case, display-only)

The current architecture artificially splits what the DAP spec treats as a unified concept.

## Proposed Unified Architecture

### Unified Source Class

```lua
---@class api.Source: api.BaseSource
---@field contentStrategy ContentStrategy
---@field identifierStrategy IdentifierStrategy
---@field bufferStrategy BufferStrategy
local Source = Class(BaseSource)

function Source.instanciate(session, dapSource)
  local contentStrategy = Source._determineContentStrategy(dapSource)
  local identifierStrategy = Source._determineIdentifierStrategy(dapSource)
  local bufferStrategy = Source._determineBufferStrategy(dapSource)
  
  return Source:new({
    session = session,
    ref = dapSource,
    contentStrategy = contentStrategy,
    identifierStrategy = identifierStrategy,
    bufferStrategy = bufferStrategy
  })
end
```

### Strategy Patterns

#### Content Strategies
- **FileContentStrategy**: Read from disk using `path`
- **VirtualContentStrategy**: DAP source request using `sourceReference`
- **HybridContentStrategy**: Try file first, fallback to DAP
- **CachedContentStrategy**: Wrapper for performance

#### Identifier Strategies
- **PathIdentifierStrategy**: Use file path for identification
- **VirtualIdentifierStrategy**: Use stability hash from content/metadata
- **HybridIdentifierStrategy**: Combine both approaches
- **StabilityIdentifierStrategy**: Content-based stable identification

#### Buffer Strategies
- **FileBufferStrategy**: Use Neovim's file buffer management
- **VirtualBufferStrategy**: Use neodap's VirtualBuffer system
- **HybridBufferStrategy**: Coordinate between both systems

### Strategy Determination Logic

```lua
function Source._determineContentStrategy(dapSource)
  if dapSource.path and dapSource.sourceReference then
    return HybridContentStrategy.new()
  elseif dapSource.path then
    return FileContentStrategy.new()
  elseif dapSource.sourceReference then
    return VirtualContentStrategy.new()
  else
    return NoContentStrategy.new() -- Display-only
  end
end
```

## Benefits of Unified Approach

### 1. Simplified DAP Integration
- BreakpointManager works with "sources", period
- No conditional logic based on source type
- Natural handling of hybrid sources
- Consistent API surface

### 2. Flexible Content Loading
- File sources could fallback to DAP if file is missing/outdated
- Virtual sources could cache to disk for performance
- Dynamic strategy switching based on runtime conditions
- Graceful degradation when strategies fail

### 3. Consistent APIs
- One `identifier()` method that always returns SourceIdentifier
- One `content()` method that handles all cases
- Unified buffer management
- Single collection query method in BreakpointManager

### 4. Future-Proof Architecture
- Easy to add new source types (network, database, computed, etc.)
- Handles DAP spec evolution gracefully
- Supports complex debugging scenarios out of the box
- Composable strategies for complex requirements

### 5. Better Testing
- Strategies can be unit tested independently
- Mock strategies for testing
- Clear separation of concerns
- Reduced integration complexity

## DAP Breakpoint Perspective

For breakpoints, the DAP adapter only cares about sending the correct request structure:

- **File sources**: `{ source: { path: "..." }, breakpoints: [...] }`
- **Virtual sources**: `{ source: { sourceReference: N }, breakpoints: [...] }`
- **Hybrid sources**: `{ source: { path: "...", sourceReference: N }, breakpoints: [...] }`

The unified source would know how to create the appropriate DAP request structure internally based on its available information.

## Migration Strategy

### Phase 1: Introduce Strategy Classes
- Create strategy interfaces and implementations
- Keep existing VirtualSource/FileSource as strategy factories
- No breaking changes to public APIs

### Phase 2: Unified Source Implementation
- Implement unified Source class using strategies
- Update Session.getSourceFor() to use unified approach
- Maintain backward compatibility wrappers

### Phase 3: Simplify Consumer APIs
- Update BreakpointManager to use unified APIs
- Remove conditional logic based on source types
- Simplify collection methods

### Phase 4: Remove Legacy Classes
- Deprecate VirtualSource/FileSource classes
- Remove conditional logic throughout codebase
- Clean up collection APIs

## Conclusion

The current VirtualSource/FileSource distinction:
- ❌ Adds complexity without clear benefit
- ❌ Creates artificial edge cases that don't exist in DAP spec
- ❌ Requires conditional logic throughout the system
- ❌ Doesn't match the DAP specification's unified model
- ❌ Makes the system harder to extend and maintain

A unified Source class with strategy patterns would:
- ✅ Simplify the overall architecture significantly
- ✅ Better match DAP's conceptual model
- ✅ Handle edge cases naturally
- ✅ Reduce code duplication and conditional logic
- ✅ Make the system more maintainable and extensible
- ✅ Support complex debugging scenarios out of the box

**The distinction we really need is not in the source type, but in the strategies for handling different source characteristics.**

## References

- [DAP Specification - Source](https://microsoft.github.io/debug-adapter-protocol/specification#Types_Source)
- [Current Breakpoint Architecture](./breakpoints.md)
- [Virtual Sources Implementation](../virtual-sources-implementation-plan.md)

---

*This reflection was generated during the implementation of virtual source breakpoint support, when architectural inconsistencies became apparent.*