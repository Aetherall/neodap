#!/usr/bin/env node
/**
 * Test fixture for stepping operations (step_over, step_into, step_out)
 */

function innerFunction(x) {
  const result = x * 2;  // Line 7 - step into lands here
  return result;         // Line 8
}

function outerFunction(value) {
  const a = value + 1;           // Line 12
  const b = innerFunction(a);    // Line 13 - step over skips inner, step into enters
  const c = b + 10;              // Line 14 - step out from inner lands here
  return c;                      // Line 15
}

function main() {
  const result = outerFunction(5);  // Line 19
  console.log(`Result: ${result}`); // Line 20
  return result;
}

main();
