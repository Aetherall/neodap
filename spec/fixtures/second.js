setTimeout(() => {
	console.log("Test completed, exiting...");
	process.exit(0);
}, 1000);

console.log("Hello from neodap test!");
console.log("Process ID:", process.pid);
console.log("Node.js version:", process.version);
