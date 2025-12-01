#!/usr/bin/env python3
import sys

print("Hello stdout line 1")
print("Hello stdout line 2")
sys.stderr.write("Error on stderr line 1\n")
sys.stderr.write("Error on stderr line 2\n")
print("Final stdout message")

# Breakpoint here
x = 1  # line 11
