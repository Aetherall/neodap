// App A - Simple HTTP server
const http = require('http');

const PORT = 3001;

const server = http.createServer((req, res) => {
  console.log(`[App A] Request: ${req.method} ${req.url}`);
  
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    app: 'A',
    message: 'Hello from App A',
    timestamp: new Date().toISOString()
  }));
});

server.listen(PORT, () => {
  console.log(`[App A] Server running on port ${PORT}`);
});
