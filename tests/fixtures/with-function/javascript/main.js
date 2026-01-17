function inner() {
  const x = 1;
  return x;
}

function outer() {
  return inner();
}

outer();
