def inner():
    x = 1
    return x

def outer():
    return inner()

outer()
