"use strict";
// Disposable CI backend for verifying the built Web rewrite. Loopback only.
const http = require("node:http");
const server = http.createServer((req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ fixture: "enterpriseit-web-rewrite", path: req.url }));
});
server.listen(13001, "127.0.0.1");
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { if (chunk.includes("SHUTDOWN")) server.close(); });
