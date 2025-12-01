#!/usr/bin/env python3
# Python program with nested function calls for stack testing

def level_3():
    """Innermost function"""
    x = 42
    return x  # Breakpoint here

def level_2():
    """Middle function"""
    y = level_3()
    return y + 1

def level_1():
    """Outer function"""
    z = level_2()
    return z + 2

def main():
    """Entry point"""
    result = level_1()
    print(f"Result: {result}")

if __name__ == "__main__":
    main()
