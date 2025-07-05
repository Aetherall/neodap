// Test file for virtual text breakpoints
console.log("Starting test");

function testFunction() {
  let x = 1;  // Breakpoint here should show ●
  let y = 2;  // Another breakpoint here should show ●
  console.log(x + y);
  return x * y;
}

testFunction();
console.log("Test complete");