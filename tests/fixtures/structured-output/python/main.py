# Structured console output for testing output expansion
# Note: Python debugpy may not support variablesReference in output events
# like js-debug does, so this fixture may produce plain text output

# Simple object
user = {
    "name": "Alice",
    "age": 30,
    "email": "alice@example.com"
}

# Nested object
config = {
    "server": {
        "host": "localhost",
        "port": 8080,
        "ssl": {
            "enabled": True,
            "cert": "/path/to/cert"
        }
    },
    "database": {
        "url": "postgres://localhost/db",
        "pool": {"min": 5, "max": 20}
    }
}

# Array with objects
items = [
    {"id": 1, "name": "item1", "tags": ["a", "b"]},
    {"id": 2, "name": "item2", "tags": ["c", "d", "e"]},
    {"id": 3, "name": "item3", "tags": []}
]

# Complex nested structure
report = {
    "metadata": {
        "version": "1.0"
    },
    "data": {
        "users": [user],
        "config": config
    },
    "stats": {
        "total": 100,
        "active": 85
    }
}

breakpoint()

# Log structured objects
print("User:", user)
print("Config:", config)
print("Items:", items)
print("Report:", report)

print("Structured output test complete")
