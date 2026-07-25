async function run() {
  const numRequests = 20;
  let totalTime = 0;
  for (let i = 0; i < numRequests; i++) {
    const start = performance.now();
    let res = await fetch("http://localhost:8787/api/admin/analytics?limit=100", {
      headers: {
        "X-Admin-API-Key": "test"
      }
    });
    if (res.status !== 200) {
      console.log("Error:", res.status, await res.text());
    }
    const end = performance.now();
    totalTime += (end - start);
  }
  console.log(`Average time per request: ${totalTime / numRequests}ms`);
}
run();
