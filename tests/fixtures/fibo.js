// Simple JavaScript program for DAP testing

function fibonacci(n) {
  if (n <= 1) {
    return n;
  }
  return fibonacci(n - 1) + fibonacci(n - 2);
}

function greet(name) {
  const message = `Hello, ${name}!`;
  console.log(message);
  return message;
}

function main() {
  console.log("Starting test program...");

  // Line 18 - Good breakpoint location
  const result1 = greet("World");

  // Line 21 - Another breakpoint location
  const result2 = fibonacci(5);
  console.log("Fibonacci(5) =", result2);

  // Line 25 - Final breakpoint
  const sum = result2 + 10;
  console.log("Sum =", sum);

  console.log("Test program finished!");
  return sum;
}

// Run the program
main();
