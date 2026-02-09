// Deep nested structures for testing tree navigation
// Tests expanding multiple levels of objects, arrays, and mixed structures

// 5 levels deep object
const deepObject = {
  level1: {
    level2: {
      level3: {
        level4: {
          level5: {
            value: "deep value",
            count: 42
          }
        }
      }
    }
  }
};

// Array of objects with nested arrays
const complexArray = [
  {
    name: "item1",
    children: [
      { id: 1, tags: ["a", "b", "c"] },
      { id: 2, tags: ["d", "e"] }
    ]
  },
  {
    name: "item2",
    children: [
      { id: 3, tags: ["f"] }
    ]
  }
];

// Mixed deep structure
const mixedDeep = {
  users: [
    {
      name: "Alice",
      profile: {
        settings: {
          theme: "dark",
          notifications: {
            email: true,
            push: false
          }
        }
      }
    },
    {
      name: "Bob",
      profile: {
        settings: {
          theme: "light",
          notifications: {
            email: false,
            push: true
          }
        }
      }
    }
  ]
};

// Wide structure (many siblings)
const wideObject = {
  a: 1, b: 2, c: 3, d: 4, e: 5,
  f: 6, g: 7, h: 8, i: 9, j: 10,
  k: 11, l: 12, m: 13, n: 14, o: 15
};

// Recursive-like structure (tree)
const tree = {
  value: "root",
  left: {
    value: "left",
    left: { value: "left-left", left: null, right: null },
    right: { value: "left-right", left: null, right: null }
  },
  right: {
    value: "right",
    left: { value: "right-left", left: null, right: null },
    right: { value: "right-right", left: null, right: null }
  }
};

debugger;
console.log("Deep structures ready for inspection");
