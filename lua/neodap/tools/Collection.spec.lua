-- Collection Enhanced Features Test Suite

local Collection = require('neodap.tools.Collection')

describe("Collection Enhanced Features", function()
  
  describe("Basic Functionality", function()
    it("should work with enhanced index definitions", function()
      local collection = Collection.create({
        items = {{id = 1, name = 'item1'}, {id = 2, name = 'item2'}},
        indexes = {
          id = { indexer = function(item) return item.id end, unique = true },
          name = { indexer = function(item) return item.name end, unique = false }
        }
      })
      
      assert.are.equal(2, collection:count())
      assert.is_not_nil(collection:getBy('id', 1))
      assert.is_not_nil(collection:findBy('id', 2))
      assert.are.equal('item1', collection:getBy('id', 1).name)
    end)
  end)
  
  describe("Enhanced Index Definitions", function()
    it("should support unique and multi-value indexes", function()
      local collection = Collection.create({
        items = {{id = 1, type = 'A'}, {id = 2, type = 'A'}, {id = 3, type = 'B'}},
        indexes = {
          id = { indexer = function(item) return item.id end, unique = true },
          type = { indexer = function(item) return item.type end, unique = false }
        }
      })
      
      assert.are.equal(3, collection:count())
      
      -- Unique index access
      assert.is_not_nil(collection:findBy('id', 2))
      assert.are.equal(2, collection:findBy('id', 2).id)
      
      -- Multi-value index access
      local typeA = collection:whereBy('type', 'A')
      assert.are.equal(2, typeA:count())
      
      local typeB = collection:whereBy('type', 'B')
      assert.are.equal(1, typeB:count())
    end)
  end)
  
  describe("Type Safety", function()
    it("should enforce unique vs multi-value index usage", function()
      local collection = Collection.create({
        items = {{id = 1, type = 'A'}},
        indexes = {
          id = { indexer = function(item) return item.id end, unique = true },
          type = { indexer = function(item) return item.type end, unique = false }
        }
      })
      
      -- These should work
      assert.has_no_error(function() collection:findBy('id', 1) end)
      assert.has_no_error(function() collection:whereBy('type', 'A') end)
      
      -- These should error
      assert.has_error(function() collection:findBy('type', 'A') end)
      assert.has_error(function() collection:whereBy('id', 1) end)
    end)
  end)
  
  describe("Performance Features", function()
    it("should provide O(1) access for serialization-based indexes", function()
      local items = {}
      for i = 1, 1000 do
        table.insert(items, {id = i, category = 'cat' .. (i % 5)})
      end
      
      local collection = Collection.create({
        items = items,
        indexes = {
          id = { indexer = function(item) return item.id end, unique = true },
          category = { indexer = function(item) return item.category end, unique = false }
        }
      })
      
      -- Should be O(1) lookups
      assert.is_not_nil(collection:findBy('id', 500))
      
      local cat2Items = collection:whereBy('category', 'cat2')
      assert.are.equal(200, cat2Items:count()) -- Every 5th item starting from 2
    end)
  end)
  
  describe("Multi-value Index Operations", function()
    it("should handle add/remove operations correctly", function()
      local collection = Collection.create({
        indexes = {
          id = { indexer = function(item) return item.id end, unique = true },
          type = { indexer = function(item) return item.type end, unique = false }
        }
      })
      
      -- Add items
      collection:add({id = 1, type = 'A'})
      collection:add({id = 2, type = 'A'})
      collection:add({id = 3, type = 'B'})
      
      assert.are.equal(3, collection:count())
      assert.are.equal(2, collection:whereBy('type', 'A'):count())
      
      -- Remove item
      local itemToRemove = collection:findBy('id', 2)
      collection:remove(itemToRemove)
      
      assert.are.equal(2, collection:count())
      assert.are.equal(1, collection:whereBy('type', 'A'):count())
      assert.is_nil(collection:findBy('id', 2))
    end)
  end)
  
  describe("createEmpty Functionality", function()
    it("should preserve index definitions in empty collections", function()
      local original = Collection.create({
        items = {{id = 1, type = 'A'}},
        indexes = {
          id = { indexer = function(item) return item.id end, unique = true },
          type = { indexer = function(item) return item.type end, unique = false }
        }
      })
      
      local empty = original:createEmpty()
      assert.are.equal(0, empty:count())
      
      -- Should still have the same index capabilities
      empty:add({id = 10, type = 'C'})
      assert.is_not_nil(empty:findBy('id', 10))
      assert.are.equal(1, empty:whereBy('type', 'C'):count())
    end)
  end)
  
  describe("getAllBy Method", function()
    it("should return all matches for both unique and multi-value indexes", function()
      local collection = Collection.create({
        items = {{id = 1, type = 'A'}, {id = 2, type = 'A'}, {id = 3, type = 'B'}},
        indexes = {
          id = { indexer = function(item) return item.id end, unique = true },
          type = { indexer = function(item) return item.type end, unique = false }
        }
      })
      
      -- Unique index - should return collection with 1 item
      local byId = collection:getAllBy('id', 2)
      assert.are.equal(1, byId:count())
      
      -- Multi-value index - should return collection with 2 items
      local byType = collection:getAllBy('type', 'A')
      assert.are.equal(2, byType:count())
    end)
  end)
  
end)