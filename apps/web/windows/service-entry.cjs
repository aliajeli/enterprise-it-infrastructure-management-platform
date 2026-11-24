"use strict";
let server; let app; let shutdownTask;
async function shutdown(reason) { shutdownTask ??= (async () => {
  process.stdout.write("[web] shutdown requested: " + reason + "\n");
  if (server?.listening) await new Promise((resolve, reject) => {
    const timer = setTimeout(() => server.closeAllConnections(), 15000); timer.unref();
    server.close((error) => { clearTimeout(timer); if (error) reject(error); else resolve(); });
  });
  if (typeof app?.close === "function") await app.close();
})(); return shutdownTask; }
async function main() {
  const { createServer } = await import("node:http");
  const { existsSync } = await import("node:fs");
  const { join } = await import("node:path");
  const flat = existsSync(join(__dirname, "server.js"));
  const monorepo = existsSync(join(__dirname, "apps", "web", "server.js"));
  if (flat === monorepo) throw new Error("Invalid or ambiguous standalone Web layout");
  const appDir = monorepo ? join(__dirname, "apps", "web") : __dirname;
  // Next's generated standalone server injects the build-time config before
  // loading Next. A custom graceful-shutdown host must do the same: reading
  // defaults instead would discard rewrites and poweredByHeader settings.
  const { readFile } = await import("node:fs/promises");
  const required = JSON.parse(await readFile(join(appDir, ".next", "required-server-files.json"), "utf8"));
  if (!required.config || typeof required.config !== "object" || Array.isArray(required.config)) throw new Error("Invalid standalone build configuration");
  process.env.__NEXT_PRIVATE_STANDALONE_CONFIG = JSON.stringify(required.config);
  const nextModule = await import("next");
  const next = nextModule.default ?? nextModule;
  const host = "127.0.0.1"; const port = 13000;
  app = next({ dev: false, dir: appDir, hostname: host, port });
  const handle = app.getRequestHandler();
  await app.prepare();
  server = createServer((req,res) => {
    Promise.resolve(handle(req,res)).catch((error) => {
      process.stderr.write("[web] request failed: " + (error instanceof Error ? error.message : "unknown") + "\n");
      if(!res.headersSent)res.writeHead(500,{"content-type":"application/json"});
      res.end(JSON.stringify({status:"internal_error"}));
    });
  });
  await new Promise((resolve,reject)=>{server.once("error",reject);server.listen(port,host,()=>{server.off("error",reject);resolve();});});
  process.stdout.write("[web] ready at http://127.0.0.1:13000\n");
}
process.once("SIGINT",()=>void shutdown("SIGINT").catch(e=>{process.stderr.write(String(e)+"\n");process.exitCode=1;}));
process.once("SIGTERM",()=>void shutdown("SIGTERM").catch(e=>{process.stderr.write(String(e)+"\n");process.exitCode=1;}));
let buffer="";process.stdin.setEncoding("utf8");process.stdin.on("data",chunk=>{buffer+=chunk;if(buffer.length>64){buffer="";return;}const n=buffer.indexOf("\n");if(n<0)return;const command=buffer.slice(0,n).trim();buffer=buffer.slice(n+1);if(command==="SHUTDOWN")void shutdown("HOST").catch(e=>{process.stderr.write("[web] shutdown failed: "+String(e)+"\n");process.exitCode=1;});});
main().catch(async e=>{process.stderr.write("[web] startup failed: "+(e instanceof Error?e.message:"unknown")+"\n");try{await app?.close?.();}catch{}process.exitCode=1;});
