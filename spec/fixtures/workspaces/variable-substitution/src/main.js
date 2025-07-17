// Main application file for variable substitution testing
const path = require('path');
const fs = require('fs');

function processFile(filename) {
  const filepath = path.join(__dirname, filename);
  
  if (fs.existsSync(filepath)) {
    const content = fs.readFileSync(filepath, 'utf8');
    console.log(`Processing file: ${filename}`);
    console.log(`Content length: ${content.length}`);
    return content;
  } else {
    console.log(`File not found: ${filename}`);
    return null;
  }
}

function main() {
  console.log('Variable substitution test application started');
  console.log('Current working directory:', process.cwd());
  console.log('Script directory:', __dirname);
  
  const testFile = 'test.txt';
  const result = processFile(testFile);
  
  if (result) {
    console.log('File processed successfully');
  } else {
    console.log('File processing failed');
  }
}

main();