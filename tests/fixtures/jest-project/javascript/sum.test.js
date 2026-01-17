const sum = require('./sum');

describe('sum', () => {
  test('adds 1 + 2 to equal 3', () => {
    debugger;
    const result = sum(1, 2);
    debugger;
    expect(result).toBe(3);
  });

  test('adds 0 + 0 to equal 0', () => {
    expect(sum(0, 0)).toBe(0);
  });
});
