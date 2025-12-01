// Test fixture for js-debug integration tests
function main() {
    const user = {
        name: "John Doe",
        age: 30,
        address: {
            street: "123 Main St",
            city: "San Francisco",
            coordinates: {
                lat: 37.7749,
                lng: -122.4194
            }
        },
        hobbies: ["coding", "reading", "hiking"]
    };

    const numbers = [1, 2, 3, 4, 5];

    debugger; // Breakpoint here

    console.log("User:", user);
    console.log("Numbers:", numbers);

    nested();
}

function nested() {
    const localVar = "I'm local";
    const anotherObject = {
        key1: "value1",
        key2: 42,
        nested: {
            deep: "very deep"
        }
    };

    console.log("Nested function");
}

main();
