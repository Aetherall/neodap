const code = `
  function evalFunction() {
    const secret = 42;
    debugger;
    return secret;
  }
  evalFunction();
`;
eval(code);
