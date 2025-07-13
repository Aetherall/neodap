# Virtual Sources Implementation Analysis

## Overview

This document analyzes the missing elements and considerations for implementing virtual source support in neodap's Location API. Virtual sources represent non-file-system sources like sourcemap-reconstructed files, eval code, and internally generated content.

## Current State

### What Works
- **DAP Content Retrieval**: Virtual sources can retrieve content via `ContentAccessTrait:content()` → DAP source request
- **Source Identification**: Virtual sources identified by `sourceReference > 0` 
- **Source Classification**: Factory pattern distinguishes FileSource vs VirtualSource vs GenericSource
- **Session Management**: Virtual sources properly cached within sessions

### What's Missing
- **Buffer Creation**: No mechanism to create buffers for virtual sources
- **Buffer Loading**: No way to load DAP content into Neovim buffers
- **Navigation Support**: Frame jumping only works for file sources
- **Location Integration**: Location API cannot work with virtual sources
- **Cross-Session Coherence**: No stable identity for same virtual content across sessions

## Critical Gaps Analysis

### 1. Virtual Source Buffer Loading (CRITICAL)

**Current Limitation**: 
```lua
-- In BaseSource:bufnr()
if not self.ref or not self.ref.path then
  return nil  -- Virtual sources return nil!
end
```

**Impact**: 
- `Frame:jump()` fails for virtual sources (requires `source.path`)
- Location marking/navigation impossible for virtual sources
- Breakpoints cannot be set in virtual sources

**Required Implementation**:
- Virtual source buffer creation with synthetic URIs
- DAP content loading into newly created buffers
- Buffer lifecycle management for virtual sources

### 2. Virtual Source URI Scheme Design (CRITICAL)

**Problem**: Virtual sources need stable, identifiable URIs compatible with Neovim's buffer system.

**Design Considerations**:
- **Session-Agnostic**: `neodap-virtual://stability-hash/name` 
  - Pros: Cross-session coherence, same virtual source = same buffer
  - Cons: Complex session cleanup, potential memory leaks
  
- **Session-Specific**: `neodap-virtual://session-2/ref-123/name`
  - Pros: Clear ownership, easy cleanup
  - Cons: Same virtual source gets different buffers across sessions

**Integration Requirements**:
- Work with `vim.uri_to_bufnr()` and `vim.uri_from_fname()`
- Support Neovim's buffer naming conventions
- Enable proper buffer identification and management

### 3. Content Synchronization Strategy (HIGH)

**Questions to Resolve**:
- When does virtual source content change during debugging?
- How to detect content updates from DAP adapter?
- Should content be cached permanently or reloaded on demand?
- How to handle checksums for content verification?

**Current DAP Integration**:
```lua
-- ContentAccessTrait:content() works but only for memory cache
local response = self.session.ref.calls:source(args):wait()
if response and response.content then
  self._content = response.content
  return self._content
end
```

**Missing**: Bridge between DAP content and Neovim buffer content.

### 4. Cross-Session Buffer Coherence (HIGH)

**Key Insight**: "A given .js file with sourcemap will always produce the same virtual file, no matter which session reads it."

**Design Challenge**: 
- Virtual sources should have stable identity across sessions
- But `sourceReference` values are session-scoped
- Need content-based stability hash for cross-session coherence

**Proposed Strategy**:
```lua
-- Stability hash calculation
function calculate_stability_hash(dap_source)
  local stable_components = {
    dap_source.name,           -- "webpack://app/src/utils.js"
    dap_source.origin,         -- "inlined content from source map"
    dap_source.checksums,      -- Content hashes if available
    dap_source.sources,        -- Related source files
  }
  
  local hash_input = vim.inspect(stable_components)
  return vim.fn.sha256(hash_input):sub(1, 8)
end
```

### 5. Integration Point Updates (MEDIUM)

**Systems Requiring Virtual Source Support**:

- **BreakpointManager**: Breakpoint operations must work with virtual sources
- **Frame Navigation**: `Frame:jump()` and `Frame:highlight()` need virtual source support
- **Location API**: All location types need virtual source compatibility
- **Range Operations**: `BreakpointCollection:_isLocationBetween()` uses path comparisons
- **Stack Display**: Stack traces with virtual source frames
- **Scope Ranges**: Scopes with virtual source positions

### 6. Error Handling and Fallbacks (MEDIUM)

**Error Scenarios to Handle**:
- DAP adapter doesn't support source requests
- Virtual source content retrieval fails
- Buffer creation fails for virtual sources
- Content format issues (binary vs text)
- Network timeouts for remote virtual sources

**Fallback Strategies**:
- Graceful degradation when virtual sources unavailable
- Clear error messages for unsupported operations
- Recovery mechanisms for failed content loading

### 7. Performance and Caching Strategy (LOW)

**Considerations**:
- **Memory Usage**: Large virtual sources impact
- **DAP Request Frequency**: Avoid repeated content requests
- **Buffer Creation Overhead**: Lazy vs eager loading
- **Cache Invalidation**: When to refresh virtual content

## SourceIdentifier Design for Virtual Sources

### Proposed Structure
```lua
---@class VirtualSourceIdentifier  
---@field type 'virtual'
---@field sourceReference integer -- Session-scoped DAP reference
---@field origin string -- Semantic type ("eval", "source_map", "internal_module")
---@field name string -- Display name for UI/debugging
---@field stability_hash string -- Cross-session coherent identifier
---@field session_id integer -- Session context for operations
```

### String Representation
**Format**: `"virtual:{stability_hash}:{origin}:{sourceReference}"`

**Examples**:
- Eval: `"virtual:a1b2c3d4:eval:123"`
- Sourcemap: `"virtual:x9y8z7w6:source_map:456"`  
- Internal: `"virtual:f5e4d3c2:internal_module:789"`

### Identity Logic
```lua
function VirtualSourceIdentifier:equals(other)
  -- Primary: Same stability hash = same virtual source
  if self.stability_hash == other.stability_hash then
    return true
  end
  
  -- Secondary: Same session + sourceReference
  if self.session_id == other.session_id and 
     self.sourceReference == other.sourceReference then
    return true
  end
  
  return false
end
```

## Implementation Plan

### Phase 0: Foundation (Must Complete First)
1. **Design Virtual Source URI Scheme**
   - Choose between session-agnostic vs session-specific URIs
   - Implement URI generation and parsing
   - Test integration with Neovim buffer system

2. **Create Virtual Source Buffer Loading**
   - Implement buffer creation for virtual sources
   - Bridge DAP content to buffer content
   - Handle buffer lifecycle and cleanup

3. **Update Core Integration Points**
   - Fix `Frame:jump()` for virtual sources
   - Enable basic Location support for virtual sources
   - Test navigation and highlighting

### Phase 1: Core Implementation
4. **Implement SourceIdentifier System**
   - Create SourceIdentifier abstraction
   - Implement virtual source identification
   - Add stability hash calculation

5. **Update Location API**
   - Replace path-centric design with source identifiers
   - Implement source-agnostic operations
   - Maintain backward compatibility

6. **Generalize Range Operations**
   - Update BreakpointCollection range logic
   - Support range operations for virtual sources
   - Test breakpoint functionality

### Phase 2: Advanced Features
7. **Cross-Session Coherence**
   - Implement global virtual source cache
   - Handle buffer sharing across sessions
   - Test session cleanup and resource management

8. **Comprehensive Error Handling**
   - Add robust error handling for all virtual source operations
   - Implement fallback strategies
   - Test edge cases and failure scenarios

### Phase 3: Polish
9. **Performance Optimization**
   - Optimize caching strategies
   - Minimize DAP request frequency
   - Profile memory usage

10. **Documentation and Testing**
    - Comprehensive test coverage
    - Migration guides
    - API documentation and examples

## Key Architectural Decisions

### Buffer Creation Strategy
**Recommendation**: **Lazy Loading**
- Create buffers only when accessed (navigation, breakpoint setting)
- Reduces memory usage for unused virtual sources
- Provides better performance for sessions with many virtual sources

### URI Scheme Choice
**Recommendation**: **Session-Agnostic with Stability Hash**
- Pattern: `neodap-virtual://{stability_hash}/{sanitized_name}`
- Enables cross-session coherence
- Simplifies buffer management
- Example: `neodap-virtual://a1b2c3d4/webpack-app-src-utils.js`

### Content Caching Policy
**Recommendation**: **Cache with Checksum Validation**
- Load content once per virtual source
- Use checksums to detect content changes
- Reload only when DAP adapter reports content updates

### Cross-Session Buffer Sharing
**Recommendation**: **Shared Buffers with Reference Counting**
- Same virtual source content = same buffer across sessions
- Track session references for proper cleanup
- Clean up buffers when no sessions reference them

## Success Criteria

### Functional Requirements
- [ ] Virtual sources can be loaded into Neovim buffers
- [ ] Frame navigation works for virtual sources
- [ ] Breakpoints can be set in virtual sources
- [ ] Location API supports both file and virtual sources
- [ ] Range operations work for virtual sources
- [ ] Cross-session coherence maintained

### Performance Requirements
- [ ] Virtual source buffer creation < 100ms
- [ ] Memory usage grows linearly with active virtual sources
- [ ] No degradation in file source performance

### Compatibility Requirements
- [ ] All existing file-based workflows continue working
- [ ] Backward compatibility for Location API
- [ ] No breaking changes to plugin interfaces

## Risks and Mitigation

### Complexity Risk
**Risk**: Virtual source implementation adds significant complexity
**Mitigation**: 
- Implement in phases with clear milestones
- Maintain separation between file and virtual source paths
- Comprehensive testing at each phase

### Performance Risk
**Risk**: Virtual source operations impact overall debugging performance
**Mitigation**:
- Lazy loading strategies
- Efficient caching mechanisms
- Performance monitoring and profiling

### Compatibility Risk
**Risk**: Changes break existing functionality
**Mitigation**:
- Extensive backward compatibility testing
- Gradual migration with both APIs supported
- Clear deprecation timeline for old patterns
