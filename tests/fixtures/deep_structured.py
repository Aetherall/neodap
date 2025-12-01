#!/usr/bin/env python3
# Python program with deeply nested structured data for testing variable exploration

class Address:
    def __init__(self, street, city, country):
        self.street = street
        self.city = city
        self.country = country

class Company:
    def __init__(self, name, address):
        self.name = name
        self.address = address
        self.departments = []

class Department:
    def __init__(self, name):
        self.name = name
        self.employees = []

class Employee:
    def __init__(self, name, role, skills):
        self.name = name
        self.role = role
        self.skills = skills  # list of strings
        self.metadata = {
            "active": True,
            "level": 5,
            "tags": ["developer", "senior"]
        }

def create_deep_structure():
    # Create deeply nested structure
    address = Address("123 Main St", "San Francisco", "USA")
    company = Company("TechCorp", address)

    # Add departments with employees
    eng = Department("Engineering")
    eng.employees.append(Employee("Alice", "Lead", ["python", "rust", "lua"]))
    eng.employees.append(Employee("Bob", "Senior", ["javascript", "typescript"]))

    ops = Department("Operations")
    ops.employees.append(Employee("Charlie", "Manager", ["terraform", "kubernetes"]))

    company.departments.append(eng)
    company.departments.append(ops)

    # Also create a deeply nested dict for testing
    nested_dict = {
        "level1": {
            "level2": {
                "level3": {
                    "level4": {
                        "value": "deep_value"
                    }
                }
            }
        }
    }

    # Breakpoint here - we have rich data to explore
    x = 42  # line 62 - breakpoint target
    return company

if __name__ == "__main__":
    result = create_deep_structure()
    print(f"Created: {result.name}")
