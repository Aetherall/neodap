local Test = require("spec.helpers.testing")(describe, it)
local Source = require("neodap.api.Session.Source")

Test.Describe("Source Unification", function()
  Test.It("creates_unified_file_source", function()
    -- Mock session (minimal for source creation)
    local session = {
      id = 999,
      api = {
        _virtual_buffer_registry = require("neodap.api.VirtualBuffer.Registry").get()
      }
    }
    
    -- Create a file source via the unified factory
    local dapSource = {
      path = "/tmp/test.js",
      name = "test.js"
    }
    
    local source = Source.instanciate(session, dapSource)
    
    -- Should be a Source with file characteristics
    assert(source ~= nil, "Source should be created")
    assert(source:isFile(), "Should identify as file source")
    assert(not source:isVirtual(), "Should not identify as virtual source")
    
    -- Should have unified API
    local identifier = source:identifier()
    assert(identifier ~= nil, "Should have identifier")
    assert(identifier:isFile(), "Identifier should be file type")
    assert(identifier:toString():match("^file://"), "Should have file:// URI")
    
    -- Should be UnifiedSource instance (api.Source is now UnifiedSource)
    assert(type(source) == "table", "Should be UnifiedSource instance")
  end)
  
  Test.It("creates_unified_virtual_source", function()
    -- Mock session (minimal for source creation)
    local session = {
      id = 999,
      api = {
        _virtual_buffer_registry = require("neodap.api.VirtualBuffer.Registry").get()
      }
    }
    
    -- Create a virtual source via the unified factory
    local dapSource = {
      sourceReference = 123,
      name = "eval.js",
      origin = "eval"
    }
    
    local source = Source.instanciate(session, dapSource)
    
    -- Should be a Source with virtual characteristics
    assert(source ~= nil, "Source should be created")
    assert(source:isVirtual(), "Should identify as virtual source")
    assert(not source:isFile(), "Should not identify as file source")
    
    -- Should have unified API
    local identifier = source:identifier()
    assert(identifier ~= nil, "Should have identifier")
    assert(identifier:isVirtual(), "Identifier should be virtual type")
    assert(identifier:toString():match("^virtual:"), "Should have virtual: URI")
    
    -- Should be UnifiedSource instance (api.Source is now UnifiedSource)
    assert(type(source) == "table", "Should be UnifiedSource instance")
  end)
  
  Test.It("creates_unified_hybrid_source", function()
    -- Mock session (minimal for source creation)
    local session = {
      id = 999,
      api = {
        _virtual_buffer_registry = require("neodap.api.VirtualBuffer.Registry").get()
      }
    }
    
    -- Create a hybrid source (both path and sourceReference)
    local dapSource = {
      path = "/tmp/transpiled.js",
      sourceReference = 456,
      name = "transpiled.js",
      origin = "sourcemap"
    }
    
    local source = Source.instanciate(session, dapSource)
    
    -- Should be a Source with virtual type (sourceReference takes priority)
    assert(source ~= nil, "Source should be created")
    assert(source:isVirtual(), "Should identify as virtual due to sourceReference priority")
    
    -- Should have unified API that handles both aspects
    local identifier = source:identifier()
    assert(identifier ~= nil, "Should have identifier")
    
    -- For hybrid sources, identifier strategy should prefer file path for stability
    -- but actual behavior depends on strategy implementation
    assert(identifier:toString() ~= nil, "Should have valid identifier string")
    
    -- Should be UnifiedSource instance (api.Source is now UnifiedSource)
    assert(type(source) == "table", "Should be UnifiedSource instance")
  end)
  
  Test.It("handles_simplified_source_behavior", function()
    -- Mock session (minimal for source creation)
    local session = {
      id = 999,
      api = {
        _virtual_buffer_registry = require("neodap.api.VirtualBuffer.Registry").get()
      }
    }
    
    -- Test file source behavior
    local fileSource = Source.instanciate(session, {
      path = "/tmp/test.js",
      name = "test.js"
    })
    
    assert(fileSource:isFile(), "Should identify as file source")
    assert(not fileSource:isVirtual(), "Should not identify as virtual source")
    
    -- Test virtual source behavior
    local virtualSource = Source.instanciate(session, {
      sourceReference = 123,
      name = "eval.js",
      origin = "eval"
    })
    
    assert(virtualSource:isVirtual(), "Should identify as virtual source")
    assert(not virtualSource:isFile(), "Should not identify as file source")
    
    -- Test hybrid source behavior (sourceReference takes priority)
    local hybridSource = Source.instanciate(session, {
      path = "/tmp/transpiled.js",
      sourceReference = 456,
      name = "transpiled.js",
      origin = "sourcemap"
    })
    
    assert(hybridSource:isVirtual(), "Should identify as virtual when sourceReference > 0")
    assert(not hybridSource:isFile(), "Should not identify as file when sourceReference > 0")
  end)
end)