// Test program for runInTerminal debugging
// This program has clear breakpoint locations and waits for debugging

function calculate(x) {
  const y = x * 2;  // Line 5 - good breakpoint location
  return y + 1;     // Line 6
}

function main() {
  console.log("Program started");

  const result = calculate(21);  // Line 11
  console.log(`Result: ${result}`);

  // Keep process alive for a bit to allow debugging
  setTimeout(() => {
    console.log("Program finished");
  }, 2000);
}

main();
