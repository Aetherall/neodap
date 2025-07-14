# Neodap Refactoring Action Plan

Based on the structural coherence analysis, here's a concrete action plan to address the most critical issues.

## Phase 1: Complete Legacy Migration (1-2 days)

### 1.1 Remove Deprecated Source Methods
**Files to modify:**
- `lua/neodap/api/Session/Source/BaseSource.lua`
- All files using `isFile()`, `isVirtual()`, `asFile()`, `asVirtual()`

**Actions:**
```lua
-- Remove from BaseSource:
-- function BaseSource:isFile()
-- function BaseSource:isVirtual() 
-- function BaseSource:asFile()
-- function BaseSource:asVirtual()

-- Replace usage with:
source.type == 'file'
source.type == 'virtual'
-- Direct usage, no casting needed
```

### 1.2 Update Location Factory Methods
**Files to modify:**
- `lua/neodap/api/Location/init.lua`
- All files using legacy location creation

**Actions:**
- Remove `fromUnifiedSource` (redundant with `fromSource`)
- Standardize on `Location.create()` and `Location.fromSource()`
- Update all call sites

## Phase 2: Resolve Circular Dependencies (2-3 days)

### 2.1 Break Location-Source Dependency
**Current problem:**
```
BaseSource → imports Location
Location → imports SourceIdentifier
SourceIdentifier → knows about Source concepts
```

**Solution:**
```lua
-- Make Location purely positional
Location = {
  line = number,
  column = number,
  -- No source knowledge
}

-- Move source+position logic to SourceLocation
SourceLocation = {
  source = Source,
  location = Location
}
```

### 2.2 Remove BaseSource Prototype Modifications
**Files to modify:**
- `lua/neodap/plugins/BreakpointApi/BreakpointManager.lua`
- `lua/neodap/api/Session/Source/BaseSource.lua`

**Actions:**
- Move breakpoint methods to BreakpointManager
- Use composition instead of prototype modification
- Update all usage sites

## Phase 3: Consolidate Source System (3-4 days)

### 3.1 Merge Source Layers
**Current:** BaseSource → Source → UnifiedSource → 12 Strategies
**Target:** Single Source class with internal strategies

**Actions:**
1. Move UnifiedSource logic into Source.lua
2. Internalize strategies as private methods
3. Remove BaseSource inheritance
4. Delete strategy files

### 3.2 Simplify Source Creation
```lua
-- New simplified API
Source.create(session, dapSource)
-- Handles all source types internally
```

## Phase 4: Standardize Event System (2-3 days)

### 4.1 Establish Event Ownership Rules
**Principle:** Parent emits child lifecycle events

**Changes needed:**
- Session emits source events
- Thread emits frame events  
- Manager emits binding events
- Remove self-emitting patterns

### 4.2 Consistent Event Naming
**Pattern:** `noun:verb`

**Standard events:**
- `session:initialized`
- `thread:stopped`
- `breakpoint:hit`
- `frame:selected`

## Phase 5: Unify Buffer Management (2-3 days)

### 5.1 Move Buffer Logic to Source
**Current:** Separate VirtualBuffer system
**Target:** Buffer management as Source responsibility

**Actions:**
- Add `getBuffer()` method to Source
- Move virtual buffer logic into Source
- Simplify Registry to pure cache

### 5.2 Clear Session Scoping
```lua
-- Session-scoped buffers
source:getBuffer() -- Returns session-specific buffer

-- Global buffer cache (for persistence)
BufferCache.get(stability_hash) -- Returns cached buffer if exists
```

## Implementation Order

### Week 1
1. Complete legacy migration (Phase 1)
2. Start circular dependency resolution (Phase 2)

### Week 2  
3. Finish circular dependencies
4. Begin source consolidation (Phase 3)

### Week 3
5. Complete source consolidation
6. Standardize events (Phase 4)
7. Unify buffer management (Phase 5)

## Success Metrics

- **Code Reduction:** Expect 30-40% fewer files in Source system
- **Dependency Graph:** No circular dependencies
- **Test Coverage:** All tests passing with new patterns
- **Developer Experience:** New features require touching fewer files

## Risk Mitigation

1. **Feature Freeze:** No new features during refactoring
2. **Incremental Changes:** Each phase independently testable
3. **Backward Compatibility:** Temporary adapters where needed
4. **Test First:** Update tests before implementation

## Quick Wins (Can do immediately)

1. Delete unused deprecated methods
2. Fix Test.assert → assert() in tests
3. Remove redundant Location factory methods
4. Document singleton usage patterns

## Long-term Vision

After refactoring:
- Single Source class handles all source types
- Clear separation between Location (position) and Source (content)
- Consistent plugin pattern for extensions
- Hierarchical event system throughout
- No circular dependencies