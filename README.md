# Neodap WIP

A Neovim Debug Adapter Protocol (DAP) client SDK.


## Goals

Support compound debugging workflows in Neovim, and provide a flexible and extensible SDK for building DAP clients in Neovim.
Current neovim DAP clients provide similar experience to the DAP clients found in other IDEs. However, they often lack the flexibility and extensibility that developers need to create custom debugging workflows. Neodap aims to fill the gap.


## Features

- Good DX with extensive usage of lua annotations
- Run DAP servers in Neovim
- Comprehensive API for DAP clients
- Support for multiple DAP servers
- Support for multiple concurrent DAP sessions

## Non-features

- Not a client, but can be used to build a client


## Usage

```lua

local neodap = require('neodap')

---@param api neodap.api
local function JumpToStoppedFramePlugin(api)

  -- global scope, outlives the session

  -- hook registration syntax
  -- to facilitate annotation type inference
  -- and resource management
  api:onSession(function (session)

    -- session scope, outlives the thread

    -- access to DAP lifecycle events
    -- wrapped in a convenient API
    session:onThread(function (thread)

      -- thread scope, outlives the stopped event

      -- access to DAP low-level events
      thread:onStopped(function (event)

        -- cached accessors with managed lifetime
        -- async support using nio library
        local stack = thread:stack()
        local frame = stack:top()

        if frame then
          -- extensible convenience API for neovim integration
          frame:jump()
        end
      end)
    end)
  end)
end
```




## Development

### Testing

This project uses busted for testing, which is ran within the neovim environment using a custom interpreter, inspired by the really interesting work done by the maintainer of the nvim-dap project.

To run the tests, you can use the following command:

```bash
nix run .#test spec/

# or

nix run .#test $testfile 
```