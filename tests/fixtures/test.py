#!/usr/bin/env python3
"""Simple Python program for DAP testing"""

def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

def greet(name):
    message = f"Hello, {name}!"
    print(message)
    return message

def main():
    print("Starting test program...")
    
    # Line 18 - Good breakpoint location
    result1 = greet("World")
    
    # Line 21 - Another breakpoint location
    result2 = fibonacci(5)
    print(f"Fibonacci(5) = {result2}")
    
    # Line 25 - Final breakpoint
    sum_result = result2 + 10
    print(f"Sum = {sum_result}")
    
    print("Test program finished!")
    return sum_result

if __name__ == "__main__":
    main()
