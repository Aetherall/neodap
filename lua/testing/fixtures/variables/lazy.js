// Test fixture for lazy variable evaluation

class LazyExample {
    constructor() {
        this._cachedValue = null;
        this._computeCount = 0;
    }
    
    // Getter that might be marked as lazy by the debugger
    get expensiveComputation() {
        this._computeCount++;
        if (!this._cachedValue) {
            // Simulate expensive computation
            this._cachedValue = Array(1000).fill(0).reduce((a, b, i) => a + i, 0);
        }
        return this._cachedValue;
    }
    
    // Another getter that could have side effects
    get currentTime() {
        return new Date().toISOString();
    }
    
    // Regular property for comparison
    normalProperty = "This is not lazy";
}

function testLazyVariables() {
    const instance = new LazyExample();
    
    // Access the getter to ensure it's initialized
    const value = instance.expensiveComputation;
    
    // Debugger breakpoint here
    console.log("Lazy variable test");
    
    return instance;
}