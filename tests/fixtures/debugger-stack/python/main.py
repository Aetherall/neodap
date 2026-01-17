def inner():
    x = 99
    pass  # inner breakpoint

x = 42
inner()
pass  # outer breakpoint
