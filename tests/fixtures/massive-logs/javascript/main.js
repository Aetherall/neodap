// Generate structured log entries
const LOG_COUNT = 10000;

const levels = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
const components = ['auth', 'api', 'db', 'cache', 'queue', 'worker'];
const actions = ['request', 'response', 'query', 'insert', 'update', 'delete', 'connect', 'disconnect'];

function generateLog(index) {
  const level = levels[index % levels.length];
  const component = components[index % components.length];
  const action = actions[index % actions.length];
  const timestamp = new Date(Date.now() + index).toISOString();

  const log = {
    index,
    timestamp,
    level,
    component,
    action,
    message: `${action} operation on ${component}`,
    metadata: {
      requestId: `req-${index.toString(16).padStart(8, '0')}`,
      duration: Math.floor(Math.random() * 1000),
      success: index % 10 !== 0
    }
  };

  console.log(JSON.stringify(log));
}

// Generate all logs (no debugger statement - runs directly)
for (let i = 0; i < LOG_COUNT; i++) {
  generateLog(i);
}

console.log('Done generating logs');
