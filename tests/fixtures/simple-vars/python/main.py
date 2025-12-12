x = 1
y = 2

try:
    raise Exception("Caught exception!")
except Exception as e:
    print("Handled:", e)


print(x + y)
