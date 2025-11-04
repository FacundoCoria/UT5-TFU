
export async function retryAsync(fn, attempts = 4, baseDelay = 200) {
  let i = 0;
  let delay = baseDelay;
  while (true) {
    try { return await fn(); } catch (e) {
      i++;
      if (i >= attempts) throw e;
      await new Promise(r => setTimeout(r, delay));
      delay *= 2;
    }
  }
}

export default retryAsync;
