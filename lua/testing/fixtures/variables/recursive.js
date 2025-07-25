// Test fixture for Variables plugin - recursive reference testing

function testRecursiveReferences() {
    // Create an object that references itself
    let recursiveObj = {
        name: "I reference myself",
        value: 42,
        nested: {
            data: "nested data",
            parent: null  // Will be set to recursiveObj
        }
    };
    
    // Create the recursive reference
    recursiveObj.nested.parent = recursiveObj;
    recursiveObj.self = recursiveObj;
    
    // Create a circular array reference
    let circularArray = [1, 2, 3];
    circularArray.push(circularArray); // circularArray[3] points to circularArray itself
    circularArray.self = circularArray;
    
    // Create a more complex recursive structure
    let complexRecursive = {
        id: "root",
        children: [],
        parent: null
    };
    
    let child1 = {
        id: "child1", 
        children: [],
        parent: complexRecursive
    };
    
    let child2 = {
        id: "child2",
        children: [],
        parent: complexRecursive
    };
    
    // Set up the recursive relationships
    complexRecursive.children.push(child1, child2);
    child1.root = complexRecursive;
    child2.root = complexRecursive;
    
    // Create a global reference that should appear in global scope
    globalThis.globalRecursive = {
        name: "Global Recursive",
        self: null,
        global: globalThis
    };
    globalThis.globalRecursive.self = globalThis.globalRecursive;
    
    // Add a reference to the global object within our local scope
    let localGlobalRef = globalThis;
    
    // Debug breakpoint - this is where Variables4 will inspect the variables
    debugger;
    
    return {
        recursiveObj,
        circularArray,
        complexRecursive,
        localGlobalRef
    };
}

// Run the test
testRecursiveReferences();