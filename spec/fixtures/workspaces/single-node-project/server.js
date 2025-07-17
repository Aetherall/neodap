// Simple server for testing launch.json configurations
const express = require('express');
const app = express();
const port = 3000;

// This will definitely execute - good for breakpoint testing
console.log('Starting server setup...');

app.get('/', (req, res) => {
  let message = 'Hello from server!';
  console.log('Server handling request');
  res.send(message);
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});