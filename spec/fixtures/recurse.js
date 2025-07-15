function fibo(n) {
	if (n <= 1) return n;
	return fibo(n - 1) + fibo(n - 2);
}

// Test with smaller number for debugging
setTimeout(() => fibo(500), 1000);
