#!/usr/bin/env python3
# Simple counter loop for testing breakpoint + continue

def count_up(limit):
    counter = 0
    for i in range(limit):
        counter += 1  # Breakpoint here (line 7)
        print(f"Counter: {counter}")
    return counter

if __name__ == "__main__":
    result = count_up(5)
    print(f"Final: {result}")
