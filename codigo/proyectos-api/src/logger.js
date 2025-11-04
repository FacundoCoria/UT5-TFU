export function reqLogger(req, res, next) {
  const raw = req.body || {};
  const body = {};
  for (const k of Object.keys(raw)) {
    const v = raw[k];
    body[k] = (k.toLowerCase() === "password")
      ? "***"
      : (typeof v === "string" ? (v.length>120 ? v.slice(0,120)+"…" : v) : v);
  }
  const rid  = req.headers["x-request-id"] || "-";
  const auth = req.headers["authorization"] ? "yes" : "no";

  console.log(JSON.stringify({
    at: new Date().toISOString(),
    evt: "REQ",
    rid, method: req.method,
    path: req.originalUrl || req.url,
    auth, body
  }));

  const t0 = process.hrtime.bigint();
  res.on("finish", () => {
    const durMs = Number((process.hrtime.bigint() - t0) / 1000000n);
    console.log(JSON.stringify({
      at: new Date().toISOString(),
      evt: "RES",
      rid, method: req.method,
      path: req.originalUrl || req.url,
      status: res.statusCode,
      dur_ms: durMs
    }));
  });

  next();
}
