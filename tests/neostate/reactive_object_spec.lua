local neostate = require("neostate")

neostate.setup({
  -- trace = true,
  -- debug_context = true,
})

describe("Reactive Object Pattern", function()
  -- Define a class-like factory
  local function Room(name)
    local self = neostate.Disposable({}, nil, "Room")

    -- Public reactive property
    self.name = neostate.Signal(name, "Room.name")
    self.name:set_parent(self) -- Bind lifecycle

    -- Message List
    self.messages = neostate.List("Room.messages")
    self.messages:set_parent(self)

    function self.send(text)
      local msg = neostate.Disposable({}, nil, "Message")
      msg.text = neostate.Signal(text, "Message.text")
      msg.text:set_parent(msg)
      self.messages:add(msg)
      return msg
    end

    function self.on_message(fn)
      return self.messages:on_added(function(msg)
        fn(msg)
      end)
    end

    return self
  end

  it("should allow subscribing to property changes", function()
    local room = Room("Lobby")
    local last_name = nil

    -- Using use to get the value (unwrapped) and current value
    -- Store unsub to keep listener alive (weak listener tables)
    local unsub = room.name:use(function(n)
      last_name = n
    end)

    assert.are.equal("Lobby", last_name)

    room.name:set("Kitchen")
    assert.are.equal("Kitchen", last_name)

    unsub() -- cleanup
  end)

  it("should allow subscribing to ONLY future changes", function()
    local room = Room("Lobby")
    local changes = {}

    -- Using watch to get unwrapped values
    room.name:watch(function(val)
      table.insert(changes, val)
    end)

    room.name:set("Kitchen")
    assert.are.same({ "Kitchen" }, changes)
  end)

  it("should allow sending and receiving messages", function()
    local room = Room("Chat")
    local received = {}

    room.on_message(function(msg)
      table.insert(received, msg.text:get())
    end)

    room.send("Hello")
    room.send("World")

    assert.are.same({ "Hello", "World" }, received)
    assert.are.equal(2, #room.messages._items)
  end)

  it("should allow subscribing to message content changes", function()
    local room = Room("Chat")
    local edits = {}

    room.on_message(function(msg)
      msg.text:watch(function(new_text)
        table.insert(edits, new_text)
      end)
    end)

    local msg = room.send("Hello")
    msg.text:set("Hello World")

    assert.are.same({ "Hello World" }, edits)
  end)
end)
