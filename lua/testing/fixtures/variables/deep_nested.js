// Test fixture for Variables plugin - deeply nested structures for visibility testing

function testDeepNesting() {
    // Create a deeply nested object structure
    let complexObject = {
        level1: {
            nested1: {
                nested2: {
                    nested3: {
                        nested4: {
                            nested5: {
                                level6: {
                                    finalValue: "You found me!",
                                    metadata: {
                                        depth: 7,
                                        path: "complexObject.level1.nested1.nested2.nested3.nested4.nested5.level6"
                                    }
                                },
                                siblings: ["a", "b", "c"]
                            },
                            moreData: [1, 2, 3, 4, 5]
                        },
                        properties: {
                            type: "deep",
                            count: 42
                        }
                    },
                    array: [10, 20, 30, 40, 50]
                },
                info: "Level 2 info"
            },
            data: "Level 1 data"
        },
        description: "Root level"
    };
    
    // Create a large array for testing vertical scrolling
    let deepArray = [];
    for (let i = 0; i < 50; i++) {
        deepArray.push({
            index: i,
            value: `Item ${i}`,
            nested: {
                data: i * 10,
                more: {
                    info: `Nested info for item ${i}`
                }
            }
        });
    }
    
    // Wide object with many properties
    let wideObject = {};
    for (let i = 0; i < 30; i++) {
        wideObject[`property_${i}`] = {
            value: i,
            description: `This is property number ${i} with some data`
        };
    }
    
    // Mixed deep and wide structure
    let mixedStructure = {
        users: {
            admins: {
                superAdmins: {
                    root: {
                        permissions: ["all"],
                        lastLogin: new Date(),
                        settings: {
                            theme: "dark",
                            notifications: {
                                email: true,
                                push: false,
                                preferences: {
                                    frequency: "daily",
                                    categories: ["security", "updates", "news"]
                                }
                            }
                        }
                    }
                },
                regularAdmins: ["alice", "bob", "charlie"]
            },
            members: Array(25).fill(null).map((_, i) => ({
                id: i,
                name: `User ${i}`,
                active: i % 2 === 0
            }))
        }
    };
    
    // Debug break point
    debugger;
    
    return "done";
}

// Run the test
testDeepNesting();