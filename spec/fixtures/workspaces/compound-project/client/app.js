// Client component for compound project testing
const http = require('http');

function makeApiRequest(method, path, data) {
  const options = {
    hostname: 'localhost',
    port: 3000,
    path: path,
    method: method,
    headers: {
      'Content-Type': 'application/json'
    }
  };

  const req = http.request(options, (res) => {
    let responseData = '';
    res.on('data', (chunk) => {
      responseData += chunk;
    });
    res.on('end', () => {
      console.log('Client: Response received:', responseData);
    });
  });

  req.on('error', (error) => {
    console.error('Client: Error:', error);
  });

  if (data) {
    req.write(JSON.stringify(data));
  }
  req.end();
}

console.log('Client: Starting requests');

// Get initial data
makeApiRequest('GET', '/api/data');

// Update data after a delay
setTimeout(() => {
  makeApiRequest('POST', '/api/data', { message: 'Updated from client!' });
}, 1000);