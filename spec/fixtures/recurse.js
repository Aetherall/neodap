function fibo(n){
  console.log("Calculating fibo(" + n + ")");
  if(n <= 1) return n;
  return fibo(n - 1) + fibo(n - 2);
}



setTimeout(() => fibo(1000000), 1000);