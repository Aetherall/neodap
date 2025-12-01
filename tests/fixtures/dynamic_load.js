#!/usr/bin/env node
// Test fixture for loadedSource events
// Dynamically loads modules to trigger "new" loadedSource events

const fs = require('fs');
const path = require('path');

// Breakpoint here - before dynamic load
let counter = 0;  // Line 9

// This will be called to dynamically load a module
function loadModule() {
  // Dynamic require triggers loadedSource "new" event
  const helper = require('./dynamic_helper.js');  // Line 14
  return helper.getValue();
}

// Main execution
counter = 1;  // Line 19 - Breakpoint here
const result = loadModule();  // Line 20 - This triggers dynamic load
counter = result;  // Line 21

console.log(`Result: ${counter}`);
