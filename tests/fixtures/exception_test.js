// Test script for JavaScript exception handling

function mightFail(value) {
  if (value === 0) {
    throw new Error("Value cannot be zero");
  }
  return 100 / value;
}

function main() {
  console.log("Starting exception test");

  // First breakpoint location
  const x = 1;  // Line 14: set breakpoint here

  // Caught exception
  try {
    const result = mightFail(0);
  } catch (e) {
    console.log(`Caught exception: ${e.message}`);
  }

  console.log("After caught exception");

  // Uncaught exception (will crash)
  const result = mightFail(0);  // Line 25: uncaught exception here

  console.log("This should not print");
}

main();
