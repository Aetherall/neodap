#!/usr/bin/env python3
"""Test fixture for stepping operations (step_over, step_into, step_out)"""


def inner_function(x):
    result = x * 2  # Line 6 - step into lands here
    return result   # Line 7


def outer_function(value):
    a = value + 1       # Line 11
    b = inner_function(a)  # Line 12 - step over skips inner, step into enters
    c = b + 10          # Line 13 - step out from inner lands here
    return c            # Line 14


def main():
    result = outer_function(5)  # Line 18
    print(f"Result: {result}")   # Line 19
    return result


if __name__ == "__main__":
    main()
