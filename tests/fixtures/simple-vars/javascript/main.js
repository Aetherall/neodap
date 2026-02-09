const x = 1;
const y = 2;

try {
  throw new Error("Caught exception!");
} catch (e) {
  console.log("Handled:", e.message);
}

console.log(x + y);
