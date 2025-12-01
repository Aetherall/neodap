// Test script with multiple exception points for testing enable/disable

function mightFail(value) {
  if (value === 0) {
    throw new Error("Value cannot be zero");
  }
  return 100 / value;
}

function main() {
  console.log("Starting multi-exception test");

  // First breakpoint location
  const x = 1;  // Line 14: set breakpoint here

  // First exception - will be caught
  try {
    const result = mightFail(0);
  } catch (e) {
    console.log(`Caught first exception: ${e.message}`);
  }

  console.log("Continuing after first exception...");

  // Second exception - will be caught
  try {
    const result = mightFail(0);
  } catch (e) {
    console.log(`Caught second exception: ${e.message}`);
  }

  console.log("Continuing after second exception...");

  // Success path
  const result = mightFail(5);
  console.log(`Result: ${result}`);

  console.log("Program completed successfully");
}

main();
