def countdown(n):
    if n <= 0:
        return 'done'
    return countdown(n - 1)

result = countdown(3)
print(result)
