// Demo app - zero dependencies (Node 18+).
//   GET /                 -> small HTML page ("Hello from Demo App")
//   GET /health           -> {"status":"ok"}          (used by the pipeline health check)
//   GET /api/info         -> {"app","version","hostname","time"}
//   GET /api/greet?name=X -> {"message":"Hello, X!"}

const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PORT = parseInt(process.env.PORT || '3000', 10);
const VERSION = (process.env.APP_VERSION ||
  fs.readFileSync(path.join(__dirname, 'VERSION'), 'utf8')).trim();

function json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}

function page() {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Demo App</title>
<style>
  body{font-family:Georgia,serif;background:#f3ead8;color:#2b1d14;text-align:center;padding:60px 16px}
  h1{font-size:44px;margin:0 0 8px}
  .box{display:inline-block;border:3px double #2b1d14;padding:24px 40px;background:#fbf6ea}
  code{background:#ece0c6;padding:2px 8px}
</style></head>
<body><div class="box">
  <h1>Hello from Demo App</h1>
  <p>Version <b>${VERSION}</b> &middot; served by <code>${os.hostname()}</code></p>
  <p>Try <code>/health</code> &middot; <code>/api/info</code> &middot; <code>/api/greet?name=Macha</code></p>
</div></body></html>`;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(page());
  }
  if (url.pathname === '/health') return json(res, 200, { status: 'ok' });
  if (url.pathname === '/api/info') {
    return json(res, 200, { app: 'demo-app', version: VERSION, hostname: os.hostname(), time: new Date().toISOString() });
  }
  if (url.pathname === '/api/greet') {
    const name = (url.searchParams.get('name') || 'World').slice(0, 50);
    return json(res, 200, { message: `Hello, ${name}!` });
  }
  json(res, 404, { error: 'not found' });
});

server.listen(PORT, '0.0.0.0', () => console.log(`Demo app v${VERSION} listening on :${PORT}`));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
