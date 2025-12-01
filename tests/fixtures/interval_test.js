// Test fixture for exploring timer internals
let counter = 0;

const intervalId = setInterval(() => {
  counter++;
  console.log(`Tick ${counter}`);  // Line 6 - breakpoint here

  if (counter >= 3) {
    clearInterval(intervalId);
    console.log('Done');
  }
}, 100);

console.log('Interval started');
