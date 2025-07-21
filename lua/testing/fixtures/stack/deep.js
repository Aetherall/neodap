// Test fixture for stack navigation - creates a deep call stack

function main() {
    console.log("Starting main");
    let result = functionOne(10);
    console.log("Main result:", result);
}

function functionOne(x) {
    console.log("In functionOne with x =", x);
    let value = x * 2;
    return functionTwo(value);
}

function functionTwo(y) {
    console.log("In functionTwo with y =", y);
    let value = y + 5;
    return functionThree(value);
}

function functionThree(z) {
    console.log("In functionThree with z =", z);
    let value = z / 2;
    return functionFour(value);
}

function functionFour(w) {
    console.log("In functionFour with w =", w);
    debugger; // Breakpoint here to create a stack
    return w * w;
}

// Start the program
main();