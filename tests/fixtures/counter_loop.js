#!/usr/bin/env node
// Simple counter loop for testing breakpoint + continue

function countUp(limit) {
  let counter = 0;
  for (let i = 0; i < limit; i++) {
    counter += 1;  // Line 7 - Breakpoint here
    console.log(`Counter: ${counter}`);  // Line 8
  }
  return counter;
}

const result = countUp(5);
console.log(`Final: ${result}`);
