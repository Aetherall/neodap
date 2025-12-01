// Helper module loaded dynamically
// This file being required should trigger a loadedSource "new" event

function getValue() {
  return 42;
}

module.exports = { getValue };
