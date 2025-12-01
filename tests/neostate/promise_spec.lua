describe("Promise", function()
  local neostate = require("neostate")

  before_each(function()
    neostate.setup({ trace = false, debug_context = false })
  end)

  describe("Promise creation", function()
    it("should create a promise in pending state", function()
      local promise = neostate.Promise()
      assert.is_true(promise:is_pending())
      assert.is_false(promise:is_settled())
    end)

    it("should execute executor immediately", function()
      local executed = false
      local promise = neostate.Promise(function(resolve, reject)
        executed = true
        resolve(42)
      end)
      assert.is_true(executed)
      assert.is_true(promise:is_settled())
    end)

    it("should resolve with executor", function()
      local promise = neostate.Promise(function(resolve, reject)
        resolve("success")
      end)
      assert.equals("fulfilled", promise._state)
      assert.equals("success", promise._result)
    end)

    it("should reject with executor", function()
      local promise = neostate.Promise(function(resolve, reject)
        reject("error")
      end)
      assert.equals("rejected", promise._state)
      assert.equals("error", promise._error)
    end)

    it("should catch executor errors", function()
      local promise = neostate.Promise(function(resolve, reject)
        error("executor error")
      end)
      assert.equals("rejected", promise._state)
      assert.is_not_nil(promise._error)
    end)
  end)

  describe("Promise resolution", function()
    it("should resolve a promise", function()
      local promise = neostate.Promise()
      promise:resolve(123)
      assert.equals("fulfilled", promise._state)
      assert.equals(123, promise._result)
    end)

    it("should reject a promise", function()
      local promise = neostate.Promise()
      promise:reject("failed")
      assert.equals("rejected", promise._state)
      assert.equals("failed", promise._error)
    end)

    it("should not resolve twice", function()
      local promise = neostate.Promise()
      promise:resolve("first")
      promise:resolve("second")
      assert.equals("first", promise._result)
    end)

    it("should not reject after resolve", function()
      local promise = neostate.Promise()
      promise:resolve("success")
      promise:reject("error")
      assert.equals("fulfilled", promise._state)
      assert.equals("success", promise._result)
    end)
  end)

  describe("then_do callbacks", function()
    it("should call then_do callback on resolution", function()
      local callback_value = nil
      local promise = neostate.Promise()
      promise:then_do(function(value)
        callback_value = value
      end)
      promise:resolve(42)
      assert.equals(42, callback_value)
    end)

    it("should call then_do immediately if already resolved", function()
      local callback_value = nil
      local promise = neostate.Promise(function(resolve)
        resolve(99)
      end)
      promise:then_do(function(value)
        callback_value = value
      end)
      assert.equals(99, callback_value)
    end)

    it("should not call then_do on rejection", function()
      local called = false
      local promise = neostate.Promise()
      promise:then_do(function()
        called = true
      end)
      promise:reject("error")
      assert.is_false(called)
    end)

    it("should allow chaining then_do", function()
      local count = 0
      local promise = neostate.Promise()
      promise:then_do(function() count = count + 1 end)
        :then_do(function() count = count + 1 end)
      promise:resolve(1)
      assert.equals(2, count)
    end)
  end)

  describe("catch_do callbacks", function()
    it("should call catch_do callback on rejection", function()
      local callback_error = nil
      local promise = neostate.Promise()
      promise:catch_do(function(err)
        callback_error = err
      end)
      promise:reject("failed")
      assert.equals("failed", callback_error)
    end)

    it("should call catch_do immediately if already rejected", function()
      local callback_error = nil
      local promise = neostate.Promise(function(_, reject)
        reject("immediate error")
      end)
      promise:catch_do(function(err)
        callback_error = err
      end)
      assert.equals("immediate error", callback_error)
    end)

    it("should not call catch_do on resolution", function()
      local called = false
      local promise = neostate.Promise()
      promise:catch_do(function()
        called = true
      end)
      promise:resolve("success")
      assert.is_false(called)
    end)
  end)

  describe("await", function()
    it("should return non-promise values directly", function()
      local completed = false

      neostate.void(function()
        assert.equals(42, neostate.await(42))
        assert.equals("hello", neostate.await("hello"))
        assert.equals(true, neostate.await(true))
        assert.equals(nil, neostate.await(nil))

        local tbl = { a = 1, b = 2 }
        assert.equals(tbl, neostate.await(tbl))

        completed = true
      end)()

      -- Wait for async work to complete with timeout
      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")
      assert.is_true(completed, "Completion flag was not set")
    end)

    it("should await a resolved promise", function()
      local completed = false
      local promise = neostate.Promise(function(resolve)
        resolve(100)
      end)

      neostate.void(function()
        local result = neostate.await(promise)
        assert.equals(100, result)
        completed = true
      end)()

      -- Wait for async work to complete with timeout
      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")
      assert.is_true(completed, "Completion flag was not set")
    end)

    it("should await a promise that resolves later", function()
      local promise = neostate.Promise()
      local result_holder = {}
      local completed = false

      neostate.void(function()
        result_holder.value = neostate.await(promise)
        completed = true
      end)()

      -- Promise not resolved yet
      assert.is_nil(result_holder.value)

      -- Resolve the promise
      promise:resolve(200)

      -- Wait for async work to complete
      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")

      -- Result should now be available
      assert.equals(200, result_holder.value)
    end)

    it("should throw error on rejected promise", function()
      local promise = neostate.Promise(function(_, reject)
        reject("promise error")
      end)

      local error_caught = false
      local completed = false

      neostate.void(function()
        local ok, err = pcall(function()
          neostate.await(promise)
        end)
        if not ok then
          error_caught = true
          assert.is_not_nil(err)
        end
        completed = true
      end)()

      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")
      assert.is_true(error_caught, "Error was not caught")
    end)

    it("should work with multiple awaits in sequence", function()
      local results = {}
      local completed = false

      neostate.void(function()
        local p1 = neostate.Promise(function(resolve)
          resolve(1)
        end)
        results[1] = neostate.await(p1)

        local p2 = neostate.Promise(function(resolve)
          resolve(2)
        end)
        results[2] = neostate.await(p2)

        local p3 = neostate.Promise(function(resolve)
          resolve(3)
        end)
        results[3] = neostate.await(p3)

        completed = true
      end)()

      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")
      assert.equals(1, results[1])
      assert.equals(2, results[2])
      assert.equals(3, results[3])
    end)
  end)

  describe("settle", function()
    it("should return non-promise values as (value, nil)", function()
      local completed = false

      neostate.void(function()
        local result, err = neostate.settle(42)
        assert.equals(42, result)
        assert.is_nil(err)

        result, err = neostate.settle("test")
        assert.equals("test", result)
        assert.is_nil(err)

        local tbl = { x = 10 }
        result, err = neostate.settle(tbl)
        assert.equals(tbl, result)
        assert.is_nil(err)

        completed = true
      end)()

      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")
    end)

    it("should settle a resolved promise", function()
      local completed = false
      local promise = neostate.Promise(function(resolve)
        resolve(300)
      end)

      neostate.void(function()
        local result, err = neostate.settle(promise)
        assert.equals(300, result)
        assert.is_nil(err)
        completed = true
      end)()

      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")
    end)

    it("should settle a rejected promise", function()
      local completed = false
      local promise = neostate.Promise(function(_, reject)
        reject("settle error")
      end)

      neostate.void(function()
        local result, err = neostate.settle(promise)
        assert.is_nil(result)
        assert.equals("settle error", err)
        completed = true
      end)()

      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")
    end)

    it("should settle a promise that resolves later", function()
      local promise = neostate.Promise()
      local result_holder = {}
      local completed = false

      neostate.void(function()
        result_holder.result, result_holder.err = neostate.settle(promise)
        completed = true
      end)()

      -- Not settled yet
      assert.is_nil(result_holder.result)

      -- Resolve the promise
      promise:resolve(400)

      -- Wait for async work to complete
      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")

      -- Result should now be available
      assert.equals(400, result_holder.result)
      assert.is_nil(result_holder.err)
    end)

    it("should work with multiple settles in sequence", function()
      local results = {}
      local completed = false

      neostate.void(function()
        local p1 = neostate.Promise(function(resolve)
          resolve(10)
        end)
        results[1], results.err1 = neostate.settle(p1)

        local p2 = neostate.Promise(function(_, reject)
          reject("error2")
        end)
        results[2], results.err2 = neostate.settle(p2)

        local p3 = neostate.Promise(function(resolve)
          resolve(30)
        end)
        results[3], results.err3 = neostate.settle(p3)

        completed = true
      end)()

      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")
      assert.equals(10, results[1])
      assert.is_nil(results.err1)
      assert.is_nil(results[2])
      assert.equals("error2", results.err2)
      assert.equals(30, results[3])
      assert.is_nil(results.err3)
    end)
  end)

  describe("void wrapper", function()
    it("should run async function", function()
      local executed = false
      neostate.void(function()
        executed = true
      end)()

      local success = vim.wait(100, function() return executed end, 10)
      assert.is_true(success, "Async work did not complete in time")
      assert.is_true(executed)
    end)

    it("should allow await in void", function()
      local completed = false
      local promise = neostate.Promise(function(resolve)
        vim.defer_fn(function()
          resolve(500)
        end, 10)
      end)

      local result_holder = {}
      neostate.void(function()
        result_holder.value = neostate.await(promise)
        completed = true
      end)()

      -- Wait for promise to resolve
      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")
      assert.equals(500, result_holder.value)
    end)

    it("should handle errors gracefully", function()
      local error_handled = false
      -- Mock vim.notify to catch the error
      local old_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("test error in void") then
          error_handled = true
        end
      end

      neostate.void(function()
        error("test error in void")
      end)()

      local success = vim.wait(100, function() return error_handled end, 10)
      vim.notify = old_notify -- Restore

      assert.is_true(success, "Error was not handled in time")
      assert.is_true(error_handled, "Error notification was not called")
    end)
  end)

  describe("disposable lifecycle", function()
    it("should dispose promise", function()
      local promise = neostate.Promise()
      promise:dispose()
      assert.is_true(promise._disposed)
    end)

    it("should reject pending promise on dispose", function()
      local promise = neostate.Promise()
      assert.equals("pending", promise._state)
      promise:dispose()
      assert.equals("rejected", promise._state)
      assert.is_not_nil(promise._error)
    end)

    it("should not affect settled promise on dispose", function()
      local promise = neostate.Promise(function(resolve)
        resolve(42)
      end)
      assert.equals("fulfilled", promise._state)
      promise:dispose()
      assert.equals("fulfilled", promise._state)
      assert.equals(42, promise._result)
    end)

    it("should clean up parent-child relationship", function()
      local parent = neostate.Disposable({}, nil, "Parent")
      local promise = neostate.Promise(nil, "ChildPromise")
      promise:set_parent(parent)

      parent:dispose()
      assert.is_true(promise._disposed)
    end)
  end)

  describe("integration tests", function()
    it("should work with mixed promises and values", function()
      local results = {}
      local completed = false

      neostate.void(function()
        -- Mix of promises and regular values
        results[1] = neostate.await(100)  -- regular value

        local promise = neostate.Promise(function(resolve)
          resolve(200)
        end)
        results[2] = neostate.await(promise)  -- promise

        results[3] = neostate.await("hello")  -- string value

        -- settle also works with non-promises
        results[4], results.err4 = neostate.settle(300)
        results[5], results.err5 = neostate.settle(neostate.Promise(function(resolve)
          resolve(400)
        end))

        completed = true
      end)()

      local success = vim.wait(100, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")

      assert.equals(100, results[1])
      assert.equals(200, results[2])
      assert.equals("hello", results[3])
      assert.equals(300, results[4])
      assert.is_nil(results.err4)
      assert.equals(400, results[5])
      assert.is_nil(results.err5)
    end)

    it("should chain multiple async operations", function()
      local results = {}
      local completed = false

      neostate.void(function()
        -- First async operation
        local promise1 = neostate.Promise(function(resolve)
          vim.defer_fn(function()
            resolve(10)
          end, 10)
        end)
        local result1 = neostate.await(promise1)
        table.insert(results, result1)

        -- Second async operation using first result
        local promise2 = neostate.Promise(function(resolve)
          vim.defer_fn(function()
            resolve(result1 * 2)
          end, 10)
        end)
        local result2 = neostate.await(promise2)
        table.insert(results, result2)

        -- Third async operation
        local promise3 = neostate.Promise(function(resolve)
          vim.defer_fn(function()
            resolve(result2 + 5)
          end, 10)
        end)
        local result3 = neostate.await(promise3)
        table.insert(results, result3)

        completed = true
      end)()

      -- Wait for all operations to complete
      local success = vim.wait(200, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")

      assert.equals(3, #results)
      assert.equals(10, results[1])
      assert.equals(20, results[2])
      assert.equals(25, results[3])
    end)

    it("should handle mixed settle and await", function()
      local results = {}
      local completed = false

      neostate.void(function()
        -- This one will succeed
        local promise1 = neostate.Promise(function(resolve)
          resolve(100)
        end)
        local result1 = neostate.await(promise1)
        table.insert(results, { success = result1 })

        -- This one will fail
        local promise2 = neostate.Promise(function(_, reject)
          reject("intentional error")
        end)
        local result2, err2 = neostate.settle(promise2)
        table.insert(results, { error = err2 })

        -- This one will succeed
        local promise3 = neostate.Promise(function(resolve)
          resolve(200)
        end)
        local result3, err3 = neostate.settle(promise3)
        table.insert(results, { success = result3, error = err3 })

        completed = true
      end)()

      local success = vim.wait(200, function() return completed end, 10)
      assert.is_true(success, "Async work did not complete in time")

      assert.equals(3, #results)
      assert.equals(100, results[1].success)
      assert.equals("intentional error", results[2].error)
      assert.equals(200, results[3].success)
      assert.is_nil(results[3].error)
    end)
  end)
end)
