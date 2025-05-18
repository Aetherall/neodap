// Simple test file for debugging
function testFunction() {
	let localVar = "test value";
	let numberVar = 42;
	console.log("Breakpoint here"); // Line 4 - good place for breakpoint
	return localVar + numberVar;
}

testFunction();
console.log("Program complete");
