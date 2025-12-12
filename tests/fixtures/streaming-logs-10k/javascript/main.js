// Performance test fixture: 10000 logs immediately, then 1 log every 100ms
// Used for testing tree toggle performance with large output

const INITIAL_COUNT = 10000;
const INTERVAL_MS = 100;

let logIndex = 0;

function emitLog() {
  console.log(`[${logIndex}] Log message at ${Date.now()}`);
  logIndex++;
}

// Emit 10000 logs immediately
for (let i = 0; i < INITIAL_COUNT; i++) {
  emitLog();
}

console.log('--- Initial logs done, starting streaming ---');

// Then emit one log every 100ms (indefinitely until killed)
setInterval(emitLog, INTERVAL_MS);
