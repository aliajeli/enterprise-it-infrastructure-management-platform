import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabaseClient } from "@platform/database";
import { buildApp } from "../app.js";
import type { ApiConfig } from "../config.js";
import { issueSessionToken } from "../security/session-token.js";

const enabled = process.env.DATABASE_URL?.includes("/platform_test") ?? false;
const origin = "http://127.0.0.1:3000";
const config: ApiConfig = {
  host: "127.0.0.1",
  port: 13002,
  publicOrigin: origin,
  cookieSecure: false,
  sessionTtlSeconds: 43_200,
  loginLockoutThreshold: 5,
  loginLockoutMs: 900_000,
};

describe.skipIf(!enabled)("inventory API authorization and persistence", () => {
  const db = createDatabaseClient();
  let app: Awaited<ReturnType<typeof buildApp>>;
  let operatorCookie = "";
  let viewerCookie = "";
  let branchId = "";
  let otherBranchId = "";
  let switchAssetId = "";

  async function createPrincipal(role: "OPERATOR" | "VIEWER", suffix: string) {
    const user = await db.user.create({
      data: {
        username: `m2_${role.toLowerCase()}_${suffix}`,
        usernameNormalized: `m2_${role.toLowerCase()}_${suffix}`,
        passwordHash: "not-used-by-this-test",
        role,
        status: "ACTIVE",
      },
    });
    const token = issueSessionToken();
    await db.session.create({
      data: {
        userId: user.id,
        tokenHash: token.tokenHash,
        authEpoch: user.authEpoch,
        expiresAt: new Date(Date.now() + config.sessionTtlSeconds * 1000),
      },
    });
    return `platform_session=${token.token}`;
  }

  beforeAll(async () => {
    const suffix = randomUUID().replaceAll("-", "").slice(0, 10).toUpperCase();
    const branch = await db.branch.create({ data: { branchCode: `M2-${suffix}`, name: "M2 test branch" } });
    const other = await db.branch.create({ data: { branchCode: `M2O-${suffix}`, name: "M2 other branch" } });
    branchId = branch.id;
    otherBranchId = other.id;
    const operator = await createPrincipal("OPERATOR", suffix);
    const viewer = await createPrincipal("VIEWER", suffix);
    operatorCookie = operator;
    viewerCookie = viewer;
    await db.userBranchAccess.create({
      data: {
        userId: (await db.user.findFirstOrThrow({ where: { username: `m2_operator_${suffix}` } })).id,
        branchId,
      },
    });
    await db.userBranchAccess.create({
      data: {
        userId: (await db.user.findFirstOrThrow({ where: { username: `m2_viewer_${suffix}` } })).id,
        branchId,
      },
    });
    app = await buildApp({ db, config, logger: false });
  }, 30_000);

  afterAll(async () => {
    await app?.close();
    await db.$disconnect();
  });

  it("enforces branch scope and role policy for assets and switch-port metadata", async () => {
    const createSwitch = await app.inject({
      method: "POST",
      url: "/api/v1/inventory/assets",
      headers: { origin, cookie: operatorCookie },
      payload: {
        branchId,
        assetCode: "SW-CORE-01",
        name: "Core switch",
        kind: "SWITCH",
        primaryIp: "192.0.2.10",
        vendor: "Cisco",
        model: "Catalyst test",
        switch: { sysName: "core-sw-01", reportedPortCount: 48 },
      },
    });
    expect(createSwitch.statusCode).toBe(201);
    switchAssetId = createSwitch.json().asset.id as string;

    const viewerWrite = await app.inject({
      method: "POST",
      url: "/api/v1/inventory/assets",
      headers: { origin, cookie: viewerCookie },
      payload: { branchId, assetCode: "PC-01", name: "POS terminal", kind: "POS" },
    });
    expect(viewerWrite.statusCode).toBe(403);

    const crossBranchWrite = await app.inject({
      method: "POST",
      url: "/api/v1/inventory/assets",
      headers: { origin, cookie: operatorCookie },
      payload: { branchId: otherBranchId, assetCode: "PC-02", name: "Other branch PC", kind: "COMPUTER" },
    });
    expect(crossBranchWrite.statusCode).toBe(404);

    const createPort = await app.inject({
      method: "POST",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports`,
      headers: { origin, cookie: operatorCookie },
      payload: {
        ifIndex: 1,
        name: "GigabitEthernet1/0/1",
        alias: "Checkout 01",
        description: "Main checkout terminal",
        configuredVlanId: 7,
        connectedDeviceLabel: "POS-01",
      },
    });
    expect(createPort.statusCode).toBe(201);
    const portId = createPort.json().port.id as string;
    expect(createPort.json().port.configuredVlanId).toBe(7);

    const viewerPortWrite = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports/${portId}`,
      headers: { origin, cookie: viewerCookie },
      payload: { version: 1, description: "unauthorized change" },
    });
    expect(viewerPortWrite.statusCode).toBe(403);

    const listPorts = await app.inject({
      method: "GET",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports`,
      headers: { cookie: viewerCookie },
    });
    expect(listPorts.statusCode).toBe(200);
    expect(listPorts.json().ports).toHaveLength(1);

    const updateAsset = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}`,
      headers: { origin, cookie: operatorCookie },
      payload: { version: 1, location: "Server room / Rack 02" },
    });
    expect(updateAsset.statusCode).toBe(200);
    expect(updateAsset.json().asset.version).toBe(2);

    const staleUpdate = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}`,
      headers: { origin, cookie: operatorCookie },
      payload: { version: 1, location: "stale write" },
    });
    expect(staleUpdate.statusCode).toBe(409);
  });
});
