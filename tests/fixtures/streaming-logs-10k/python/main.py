# Performance test fixture: 10000 logs immediately, then 1 log every 100ms
# Used for testing tree toggle performance with large output

import time

INITIAL_COUNT = 10000
INTERVAL_S = 0.1

log_index = 0


def emit_log():
    global log_index
    print(f"[{log_index}] Log message at {time.time()}")
    log_index += 1


# Emit 10000 logs immediately
for _ in range(INITIAL_COUNT):
    emit_log()

print("--- Initial logs done, starting streaming ---")

# Then emit one log every 100ms (indefinitely until killed)
while True:
    time.sleep(INTERVAL_S)
    emit_log()
