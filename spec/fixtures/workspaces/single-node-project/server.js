// Simple server for testing launch.json configurations
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  let message = 'Hello from server!';
  console.log('Server handling request');
  res.send(message);
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});