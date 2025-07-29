// Test fixture for recursive function calls - creates duplicate frames in stack

function fibonacci(n, depth = 0) {
    // Add a breakpoint here to see recursive frames
    console.log(`fibonacci(${n}) at depth ${depth}`);
    
    if (n <= 1) {
        return n;
    }
    
    // Recursive calls create multiple "fibonacci" frames in the stack
    return fibonacci(n - 1, depth + 1) + fibonacci(n - 2, depth + 1);
}

function factorial(n) {
    // Another recursive function
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1);
}

function main() {
    console.log("Starting recursive function test");
    
    // This will create multiple fibonacci frames in the call stack
    const result = fibonacci(5);
    console.log(`fibonacci(5) = ${result}`);
    
    // Also test factorial
    const fact = factorial(4);
    console.log(`factorial(4) = ${fact}`);
}

// Run the test
main();