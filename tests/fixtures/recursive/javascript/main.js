function countdown(n) {
  if (n <= 0) {
    return 'done';
  }
  return countdown(n - 1);
}

const result = countdown(3);
console.log(result);
