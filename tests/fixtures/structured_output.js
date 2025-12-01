#!/usr/bin/env node
/**
 * Test fixture for structured console output exploration
 * js-debug provides variablesReference for logged objects
 */

function main() {
  const company = {
    name: "TechCorp",
    address: {
      street: "123 Main St",
      city: "San Francisco",
      country: "USA"
    },
    departments: [
      {
        name: "Engineering",
        employees: [
          { name: "Alice", role: "Lead", skills: ["python", "rust"] }
        ]
      }
    ]
  };

  const nested = {
    level1: {
      level2: {
        level3: {
          value: "deep_value"
        }
      }
    }
  };

  // These structured console.log calls should produce output with variablesReference
  console.log("Company data:", company);
  console.log("Nested data:", nested);

  // Breakpoint here to capture the outputs
  debugger;  // Line 38
}

main();
