// Test program that waits for a debugger to attach
// Run with: node --inspect-brk=port wait_for_debugger.js

console.log("Node.js process started, waiting for debugger...");

// Give debugger time to attach
setTimeout(() => {
  console.log("Debugger should be attached now");
  
  // Simple code to debug
  const x = 42;
  const y = x + 1;  // Breakpoint here (line 11)
  console.log(`Result: ${y}`);
}, 100);
