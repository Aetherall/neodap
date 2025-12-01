#!/usr/bin/env python3
"""
Test program that waits for a debugger to attach.
Runs a debugpy server in listen mode.
"""
import sys
import debugpy

# Listen for debugger connection
port = int(sys.argv[1]) if len(sys.argv) > 1 else 5678
print(f"Debugpy listening on port {port}", flush=True)

try:
    debugpy.listen(("127.0.0.1", port))
except Exception as e:
    print(f"Failed to listen on port {port}: {e}", flush=True)
    sys.exit(1)

print("Waiting for debugger to attach...", flush=True)
debugpy.wait_for_client()
print("Debugger attached!", flush=True)

# Simple code to debug
x = 42
y = x + 1  # Breakpoint here
print(f"Result: {y}")
