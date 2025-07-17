// Server component for compound project testing
const express = require('express');
const cors = require('cors');
const app = express();
const port = 3000;

app.use(cors());
app.use(express.json());

let data = {
  message: 'Hello from compound server!',
  timestamp: new Date().toISOString()
};

app.get('/api/data', (req, res) => {
  console.log('Server: API request received');
  res.json(data);
});

app.post('/api/data', (req, res) => {
  data.message = req.body.message || data.message;
  data.timestamp = new Date().toISOString();
  console.log('Server: Data updated', data);
  res.json(data);
});

app.listen(port, () => {
  console.log(`Compound server running on port ${port}`);
});