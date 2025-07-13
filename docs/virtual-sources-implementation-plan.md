# Virtual Sources Implementation Plan

## Executive Summary

This document outlines the complete implementation plan for adding virtual source support to neodap's Location API. Virtual sources represent non-file-system sources like sourcemap-reconstructed files, eval code, and internally generated content. The implementation preserves cross-session coherence while maintaining backward compatibility.

## Background and Requirements

### Core Requirement
As stated in the original analysis: "A given .js file with sourcemap will always produce the same virtual file, no matter which session reads it. We must preserve coherence wherever possible. Also, virtual sources can be loaded into buffers."

### Current Limitations
1. **Location API is file-path centric**: Uses `path` fields and file URI assumptions
2. **No virtual buffer support**: `BaseSource:bufnr()` returns `nil` for virtual sources
3. **Navigation failures**: `Frame:jump()` only works with file sources
4. **No cross-session coherence**: Same virtual content would create different buffers

## Architectural Decisions

### 1. Session-Agnostic vs Session-Specific URIs

**Decision: Session-Agnostic URIs**

After thorough analysis, we chose session-agnostic URIs with the pattern:
```
neodap-virtual://{stability_hash}/{sanitized_name}
```

**Rationale:**
- **Cross-session coherence**: Same virtual source always maps to same buffer
- **User experience**: Consistent buffer identity across debugging sessions
- **Neovim alignment**: Matches Neovim's global buffer namespace
- **Resource efficiency**: No duplicate buffers for identical content

**Considered Alternative:** Session-specific URIs would have provided simpler cleanup but violated the coherence requirement and created confusing duplicate buffers.

### 2. Directory Organization

**Decision: Session-Independent Resources at API Level**

Resources that outlive sessions are organized outside the Session directory:

```
lua/neodap/api/
├── Location/                      # Session-independent
│   └── SourceIdentifier.lua       # NEW
├── VirtualBuffer/                 # Session-independent (NEW)
│   ├── Registry.lua
│   ├── Metadata.lua
│   ├── Manager.lua
│   └── init.lua
└── Session/                       # Session-scoped only
    └── Source/
        └── VirtualSource.lua      # Uses VirtualBuffer API
```

**Rationale:**
- **Clear lifecycle boundaries**: Directory structure reflects resource lifetime
- **Discoverability**: Obvious which components outlive sessions
- **Testability**: Session-independent components can be tested in isolation
- **Follows existing pattern**: Mirrors how Location is organized

### 3. Stability Hash Strategy

**Decision: Content-Based Hashing**

Stability hash calculation includes:
- Source name
- Origin (eval, sourcemap, etc.)
- Checksums (if available)
- Related sources (for sourcemap coherence)

**Rationale:**
- **Deterministic**: Same input always produces same hash
- **Cross-session stable**: Independent of session-specific data
- **Collision resistant**: Multiple components reduce conflicts
- **Debuggable**: Components are meaningful for troubleshooting

### 4. Buffer Lifecycle Management

**Decision: Reference Counting with Grace Period**

Virtual buffers use reference counting from sessions with a 30-second grace period after last reference is removed.

**Rationale:**
- **Prevents premature cleanup**: User might restart debugging quickly
- **Memory efficiency**: Unused buffers eventually cleaned up
- **User control**: Manual cleanup commands available
- **Graceful degradation**: Buffers can be manually deleted without breaking system

### 5. Backward Compatibility Strategy

**Decision: Dual API with Deprecation Path**

- Keep `path` field in Location objects
- Add `source_identifier` as primary field
- Support both creation patterns
- Emit deprecation warnings (configurable)

**Rationale:**
- **Zero breaking changes**: Existing code continues working
- **Gradual migration**: Users can update at their pace
- **Clear upgrade path**: Warnings guide migration
- **Future-proof**: Clean path to removing legacy code

## Implementation Plan

### Phase 1: Virtual Buffer Infrastructure (Session-Independent)

#### 1.1 VirtualBuffer Registry (`/lua/neodap/api/VirtualBuffer/Registry.lua`)

**Purpose**: Singleton registry managing all virtual buffers across sessions

**Key Features:**
- Global buffer tracking by URI
- Stability hash index for fast lookups
- Session reference counting
- Buffer cleanup scheduling

**Implementation Details:**
```lua
-- Singleton pattern
function VirtualBufferRegistry.get()
  if not VirtualBufferRegistry._instance then
    VirtualBufferRegistry._instance = VirtualBufferRegistry:new({
      buffers = {},            -- URI -> metadata
      stability_index = {}     -- stability_hash -> URI
    })
  end
  return VirtualBufferRegistry._instance
end
```

**System Impact:**
- New global state (singleton)
- Memory: ~1KB base + ~200 bytes per buffer
- No performance impact on existing operations

#### 1.2 VirtualBuffer Metadata (`/lua/neodap/api/VirtualBuffer/Metadata.lua`)

**Purpose**: Structured metadata for each virtual buffer

**Key Fields:**
- `uri`: Full neodap-virtual:// URI
- `bufnr`: Neovim buffer number
- `content_hash`: For content validation
- `stability_hash`: Cross-session identifier
- `referencing_sessions`: Active session references
- `last_accessed`: For cleanup decisions

**Implementation Details:**
- Immutable after creation (except references)
- Validation methods for buffer state
- Statistics helpers

#### 1.3 VirtualBuffer Manager (`/lua/neodap/api/VirtualBuffer/Manager.lua`)

**Purpose**: Buffer lifecycle operations

**Key Features:**
- Buffer creation with proper Neovim settings
- Content loading from DAP
- Cleanup scheduling with grace period
- User command implementations

**Implementation Details:**
```lua
function VirtualBufferManager.createBuffer(uri, content, filetype)
  local bufnr = vim.api.nvim_create_buf(false, true) -- nofile, scratch
  
  -- Configure for virtual source
  vim.api.nvim_buf_set_name(bufnr, uri)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  
  -- Load content...
  return bufnr
end
```

### Phase 2: Source Identifier System (Session-Independent)

#### 2.1 SourceIdentifier (`/lua/neodap/api/Location/SourceIdentifier.lua`)

**Purpose**: Unified identification for file and virtual sources

**Key Features:**
- Type discrimination (file vs virtual)
- Stability hash calculation
- URI generation
- Buffer lookup delegation

**Implementation Details:**
```lua
-- Factory pattern for creation
function SourceIdentifier.fromDapSource(dap_source, session)
  if dap_source.path and dap_source.path ~= '' then
    return SourceIdentifier.fromPath(dap_source.path)
  elseif dap_source.sourceReference and dap_source.sourceReference > 0 then
    return {
      type = 'virtual',
      stability_hash = SourceIdentifier.calculateStabilityHash(dap_source),
      origin = dap_source.origin or 'unknown',
      name = dap_source.name or 'unnamed',
      -- Optional session context
      source_reference = dap_source.sourceReference,
      session_id = session and session.id
    }
  end
end
```

**Design Considerations:**
- Session-independent by default
- Optional session context for debugging
- Efficient equality comparison
- Clean toString() for debugging

### Phase 3: Virtual Source Enhancement

#### 3.1 VirtualSource Updates (`/lua/neodap/api/Session/Source/VirtualSource.lua`)

**Purpose**: Connect session-scoped sources to session-independent buffers

**Key Changes:**
- Implement `bufnr()` method
- Delegate to VirtualBuffer system
- Content hash validation
- Filetype detection
- Reference cleanup on destroy

**Implementation Details:**
```lua
function VirtualSource:bufnr()
  local registry = VirtualBufferRegistry.get()
  local uri = self:uri()
  
  -- Check existing buffer with content validation
  local existing = registry:getBufferByUri(uri)
  if existing and existing:isValid() then
    if existing.content_hash == self:contentHash() then
      registry:addSessionReference(uri, self.session.id)
      return existing.bufnr
    end
  end
  
  -- Create new buffer via manager
  -- Register with reference counting
  -- Return buffer number
end
```

### Phase 4: Location API Generalization

#### 4.1 BaseLocation Updates (`/lua/neodap/api/Location/Base.lua`)

**Key Changes:**
- Add `source_identifier` field
- Implement delegation methods
- Maintain `path` for compatibility
- Update type guards

**Backward Compatibility:**
```lua
function BaseLocation:getSourceIdentifier()
  -- Lazy migration from path
  if not self.source_identifier and self.path then
    self.source_identifier = SourceIdentifier.fromPath(self.path)
  end
  return self.source_identifier
end
```

#### 4.2 Location Factory Updates (`/lua/neodap/api/Location/init.lua`)

**New APIs:**
- `Location.fromVirtualSource(virtual_source, opts)`
- `Location.fromSourceIdentifier(identifier, opts)`

**Enhanced APIs:**
- `Location.create()` accepts `source_identifier`
- `Location.fromDapBinding()` supports virtual sources

#### 4.3 Location Type Updates

All location types (SourceFilePosition, SourceFileLine, SourceFile) updated to:
- Use source identifiers internally
- Support virtual source operations
- Maintain backward compatibility

### Phase 5: System Integration

#### 5.1 Frame Navigation (`/lua/neodap/api/Session/Frame.lua`)

**Changes:**
- Support virtual source navigation
- Automatic buffer creation
- Consistent jump behavior

#### 5.2 BreakpointCollection (`/lua/neodap/plugins/BreakpointApi/BreakpointCollection.lua`)

**Changes:**
- Source-agnostic range operations
- Virtual source filtering methods
- Identifier-based comparisons

#### 5.3 Session Cleanup (`/lua/neodap/api/Session/Session.lua`)

**Changes:**
- Remove virtual buffer references on destroy
- Trigger cleanup scheduling
- Prevent memory leaks

### Phase 6: User Experience

#### 6.1 Error Handling

**Error Scenarios:**
- DAP adapter lacks source request support
- Content retrieval failures
- Buffer creation errors
- Content format issues

**Strategies:**
- Clear, actionable error messages
- Graceful degradation
- Recovery options

#### 6.2 User Commands

**New Commands:**
- `:NeodapVirtualBufferStats` - Show statistics
- `:NeodapVirtualBufferCleanup` - Manual cleanup
- `:NeodapVirtualBufferList` - List active buffers

## Testing Strategy

### Unit Tests
- Each new component tested in isolation
- Mock dependencies for clarity
- Edge case coverage

### Integration Tests
- Cross-session buffer reuse
- Session cleanup scenarios
- Backward compatibility
- Navigation and breakpoints

### Performance Tests
- Large session scenarios
- Memory usage monitoring
- Buffer creation timing

## Migration Guide

### For Users
1. Existing code continues working
2. Optional: Update to use new APIs for virtual source support
3. Optional: Enable deprecation warnings to find old patterns

### For Plugin Authors
1. Use Location API - automatically gain virtual support
2. Avoid direct path assumptions
3. Test with virtual sources

## Risk Mitigation

### Performance Risks
- **Mitigation**: Lazy buffer creation, efficient caching
- **Monitoring**: Performance benchmarks in tests

### Memory Risks
- **Mitigation**: Reference counting, cleanup scheduling
- **Monitoring**: Statistics commands for users

### Compatibility Risks
- **Mitigation**: Extensive backward compatibility
- **Monitoring**: Deprecation warnings, migration guides

## Success Metrics

### Functional Success
- [ ] Virtual sources load in buffers
- [ ] Navigation works for virtual sources
- [ ] Breakpoints work in virtual sources
- [ ] Cross-session coherence maintained
- [ ] Zero breaking changes

### Performance Success
- [ ] Buffer creation < 100ms
- [ ] Memory usage scales linearly
- [ ] No degradation for file sources

### User Experience Success
- [ ] Intuitive virtual source handling
- [ ] Clear error messages
- [ ] Helpful documentation

## Future Considerations

### Potential Extensions
1. Remote source support (SSH, HTTP)
2. Dynamic source generation
3. Source transformation pipelines
4. Enhanced sourcemap support

### API Evolution
1. Remove deprecated `path` field (v2.0)
2. Add source provider plugins
3. Enhanced content caching strategies

## Conclusion

This implementation plan provides comprehensive virtual source support while maintaining neodap's architectural principles. The session-independent organization ensures proper resource lifecycle management, and the careful attention to backward compatibility ensures a smooth transition for existing users.

The plan balances immediate functionality needs with long-term architectural sustainability, providing a solid foundation for future enhancements to neodap's source handling capabilities.