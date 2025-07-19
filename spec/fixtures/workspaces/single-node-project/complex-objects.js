let counter = 0;

// Create complex objects for hierarchical testing
const user = {
    name: "John Doe",
    age: 30,
    address: {
        street: "123 Main St",
        city: "San Francisco",
        country: "USA",
        coordinates: {
            lat: 37.7749,
            lng: -122.4194
        }
    },
    hobbies: ["reading", "coding", "hiking"],
    settings: {
        theme: "dark",
        notifications: {
            email: true,
            push: false,
            sms: true
        }
    }
};

const numbers = [1, 2, 3, [4, 5, [6, 7, 8]], 9, 10];

const complexArray = [
    { id: 1, name: "Item 1" },
    { id: 2, name: "Item 2", meta: { tags: ["important", "urgent"] } },
    [1, 2, { nested: "value" }]
];

setInterval(() => {
    console.log("Counter:", counter++);
    console.log("User name:", user.name);
    console.log("First hobby:", user.hobbies[0]);
    console.log("Email notifications:", user.settings.notifications.email);
    console.log("Numbers:", numbers);
    console.log("Complex array:", complexArray);
}, 2000);