#!/usr/bin/env python3
"""Test script with multiple exception points for testing enable/disable"""

import time

def might_fail(value):
    """Function that raises based on input"""
    if value == 0:
        raise ValueError("Value cannot be zero")
    return 100 / value

def main():
    print("Starting multi-exception test")

    # First breakpoint location
    x = 1  # Line 16: set breakpoint here

    # First exception - will be caught
    try:
        result = might_fail(0)
    except ValueError as e:
        print(f"Caught first exception: {e}")

    print("Continuing after first exception...")

    # Second exception - will be caught
    try:
        result = might_fail(0)
    except ValueError as e:
        print(f"Caught second exception: {e}")

    print("Continuing after second exception...")

    # Success path
    result = might_fail(5)
    print(f"Result: {result}")

    print("Program completed successfully")

if __name__ == "__main__":
    main()
