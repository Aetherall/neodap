#!/usr/bin/env python3
"""Generate 10,000 structured log entries."""

import json
import random
from datetime import datetime, timedelta

LOG_COUNT = 10000

LEVELS = ['DEBUG', 'INFO', 'WARN', 'ERROR']
COMPONENTS = ['auth', 'api', 'db', 'cache', 'queue', 'worker']
ACTIONS = ['request', 'response', 'query', 'insert', 'update', 'delete', 'connect', 'disconnect']


def generate_log(index: int) -> dict:
    level = LEVELS[index % len(LEVELS)]
    component = COMPONENTS[index % len(COMPONENTS)]
    action = ACTIONS[index % len(ACTIONS)]
    timestamp = (datetime.now() + timedelta(milliseconds=index)).isoformat()

    return {
        'index': index,
        'timestamp': timestamp,
        'level': level,
        'component': component,
        'action': action,
        'message': f'{action} operation on {component}',
        'metadata': {
            'requestId': f'req-{index:08x}',
            'duration': random.randint(0, 1000),
            'success': index % 10 != 0
        }
    }


# Generate all logs (no breakpoint - runs directly)
for i in range(LOG_COUNT):
    log = generate_log(i)
    print(json.dumps(log))

print('Done generating logs')
