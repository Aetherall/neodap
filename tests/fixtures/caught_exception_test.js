// Test script for caught exceptions only (no uncaught)

function mightFail(value) {
  if (value === 0) {
    throw new Error("Value cannot be zero");
  }
  return 100 / value;
}

function main() {
  console.log("Starting caught exception test");

  // First breakpoint location
  const x = 1;  // Line 14: set breakpoint here

  // First caught exception
  try {
    const result = mightFail(0);  // Line 18: caught exception
  } catch (e) {
    console.log(`Caught first exception: ${e.message}`);
  }

  console.log("After first exception");

  // Second caught exception
  try {
    const result = mightFail(0);  // Line 27: caught exception
  } catch (e) {
    console.log(`Caught second exception: ${e.message}`);
  }

  console.log("Program completed successfully");
}

main();
