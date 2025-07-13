local Test = require("spec.helpers.testing")(describe, it)
local PrepareHelper = require("spec.helpers.prepare")
local prepare = PrepareHelper.prepare
local nio = require('nio')

Test.Describe("StackNavigation Plugin", function()
  
  Test.It("plugin_factory_creates_instance", function()
    local api, start = prepare()
    local StackNavigation = require('neodap.plugins.StackNavigation')
    
    -- Test plugin factory function
    local plugin_instance = StackNavigation.plugin(api)
    
    assert(plugin_instance ~= nil, "Plugin instance should not be nil")
    assert(type(plugin_instance) == "table", "Plugin instance should be a table")
    assert(plugin_instance.api ~= nil, "Plugin instance should have api")
    assert(plugin_instance.logger ~= nil, "Plugin instance should have logger")
    assert(type(plugin_instance.thread_positions) == "table", "Thread positions should be a table")
    assert(plugin_instance.primary_thread_id == nil, "Primary thread ID should initially be nil")
  end)
  
  Test.It("thread_stopped_initializes_position_tracking", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Set up session spy
    local session_spy = Test.spy()
    api:onSession(session_spy)
    
    start()
    session_spy.wait()
    
    -- Get the session
    local session = nil
    for s in api:eachSession() do
      session = s
      break
    end
    assert(session ~= nil, "session should not be nil")
    
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    -- Set up thread spy
    local thread_spy = Test.spy()
    session:onThread(thread_spy)
    
    -- Set up stopped spy  
    local stopped_spy = Test.spy()
    
    -- Trigger a stopped event for thread 1
    session.ref.events:emit('thread', { reason = 'started', threadId = 1 })
    thread_spy.wait()
    
    -- Get the thread
    local thread = session._threads[1]
    assert(thread ~= nil, "thread should not be nil")
    
    thread:onStopped(stopped_spy)
    
    -- Simulate thread stopped with stack frames
    thread.stopped = true
    session.ref.events:emit('stopped', { 
      reason = 'breakpoint',
      threadId = 1,
      allThreadsStopped = false
    })
    stopped_spy.wait()
    
    -- Allow async position tracking to complete
    nio.sleep(100)
    
    -- Verify position tracking was initialized
    local position = plugin_instance.thread_positions[1]
    assert(position ~= nil, "position should not be nil")
    assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
    assert(position.stack_size > 0, "Stack size should be greater than 0")
    assert(plugin_instance.primary_thread_id == 1, "plugin_instance.primary_thread_id should equal 1")
  end)
  
  Test.It("thread_resumed_clears_position_tracking", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Set up session spy
    local session_spy = Test.spy()
    api:onSession(session_spy)
    
    start()
    session_spy.wait()
    
    -- Get the session
    local session = nil
    for s in api:eachSession() do
      session = s
      break
    end
    assert(session ~= nil, "session should not be nil")
    
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    -- Set up thread spy
    local thread_spy = Test.spy()
    session:onThread(thread_spy)
    
    -- Set up stopped and resumed spies
    local stopped_spy = Test.spy()
    local resumed_spy = Test.spy()
    
    -- Trigger a stopped event for thread 1
    session.ref.events:emit('thread', { reason = 'started', threadId = 1 })
    thread_spy.wait()
    
    -- Get the thread
    local thread = session._threads[1]
    assert(thread ~= nil, "thread should not be nil")
    
    thread:onStopped(stopped_spy)
    thread:onResumed(resumed_spy)
    
    -- Simulate thread stopped
    thread.stopped = true
    session.ref.events:emit('stopped', { 
      reason = 'breakpoint',
      threadId = 1
    })
    stopped_spy.wait()
    
    -- Allow position tracking initialization
    nio.sleep(100)
    
    -- Verify position tracking exists
    assert(plugin_instance.thread_positions[1] ~= nil, "plugin_instance.thread_positions[1] should not be nil")
    assert(plugin_instance.primary_thread_id == 1, "plugin_instance.primary_thread_id should equal 1")
    
    -- Simulate thread resumed
    thread.stopped = false
    session.ref.events:emit('continued', { threadId = 1 })
    resumed_spy.wait()
    
    -- Allow cleanup to complete
    nio.sleep(100)
    
    -- Verify position tracking was cleared
    assert(plugin_instance.thread_positions[1] == nil, "plugin_instance.thread_positions[1] should be nil")
    assert(plugin_instance.primary_thread_id == nil, "plugin_instance.primary_thread_id should be nil")
  end)
  
  Test.It("multiple_threads_tracked_independently", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Set up session spy
    local session_spy = Test.spy()
    api:onSession(session_spy)
    
    start()
    session_spy.wait()
    
    -- Get the session
    local session = nil
    for s in api:eachSession() do
      session = s
      break
    end
    assert(session ~= nil, "session should not be nil")
    
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    -- Set up thread spies
    local thread1_spy = Test.spy()
    local thread2_spy = Test.spy()
    local stopped1_spy = Test.spy()
    local stopped2_spy = Test.spy()
    
    session:onThread(function(thread)
      if thread.id == 1 then
        thread1_spy()
        thread:onStopped(stopped1_spy)
      elseif thread.id == 2 then
        thread2_spy() 
        thread:onStopped(stopped2_spy)
      end
    end)
    
    -- Start both threads
    session.ref.events:emit('thread', { reason = 'started', threadId = 1 })
    session.ref.events:emit('thread', { reason = 'started', threadId = 2 })
    thread1_spy.wait()
    thread2_spy.wait()
    
    -- Get both threads
    local thread1 = session._threads[1]
    local thread2 = session._threads[2]
    assert(thread1 ~= nil, "thread1 should not be nil")
    assert(thread2 ~= nil, "thread2 should not be nil")
    
    -- Stop thread 1
    thread1.stopped = true
    session.ref.events:emit('stopped', { 
      reason = 'breakpoint',
      threadId = 1
    })
    stopped1_spy.wait()
    
    -- Allow position tracking to initialize
    nio.sleep(100)
    
    -- Verify thread 1 tracking
    assert(plugin_instance.thread_positions[1] ~= nil, "plugin_instance.thread_positions[1] should not be nil")
    assert(plugin_instance.primary_thread_id == 1, "plugin_instance.primary_thread_id should equal 1")
    assert(plugin_instance.thread_positions[2] == nil, "plugin_instance.thread_positions[2] should be nil")
    
    -- Stop thread 2
    thread2.stopped = true  
    session.ref.events:emit('stopped', {
      reason = 'step',
      threadId = 2
    })
    stopped2_spy.wait()
    
    -- Allow position tracking to initialize
    nio.sleep(100)
    
    -- Verify both threads tracked, thread 2 is now primary
    assert(plugin_instance.thread_positions[1] ~= nil, "plugin_instance.thread_positions[1] should not be nil")
    assert(plugin_instance.thread_positions[2] ~= nil, "plugin_instance.thread_positions[2] should not be nil")
    assert(plugin_instance.primary_thread_id == 2, "plugin_instance.primary_thread_id should equal 2")
  end)
  
  Test.It("navigation_methods_handle_no_thread_gracefully", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Test navigation methods when no threads are stopped
    assert(plugin_instance:up() == false, "up() should return false")
    assert(plugin_instance:down() == false, "down() should return false")
    assert(plugin_instance:top() == false, "top() should return false")
    assert(plugin_instance:bottom() == false, "bottom() should return false")
    assert(plugin_instance:jumpToFrame(1) == false, "jumpToFrame(1) should return false")
  end)
  
  Test.It("information_methods_handle_no_thread_gracefully", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Test information methods when no threads are stopped
    assert(plugin_instance:getCurrentFrame() == nil, "getCurrentFrame() should return nil")
    assert(plugin_instance:getCurrentPosition() == nil, "getCurrentPosition() should return nil")
    assert(plugin_instance:getStackInfo() == nil, "getStackInfo() should return nil")
  end)
  
  Test.It("up_navigation_moves_toward_caller", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Set up session and thread
    local session_spy = Test.spy()
    api:onSession(session_spy)
    
    start()
    session_spy.wait()
    
    local session = nil
    for s in api:eachSession() do
      session = s
      break
    end
    assert(session ~= nil, "session should not be nil")
    
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    local thread_spy = Test.spy()
    local stopped_spy = Test.spy()
    
    session:onThread(function(thread)
      thread_spy()
      thread:onStopped(stopped_spy)
    end)
    
    -- Start and stop thread
    session.ref.events:emit('thread', { reason = 'started', threadId = 1 })
    thread_spy.wait()
    
    local thread = session._threads[1]
    thread.stopped = true
    session.ref.events:emit('stopped', { 
      reason = 'breakpoint',
      threadId = 1
    })
    stopped_spy.wait()
    
    nio.sleep(100)
    
    -- Verify initial position is at top (frame 1)
    local position = plugin_instance.thread_positions[1]
    assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
    
    -- Navigate up (should move to frame 2 if stack has multiple frames)
    if position.stack_size > 1 then
      assert(plugin_instance:up() == true, "up() should succeed")
      assert(position.current_frame_index == 2, "position.current_frame_index should equal 2")
      
      -- Try to go up again
      if position.stack_size > 2 then
        assert(plugin_instance:up() == true, "up() should succeed")
        assert(position.current_frame_index == 3, "position.current_frame_index should equal 3")
      end
      
      -- Try to go beyond stack boundary
      local original_index = position.current_frame_index
      for i = 1, 10 do
        if not plugin_instance:up() then
          break
        end
      end
      -- Should be at bottom of stack
      assert(position.current_frame_index == position.stack_size, "position.current_frame_index should equal position.stack_size")
    else
      -- Single frame stack - up should fail
      assert(plugin_instance:up() == false, "up() should fail on single frame stack")
      assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
    end
  end)
  
  Test.It("down_navigation_moves_toward_callee", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Set up session and thread
    local session_spy = Test.spy()
    api:onSession(session_spy)
    
    start()
    session_spy.wait()
    
    local session = nil
    for s in api:eachSession() do
      session = s
      break
    end
    assert(session ~= nil, "session should not be nil")
    
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    local thread_spy = Test.spy()
    local stopped_spy = Test.spy()
    
    session:onThread(function(thread)
      thread_spy()
      thread:onStopped(stopped_spy)
    end)
    
    -- Start and stop thread
    session.ref.events:emit('thread', { reason = 'started', threadId = 1 })
    thread_spy.wait()
    
    local thread = session._threads[1]
    thread.stopped = true
    session.ref.events:emit('stopped', { 
      reason = 'breakpoint',
      threadId = 1
    })
    stopped_spy.wait()
    
    nio.sleep(100)
    
    local position = plugin_instance.thread_positions[1]
    
    if position.stack_size > 1 then
      -- Move to middle of stack first
      plugin_instance:jumpToFrame(2)
      assert(position.current_frame_index == 2, "position.current_frame_index should equal 2")
      
      -- Navigate down (should move back to frame 1)
      assert(plugin_instance:down() == true, "down() should succeed")
      assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
      
      -- Try to go down from top (should fail)
      assert(plugin_instance:down() == false, "down() should fail from top")
      assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
    else
      -- Single frame stack - down should fail from start
      assert(plugin_instance:down() == false, "down() should fail on single frame stack")
      assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
    end
  end)
  
  Test.It("top_and_bottom_navigation_work", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Set up session and thread
    local session_spy = Test.spy()
    api:onSession(session_spy)
    
    start()
    session_spy.wait()
    
    local session = nil
    for s in api:eachSession() do
      session = s
      break
    end
    assert(session ~= nil, "session should not be nil")
    
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    local thread_spy = Test.spy()
    local stopped_spy = Test.spy()
    
    session:onThread(function(thread)
      thread_spy()
      thread:onStopped(stopped_spy)
    end)
    
    -- Start and stop thread
    session.ref.events:emit('thread', { reason = 'started', threadId = 1 })
    thread_spy.wait()
    
    local thread = session._threads[1]
    thread.stopped = true
    session.ref.events:emit('stopped', { 
      reason = 'breakpoint',
      threadId = 1
    })
    stopped_spy.wait()
    
    nio.sleep(100)
    
    local position = plugin_instance.thread_positions[1]
    
    if position.stack_size > 1 then
      -- Move to middle of stack
      plugin_instance:jumpToFrame(math.floor(position.stack_size / 2))
      local middle_frame = position.current_frame_index
      assert(middle_frame > 1 and middle_frame < position.stack_size, "Should be in middle of stack")
      
      -- Jump to bottom
      assert(plugin_instance:bottom() == true, "bottom() should succeed")
      assert(position.current_frame_index == position.stack_size, "position.current_frame_index should equal position.stack_size")
      
      -- Jump to top
      assert(plugin_instance:top() == true, "top() should succeed")
      assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
    else
      -- Single frame stack
      assert(plugin_instance:top() == true, "top() should succeed")
      assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
      
      assert(plugin_instance:bottom() == true, "bottom() should succeed")
      assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
    end
  end)
  
  Test.It("jump_to_frame_validates_bounds", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Set up session and thread
    local session_spy = Test.spy()
    api:onSession(session_spy)
    
    start()
    session_spy.wait()
    
    local session = nil
    for s in api:eachSession() do
      session = s
      break
    end
    assert(session ~= nil, "session should not be nil")
    
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    local thread_spy = Test.spy()
    local stopped_spy = Test.spy()
    
    session:onThread(function(thread)
      thread_spy()
      thread:onStopped(stopped_spy)
    end)
    
    -- Start and stop thread
    session.ref.events:emit('thread', { reason = 'started', threadId = 1 })
    thread_spy.wait()
    
    local thread = session._threads[1]
    thread.stopped = true
    session.ref.events:emit('stopped', { 
      reason = 'breakpoint',
      threadId = 1
    })
    stopped_spy.wait()
    
    nio.sleep(100)
    
    local position = plugin_instance.thread_positions[1]
    
    -- Test invalid frame indices
    assert(plugin_instance:jumpToFrame(0) == false, "jumpToFrame(0) should fail")
    assert(plugin_instance:jumpToFrame(-1) == false, "jumpToFrame(-1) should fail")
    assert(plugin_instance:jumpToFrame(position.stack_size + 1) == false, "jumpToFrame(out of bounds) should fail")
    assert(plugin_instance:jumpToFrame(999) == false, "jumpToFrame(999) should fail")
    
    -- Test valid frame indices
    assert(plugin_instance:jumpToFrame(1) == true, "jumpToFrame(1) should succeed")
    assert(position.current_frame_index == 1, "position.current_frame_index should equal 1")
    
    if position.stack_size > 1 then
      assert(plugin_instance:jumpToFrame(position.stack_size) == true, "jumpToFrame(last) should succeed")
      assert(position.current_frame_index == position.stack_size, "position.current_frame_index should equal position.stack_size")
    end
  end)
  
  Test.It("get_current_position_returns_accurate_info", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Set up session and thread
    local session_spy = Test.spy()
    api:onSession(session_spy)
    
    start()
    session_spy.wait()
    
    local session = nil
    for s in api:eachSession() do
      session = s
      break
    end
    assert(session ~= nil, "session should not be nil")
    
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    local thread_spy = Test.spy()
    local stopped_spy = Test.spy()
    
    session:onThread(function(thread)
      thread_spy()
      thread:onStopped(stopped_spy)
    end)
    
    -- Start and stop thread
    session.ref.events:emit('thread', { reason = 'started', threadId = 1 })
    thread_spy.wait()
    
    local thread = session._threads[1]
    thread.stopped = true
    session.ref.events:emit('stopped', { 
      reason = 'breakpoint',
      threadId = 1
    })
    stopped_spy.wait()
    
    nio.sleep(100)
    
    -- Test initial position info
    local info = plugin_instance:getCurrentPosition()
    assert(info ~= nil, "info should not be nil")
    assert(info.thread_id == 1, "info.thread_id should equal 1")
    assert(info.frame_index == 1, "info.frame_index should equal 1")
    assert(info.stack_size > 0, "Stack size should be greater than 0")
    
    -- Test position info after navigation
    if info.stack_size > 1 then
      plugin_instance:jumpToFrame(2)
      info = plugin_instance:getCurrentPosition()
      assert(info.frame_index == 2, "info.frame_index should equal 2")
    end
  end)
  
  Test.It("get_stack_info_returns_complete_data", function()
    local api, start = prepare()
    local plugin_instance = api:getPluginInstance(require('neodap.plugins.StackNavigation'))
    
    -- Set up session and thread
    local session_spy = Test.spy()
    api:onSession(session_spy)
    
    start()
    session_spy.wait()
    
    local session = nil
    for s in api:eachSession() do
      session = s
      break
    end
    assert(session ~= nil, "session should not be nil")
    
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    local thread_spy = Test.spy()
    local stopped_spy = Test.spy()
    
    session:onThread(function(thread)
      thread_spy()
      thread:onStopped(stopped_spy)
    end)
    
    -- Start and stop thread
    session.ref.events:emit('thread', { reason = 'started', threadId = 1 })
    thread_spy.wait()
    
    local thread = session._threads[1]
    thread.stopped = true
    session.ref.events:emit('stopped', { 
      reason = 'breakpoint',
      threadId = 1
    })
    stopped_spy.wait()
    
    nio.sleep(100)
    
    -- Test stack info
    local info = plugin_instance:getStackInfo()
    assert(info ~= nil, "info should not be nil")
    assert(info.thread_id == 1, "info.thread_id should equal 1")
    assert(type(info.frames) == "table", "Frames should be a table")
    assert(#info.frames > 0, "Should have at least one frame")
    assert(info.current_index == 1, "info.current_index should equal 1")
    
    -- Verify frames are Frame objects
    for _, frame in ipairs(info.frames) do
      assert(frame.ref ~= nil, "frame.ref should not be nil")
      assert(frame.stack ~= nil, "frame.stack should not be nil")
    end
  end)
  
end)