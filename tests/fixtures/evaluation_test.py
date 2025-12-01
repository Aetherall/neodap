#!/usr/bin/env python3
"""Test fixture for expression evaluation and structured output"""


def test_evaluation():
    simple_number = 42
    simple_string = "hello world"

    user = {
        "name": "Alice",
        "age": 30,
        "address": {
            "city": "Wonderland",
            "zip": "12345"
        }
    }

    numbers = [1, 2, 3, 4, 5]

    # Output some structured data
    print(f"User: {user}")
    print(f"Numbers: {numbers}")

    result = simple_number + 1  # Line 24 - breakpoint here

    return {"simple_number": simple_number, "simple_string": simple_string, "user": user, "numbers": numbers}


if __name__ == "__main__":
    test_evaluation()
