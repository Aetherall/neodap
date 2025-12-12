// App B - Simple HTTP server
const http = require('http');

const PORT = 3002;

const server = http.createServer((req, res) => {
  console.log(`[App B] Request: ${req.method} ${req.url}`);
  
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    app: 'B',
    message: 'Hello from App B',
    timestamp: new Date().toISOString()
  }));
});

server.listen(PORT, () => {
  console.log(`[App B] Server running on port ${PORT}`);
});
