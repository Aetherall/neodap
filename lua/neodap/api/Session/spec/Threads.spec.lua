local Threads = require('neodap.api.Session.Threads')

describe('Threads collection', function()
  it('should inherit from Collection', function()
    local threads = Threads.create()
    
    -- Test basic Collection methods are available
    assert.is_function(threads.add)
    assert.is_function(threads.remove)
    assert.is_function(threads.findBy)
    assert.is_function(threads.whereBy)
    assert.is_function(threads.isEmpty)
    assert.is_function(threads.count)
    assert.is_function(threads.each)
    assert.is_function(threads.filter)
    
    -- Test Threads-specific methods
    assert.is_function(threads.eachStopped)
    assert.is_function(threads.eachRunning)
  end)
  
  it('should support O(1) status-based filtering', function()
    local threads = Threads.create()
    
    -- Mock thread objects
    local stoppedThread = { id = 1, stopped = true }
    local runningThread = { id = 2, stopped = false }
    
    threads:add(stoppedThread)
    threads:add(runningThread)
    
    -- Test O(1) status filtering
    local stopped = threads:whereBy("status", "stopped")
    assert.equals(1, stopped:count())
    assert.equals(stoppedThread, stopped:first())
    
    local running = threads:whereBy("status", "running")
    assert.equals(1, running:count())
    assert.equals(runningThread, running:first())
    
    -- Test convenience methods
    local stoppedIterator = threads:eachStopped()
    local first_stopped = stoppedIterator()
    assert.equals(stoppedThread, first_stopped)
    
    local runningIterator = threads:eachRunning()
    local first_running = runningIterator()
    assert.equals(runningThread, first_running)
  end)
end)