def log_step(n):
    print(f'Step {n}', flush=True)
    return n

a = log_step(1)
b = log_step(2)
c = log_step(3)
print('Done', flush=True)
