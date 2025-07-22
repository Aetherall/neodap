// Test fixture for Variables plugin - various variable types

function testVariables() {
    // Primitive types
    let numberVar = 42;
    let stringVar = "Hello, Debug!";
    let booleanVar = true;
    let nullVar = null;
    let undefinedVar = undefined;
    let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
    let longStringValue = "This is a very long string value that should be truncated when displayed in the tree view to prevent line wrapping";
    
    // Complex types
    let arrayVar = [1, 2, 3, "four", { five: 5 }];
    let objectVar = {
        name: "Test Object",
        count: 100,
        nested: {
            level: 2,
            data: ["a", "b", "c"]
        },
        method: function() { return "method"; }
    };
    
    // Function
    let functionVar = function(x) { return x * 2; };
    
    // Map and Set
    let mapVar = new Map([["key1", "value1"], ["key2", "value2"]]);
    let setVar = new Set([1, 2, 3, 3, 4]);
    
    // Date
    let dateVar = new Date("2024-01-01");
    
    // Debug break point
    debugger;
    
    return "done";
}

// Run the test
testVariables();