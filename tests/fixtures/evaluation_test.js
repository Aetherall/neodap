#!/usr/bin/env node
/**
 * Test fixture for expression evaluation and structured output
 */

function testEvaluation() {
  const simpleNumber = 42;
  const simpleString = "hello world";

  const user = {
    name: "Alice",
    age: 30,
    address: {
      city: "Wonderland",
      zip: "12345"
    }
  };

  const numbers = [1, 2, 3, 4, 5];

  // Output some structured data
  console.log("User:", user);
  console.log("Numbers:", numbers);

  debugger;  // Line 24 - breakpoint here for evaluation tests

  return { simpleNumber, simpleString, user, numbers };
}

testEvaluation();
