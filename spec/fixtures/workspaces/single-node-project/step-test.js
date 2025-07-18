function innerFunction(value) {
	console.log("Inner function:", value);
	return value * 2;
}

function middleFunction(value) {
	console.log("Middle function start:", value);
	const result = innerFunction(value);
	console.log("Middle function end:", result);
	return result + 1;
}

function outerFunction(value) {
	console.log("Outer function start:", value);
	const result = middleFunction(value);
	console.log("Outer function end:", result);
	return result;
}

// Start execution
console.log("Starting step test");
const finalResult = outerFunction(5);
console.log("Final result:", finalResult);