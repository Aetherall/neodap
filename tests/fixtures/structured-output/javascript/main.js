// Structured console output for testing output expansion
// Tests that console.log with objects produces expandable output

// Simple object
const user = {
  name: "Alice",
  age: 30,
  email: "alice@example.com"
};

// Nested object
const config = {
  server: {
    host: "localhost",
    port: 8080,
    ssl: {
      enabled: true,
      cert: "/path/to/cert"
    }
  },
  database: {
    url: "postgres://localhost/db",
    pool: { min: 5, max: 20 }
  }
};

// Array with objects
const items = [
  { id: 1, name: "item1", tags: ["a", "b"] },
  { id: 2, name: "item2", tags: ["c", "d", "e"] },
  { id: 3, name: "item3", tags: [] }
];

// Complex nested structure
const report = {
  metadata: {
    generated: new Date().toISOString(),
    version: "1.0"
  },
  data: {
    users: [user],
    config: config
  },
  stats: {
    total: 100,
    active: 85
  }
};

debugger;

// Log structured objects - these should produce expandable output
console.log("User:", user);
console.log("Config:", config);
console.log("Items:", items);
console.log("Report:", report);

console.log("Structured output test complete");
