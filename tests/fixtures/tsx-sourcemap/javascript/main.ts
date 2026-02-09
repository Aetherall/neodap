interface User {
  name: string;
  age: number;
}

function greet(user: User): string {
  const message = `Hello, ${user.name}! You are ${user.age} years old.`;
  console.log(message);
  return message;
}

const user: User = {
  name: "Alice",
  age: 30,
};

const result = greet(user);
console.log("Done:", result);
