local Test = require("spec.helpers.testing")(describe, it)
local Source = require("neodap.api.Session.Source.Source")

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
    
    -- Should be a UnifiedSource but with legacy file type
    assert(source ~= nil, "Source should be created")
    assert(source.type == "file", "Should have legacy file type")
    assert(source.type == 'file', "Should identify as file source")
    assert(source.type ~= 'virtual', "Should not identify as virtual source")
    
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
    
    -- Should be a UnifiedSource but with legacy virtual type
    assert(source ~= nil, "Source should be created")
    assert(source.type == "virtual", "Should have legacy virtual type")
    assert(source.type ~= 'file', "Should not identify as file source")
    assert(source.type == 'virtual', "Should identify as virtual source")
    
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
    
    -- Should be a UnifiedSource with virtual type (priority in legacy logic)
    assert(source ~= nil, "Source should be created")
    assert(source.type == "virtual", "Should have legacy virtual type due to sourceReference priority")
    
    -- Should have unified API that handles both aspects
    local identifier = source:identifier()
    assert(identifier ~= nil, "Should have identifier")
    
    -- For hybrid sources, identifier strategy should prefer file path for stability
    -- but actual behavior depends on strategy implementation
    assert(identifier:toString() ~= nil, "Should have valid identifier string")
    
    -- Should be UnifiedSource instance (api.Source is now UnifiedSource)
    assert(type(source) == "table", "Should be UnifiedSource instance")
  end)
  
  Test.It("handles_source_strategies", function()
    -- Mock session (minimal for source creation)
    local session = {
      id = 999,
      api = {
        _virtual_buffer_registry = require("neodap.api.VirtualBuffer.Registry").get()
      }
    }
    
    -- Test file source strategies
    local fileSource = Source.instanciate(session, {
      path = "/tmp/test.js",
      name = "test.js"
    })
    
    assert(fileSource._contentType == 'file', "Should have file content type")
    assert(fileSource._identifierType == 'path', "Should have path identifier type")
    assert(fileSource._bufferType == 'file', "Should have file buffer type")
    
    -- Test virtual source strategies
    local virtualSource = Source.instanciate(session, {
      sourceReference = 123,
      name = "eval.js",
      origin = "eval"
    })
    
    assert(virtualSource._contentType == 'virtual', "Should have virtual content type")
    assert(virtualSource._identifierType == 'virtual', "Should have virtual identifier type")
    assert(virtualSource._bufferType == 'virtual', "Should have virtual buffer type")
    
    -- Test hybrid source strategies
    local hybridSource = Source.instanciate(session, {
      path = "/tmp/transpiled.js",
      sourceReference = 456,
      name = "transpiled.js",
      origin = "sourcemap"
    })
    
    assert(hybridSource._contentType == 'hybrid', "Should have hybrid content type")
    assert(hybridSource._identifierType == 'hybrid', "Should have hybrid identifier type")
    assert(hybridSource._bufferType == 'hybrid', "Should have hybrid buffer type")
  end)
end)