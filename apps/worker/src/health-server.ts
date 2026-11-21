import { createServer, type Server } from "node:http";
export interface WorkerHealthServerOptions { port?: number; isReady: () => Promise<boolean>; }
export interface WorkerHealthServer { server: Server; close: () => Promise<void>; }
/** Exposes a loopback readiness endpoint without returning dependency error details. */
export async function startWorkerHealthServer({ port = 13002, isReady }: WorkerHealthServerOptions): Promise<WorkerHealthServer> {
  if (!Number.isInteger(port) || port < 0 || port > 65_535) throw new Error("Worker health port must be an integer between 0 and 65535.");
  const server = createServer((request, response) => {
    if (request.method !== "GET" || request.url !== "/health/ready") { response.writeHead(404, { "content-type": "application/json; charset=utf-8" }); response.end(JSON.stringify({ status: "not_found" })); return; }
    void isReady().then((ready) => {
      response.writeHead(ready ? 200 : 503, { "cache-control": "no-store", "content-type": "application/json; charset=utf-8" });
      response.end(JSON.stringify({ status: ready ? "ready" : "not_ready" }));
    }, () => { response.writeHead(503, { "cache-control": "no-store", "content-type": "application/json; charset=utf-8" }); response.end(JSON.stringify({ status: "not_ready" })); });
  });
  await new Promise<void>((resolve, reject) => {
    const onError = (error: Error) => { server.off("listening", onListening); reject(error); };
    const onListening = () => { server.off("error", onError); resolve(); };
    server.once("error", onError); server.once("listening", onListening); server.listen(port, "127.0.0.1");
  });
  return { server, close: () => new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve())) };
}