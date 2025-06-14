---
applyTo: '**'
---

# Project Description

Neodap is a SDK for building DAP client plugins for Neovim.
It provides a comprehensive api for interacting with the lifecycle of dap sessions, breakpoints, threads, stacks, frames, variables, and more.

# Testing

To run the tests, you can use the following command:

```bash
nix run .#test spec/core/neodap_core.spec.lua -- --filter <part of the test name>
```
