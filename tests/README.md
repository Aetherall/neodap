# JS-Debug Integration Test

This directory contains integration tests for the DAP SDK using the js-debug adapter.

## Prerequisites

You need to have `js-debug-adapter` installed. Install it via npm:

```bash
npm install -g js-debug
```

Or using the VS Code extension approach:

```bash
# Install the VS Code DAP adapter
git clone https://github.com/microsoft/vscode-js-debug
cd vscode-js-debug
npm install
npm run build
```

Then ensure `js-debug-adapter` is in your PATH.

## Running the Test

```bash
nvim -l tests/js-debug-test.lua
```

## What the Test Does

The test verifies the following DAP SDK functionality:

1. **Session Initialization** - Connects to js-debug and initializes the DAP session
2. **Program Launch** - Launches a JavaScript program with debugging enabled
3. **Stack Frame Access** - Retrieves stack trace when hitting a breakpoint
4. **Frame Navigation** - Accesses the top frame from the stack
5. **Scope Exploration** - Lists available scopes (Local, Global, etc.)
6. **Variable Access** - Retrieves variables from scopes
7. **Nested Variable Expansion** - Expands complex objects to inspect nested properties

## Expected Output

When successful, the test will output:

```
=== JS-Debug Stack Frame and Scope Test ===

Initializing session...
✓ Initialized

Launching test.js...
✓ Launched

Waiting for breakpoint...
✓ Hit breakpoint at debugger statement

=== Testing Stack Frame Access ===
✓ Got stack with N frames
✓ Top frame: main (line 18)

=== Testing Scope Exploration ===
✓ Got N scopes
  - Local (expensive: false)
  - Closure (expensive: false)
  - Global (expensive: true)

=== Testing Variable Access ===

Exploring 'Local' scope variables:
✓ Got N variables
  - user: Object (expandable)

    Expanding 'user' object:
      - name: "John Doe"
      - age: 30
      - address: Object (expandable)

        Expanding 'address' object:
          - street: "123 Main St"
          - city: "San Francisco"
          - coordinates: Object (expandable)
      - hobbies: Array(3) (expandable)
  - numbers: Array(5) (expandable)

=== Test Complete ===
All tests passed! ✓
```

## Troubleshooting

### Error: ENOENT: no such file or directory (cmd): 'js-debug-adapter'

This means `js-debug-adapter` is not installed or not in your PATH. Follow the installation instructions above.

### Test hangs or times out

Make sure the JavaScript file (`tests/fixtures/test.js`) is present and contains a `debugger;` statement.
