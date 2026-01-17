function inner() {
  debugger;
}

function outer() {
  inner();
}

outer();
