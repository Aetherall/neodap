const sum = require("./sum");

describe("sum", () => {
  test("adds 1 + 2 to equal 3", () => {
    console.log("Starting test: adds 1 + 2 to equal 3");
    console.log("Calling sum(1, 2)...");
    debugger;
    const result = sum(1, 2);
    console.log("Result:", result);
    console.log("Expected:", 3);
    console.log({ result, expected: 3, passed: result === 3 });
    debugger;
    expect(result).toBe(3);
    console.log("Test passed!");
  });

  test("adds 0 + 0 to equal 0", () => {
    console.log("Starting test: adds 0 + 0 to equal 0");
    const result = sum(0, 0);
    console.log("Result:", result);
    expect(result).toBe(0);
    console.log("Test passed!");
  });
});
