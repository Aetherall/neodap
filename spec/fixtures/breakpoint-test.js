function simpleFunction(x, y) {
	let result = x + y; // Line 2 - Good breakpoint target
	console.log("Computing:", result); // Line 3 - Another target
	return result; // Line 4 - Return point
}

function anotherFunction() {
	let value = 42; // Line 7 - Function breakpoint test
	return value * 2; // Line 8
}

// Main execution
let a = 5; // Line 12 - Entry point
let b = 10; // Line 13
let sum = simpleFunction(a, b); // Line 14 - Function call
console.log("Result:", sum); // Line 15 - Output
let doubled = anotherFunction(); // Line 16 - Another function call
console.log("Doubled:", doubled); // Line 17 - Final output
