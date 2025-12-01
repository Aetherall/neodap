local neostate = require("neostate")
local Context = require("neodap.sdk.context").Context

describe("Context", function()
  describe("basic functionality", function()
    it("should create a context with nil frame_uri by default", function()
      local ctx = Context:new(nil)
      assert.is_nil(ctx.frame_uri:get())
      ctx:dispose()
    end)

    it("should allow pinning a frame URI", function()
      local ctx = Context:new(nil)
      ctx:pin("dap:session:abc/stack[0]/frame[0]")

      assert.are.equal("dap:session:abc/stack[0]/frame[0]", ctx.frame_uri:get())
      assert.is_true(ctx:is_pinned())
      ctx:dispose()
    end)

    it("should allow unpinning", function()
      local ctx = Context:new(nil)
      ctx:pin("dap:session:abc/stack[0]/frame[0]")
      ctx:unpin()

      assert.is_nil(ctx.frame_uri:get())
      assert.is_false(ctx:is_pinned())
      ctx:dispose()
    end)
  end)

  describe("inheritance", function()
    it("should inherit frame_uri from parent when not pinned", function()
      local parent = Context:new(nil)
      local child = Context:new(parent)

      parent:pin("dap:session:abc/stack[0]/frame[0]")

      assert.are.equal("dap:session:abc/stack[0]/frame[0]", child.frame_uri:get())
      assert.is_false(child:is_pinned())

      parent:dispose()
      child:dispose()
    end)

    it("should override parent when pinned", function()
      local parent = Context:new(nil)
      local child = Context:new(parent)

      parent:pin("dap:session:abc/stack[0]/frame[0]")
      child:pin("dap:session:abc/stack[0]/frame:42")

      assert.are.equal("dap:session:abc/stack[0]/frame[0]", parent.frame_uri:get())
      assert.are.equal("dap:session:abc/stack[0]/frame:42", child.frame_uri:get())
      assert.is_true(child:is_pinned())

      parent:dispose()
      child:dispose()
    end)

    it("should follow parent changes when not pinned", function()
      local parent = Context:new(nil)
      local child = Context:new(parent)

      parent:pin("dap:session:abc/stack[0]/frame[0]")
      assert.are.equal("dap:session:abc/stack[0]/frame[0]", child.frame_uri:get())

      parent:pin("dap:session:xyz/stack[0]/frame[0]")
      assert.are.equal("dap:session:xyz/stack[0]/frame[0]", child.frame_uri:get())

      parent:dispose()
      child:dispose()
    end)

    it("should return to following parent after unpin", function()
      local parent = Context:new(nil)
      local child = Context:new(parent)

      parent:pin("dap:session:abc/stack[0]/frame[0]")
      child:pin("dap:session:abc/stack[0]/frame:42")

      assert.are.equal("dap:session:abc/stack[0]/frame:42", child.frame_uri:get())

      child:unpin()
      assert.are.equal("dap:session:abc/stack[0]/frame[0]", child.frame_uri:get())

      parent:dispose()
      child:dispose()
    end)
  end)

  describe("reactivity", function()
    it("should notify watchers when frame_uri changes", function()
      local ctx = Context:new(nil)
      local observed = {}

      ctx.frame_uri:watch(function(uri)
        table.insert(observed, uri or "nil")
      end)

      ctx:pin("uri1")
      ctx:pin("uri2")
      ctx:unpin()

      assert.are.same({ "uri1", "uri2", "nil" }, observed)
      ctx:dispose()
    end)

    it("should notify child watchers when parent changes", function()
      local parent = Context:new(nil)
      local child = Context:new(parent)
      local observed = {}

      child.frame_uri:watch(function(uri)
        table.insert(observed, uri or "nil")
      end)

      parent:pin("uri1")
      parent:pin("uri2")

      assert.are.same({ "uri1", "uri2" }, observed)

      parent:dispose()
      child:dispose()
    end)

    it("should not notify child watchers when child is pinned", function()
      local parent = Context:new(nil)
      local child = Context:new(parent)
      local observed = {}

      child:pin("child_uri")

      child.frame_uri:watch(function(uri)
        table.insert(observed, uri or "nil")
      end)

      parent:pin("parent_uri1")
      parent:pin("parent_uri2")

      -- Child is pinned, so parent changes don't affect it
      assert.are.same({}, observed)
      assert.are.equal("child_uri", child.frame_uri:get())

      parent:dispose()
      child:dispose()
    end)
  end)

  describe("parent accessor", function()
    it("should return parent context", function()
      local parent = Context:new(nil)
      local child = Context:new(parent)

      assert.are.equal(parent, child:parent())
      assert.is_nil(parent:parent())

      parent:dispose()
      child:dispose()
    end)
  end)
end)
