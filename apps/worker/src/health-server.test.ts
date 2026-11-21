import { afterEach, describe, expect, it, vi } from "vitest";
import { startWorkerHealthServer, type WorkerHealthServer } from "./health-server.js";
describe("worker readiness endpoint", () => {
  let health: WorkerHealthServer | undefined;
  afterEach(async () => { await health?.close(); health = undefined; });
  async function start(isReady: () => Promise<boolean>) {
    health = await startWorkerHealthServer({ port: 0, isReady });
    const address = health.server.address();
    if (!address || typeof address === "string") throw new Error("Expected TCP address.");
    return "http://127.0.0.1:" + address.port;
  }
  it("binds loopback and returns 200 when dependencies are ready", async () => {
    const url = await start(async () => true); const response = await fetch(url + "/health/ready");
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ status: "ready" });
    expect(health?.server.address()).toMatchObject({ address: "127.0.0.1" });
  });
  it("returns 503 while dependencies are unavailable", async () => {
    const url = await start(async () => false); const response = await fetch(url + "/health/ready");
    expect(response.status).toBe(503); expect(await response.json()).toEqual({ status: "not_ready" });
  });
  it("fails closed and sanitizes dependency exceptions", async () => {
    const url = await start(async () => { throw new Error("secret database detail"); });
    const response = await fetch(url + "/health/ready"); expect(response.status).toBe(503);
    expect(await response.text()).not.toContain("secret database detail");
  });
  it("rejects unrelated paths and methods", async () => {
    const url = await start(vi.fn(async () => true));
    expect((await fetch(url + "/")).status).toBe(404);
    expect((await fetch(url + "/health/ready", { method: "POST" })).status).toBe(404);
  });
  it("rejects invalid ports", async () => {
    await expect(startWorkerHealthServer({ port: 65_536, isReady: async () => true })).rejects.toThrow("Worker health port");
  });
});