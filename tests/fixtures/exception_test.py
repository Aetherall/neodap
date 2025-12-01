#!/usr/bin/env python3
"""Test script for exception breakpoints testing"""

def divide(a, b):
    """Function that may raise an exception"""
    return a / b

def main():
    print("Starting exception test")

    # This will work fine
    result = divide(10, 2)
    print(f"10 / 2 = {result}")

    # This will raise a ZeroDivisionError
    try:
        result = divide(10, 0)
        print(f"10 / 0 = {result}")
    except ZeroDivisionError as e:
        print(f"Caught exception: {e}")

    # This will raise an uncaught exception
    result = divide(5, 0)  # Line 23: uncaught exception
    print(f"5 / 0 = {result}")

if __name__ == "__main__":
    main()
