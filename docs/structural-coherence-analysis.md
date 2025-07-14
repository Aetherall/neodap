# Neodap Structural Coherence Analysis

This document identifies areas of the codebase with low structural coherence and provides recommendations for improvement.

## Executive Summary

The neodap codebase shows signs of organic growth with several architectural inconsistencies that impact maintainability. The main issues stem from:
1. Over-engineered abstraction layers (particularly in the Source system)
2. Unclear separation of concerns between components
3. Inconsistent patterns across similar functionality
4. Incomplete migration from legacy patterns

## Critical Issues

### 1. Source System: Three-Layer Abstraction Problem

**Current Structure:**
```
BaseSource (legacy base class)
    ↓
Source.lua (factory with legacy support)
    ↓
UnifiedSource (strategy-based implementation)
    ↓
12 Strategy files (Content, Identifier, Buffer × 4 variations)
```

**Problems:**
- Three abstraction layers for what should be a simple polymorphic class
- 12 strategy files create excessive indirection
- Legacy methods (isFile, isVirtual, asFile, asVirtual) still in use despite being deprecated
- BaseSource still contains legacy type-checking logic

**Impact:** 
- New developers need to understand 15+ files to work with sources
- Simple operations require navigating multiple abstraction layers
- Debugging is difficult due to indirection

**Recommendation:**
Consolidate into a single Source class with internal polymorphism:
```lua
-- Single Source.lua with internal strategies
Source = class()

function Source:new(session, dapSource)
  -- Determine type and behavior internally
  local isVirtual = dapSource.sourceReference ~= nil
  -- ... configure behavior based on type
end
```

### 2. Location-Source Circular Dependency

**Current Structure:**
- Location knows about Sources (has fromSource, fromUnifiedSource methods)
- SourceIdentifier duplicates source identification logic
- BaseSource imports Location, creating circular dependency

**Problems:**
- Unclear which component owns source identification
- Location has 4+ factory methods with overlapping responsibilities
- Circular imports make testing difficult

**Impact:**
- Hard to reason about data flow
- Changes to one system require changes to the other
- Unit testing requires mocking entire dependency chain

**Recommendation:**
- Make Location purely about positions (line, column)
- Move all source identification to Source system
- Use dependency injection for cross-component needs

### 3. Manager vs Plugin Pattern Inconsistency

**Current Patterns:**

| Component | Pattern | Size | Complexity |
|-----------|---------|------|------------|
| BreakpointApi | Manager | 390+ lines | High (modifies prototypes) |
| ToggleBreakpoint | Plugin | 50 lines | Low |
| StackNavigation | Plugin | 100 lines | Medium |

**Problems:**
- BreakpointApi uses Manager pattern but returns manager from plugin
- Manager directly modifies BaseSource prototype (monkey patching)
- No clear guidelines on when to use Manager vs Plugin

**Impact:**
- Inconsistent architecture makes it hard to add new features
- Unclear where functionality should live
- Prototype modification creates hidden dependencies

**Recommendation:**
- Establish clear Manager pattern for complex stateful features
- Use Plugin pattern for simple event handlers
- Avoid prototype modification; use composition instead

### 4. Event System Fragmentation

**Current Approaches:**
```lua
-- Approach 1: Hierarchical
session:onThread(function(thread)
  thread:onStopped(...)
end)

-- Approach 2: Direct hookable
manager.hookable:emit('breakpoint', ...)

-- Approach 3: Self-emitting
binding:_emitHit(thread)
```

**Problems:**
- Three different event patterns in use
- No clear ownership of event emission
- Mixed naming conventions
- Some components emit their own lifecycle events

**Impact:**
- Difficult to trace event flow
- Potential for missed events or double-handling
- Hard to implement cross-cutting concerns

**Recommendation:**
- Standardize on hierarchical event system
- Clear ownership: parent emits child events
- Consistent naming: noun:verb (thread:stopped, breakpoint:hit)

### 5. Virtual Buffer System Complexity

**Current Structure:**
- Singleton Registry for cross-session lookup
- Instance-based Manager per API
- Complex integration with Source strategies
- Session-independent persistence logic

**Problems:**
- Mixed singleton and instance patterns
- Unclear ownership of buffer lifecycle
- Complex cross-referencing with Source system
- Session-independent operations mixed with session-specific ones

**Impact:**
- Hard to reason about buffer lifecycle
- Potential memory leaks from retained buffers
- Complex testing due to singleton state

**Recommendation:**
- Unify buffer management under Source system
- Clear session-scoped vs global buffer distinction
- Use WeakMap for buffer caching to prevent leaks

### 6. Incomplete Legacy Migration

**Deprecated but Still Used:**
- BaseSource type-checking methods (isFile, isVirtual, asFile, asVirtual)
- Location legacy factory methods
- Source.lua factory maintaining backward compatibility

**Problems:**
- Deprecated methods still actively used in codebase
- New code sometimes uses old patterns
- Test confusion about "api.Source is now UnifiedSource"

**Impact:**
- Technical debt accumulation
- Confusion about which APIs to use
- Harder to onboard new developers

**Recommendation:**
- Complete migration sprint to remove all deprecated usage
- Update all tests to use new patterns
- Remove deprecated methods entirely

### 7. Singleton Pattern Inconsistency

**Current Usage:**
| Component | Pattern | Rationale |
|-----------|---------|-----------|
| Logger | Singleton | Global logging |
| VirtualBuffer/Registry | Singleton | Cross-session state |
| BreakpointApi | Per-instance | Per-session state |

**Problems:**
- No clear guidelines on singleton usage
- Some singletons for convenience, others for shared state
- Lifecycle management unclear

**Impact:**
- Potential state leakage between sessions
- Hard to test components in isolation
- Unclear initialization order

**Recommendation:**
- Document singleton usage guidelines
- Use dependency injection for testability
- Clear lifecycle management for singletons

### 8. Test Infrastructure Issues

**Problems Found:**
- Test.assert vs assert() confusion
- Tests using legacy patterns
- No clear test data builders
- Mixed async patterns in tests

**Impact:**
- Flaky tests requiring sleep/wait
- Hard to write comprehensive tests
- Test maintenance burden

**Recommendation:**
- Standardize test patterns
- Create test data builders
- Use spy-based verification instead of timing

## Refactoring Priority

### High Priority (Blocking new features)
1. Complete legacy source migration
2. Resolve Location-Source circular dependency
3. Standardize event system

### Medium Priority (Improving maintainability)
4. Consolidate Source abstraction layers
5. Clarify Manager vs Plugin patterns
6. Unify Virtual Buffer management

### Low Priority (Nice to have)
7. Singleton pattern standardization
8. Test infrastructure improvements

## Next Steps

1. **Immediate**: Complete migration away from deprecated methods
2. **Short-term**: Resolve circular dependencies and standardize events
3. **Long-term**: Consolidate abstraction layers and establish clear patterns

## Architectural Principles Going Forward

1. **Single Responsibility**: Each component should have one clear purpose
2. **Dependency Direction**: Dependencies should flow in one direction
3. **Abstraction Levels**: Minimize abstraction layers; prefer composition
4. **Event Ownership**: Parent components own child lifecycle events
5. **Pattern Consistency**: Similar problems should use similar solutions