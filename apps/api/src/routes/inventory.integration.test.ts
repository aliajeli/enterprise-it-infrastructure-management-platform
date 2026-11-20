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
  let app: Awaited<ReturnType<typeof buildApp>> | undefined;
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
    if (!app) throw new Error("Inventory integration API was not initialized.");

    const operatorBranches = await app.inject({
      method: "GET",
      url: "/api/v1/branches/accessible",
      headers: { cookie: operatorCookie },
    });
    expect(operatorBranches.statusCode).toBe(200);
    expect(operatorBranches.json().branches.map((branch: { id: string }) => branch.id)).toEqual([branchId]);

    const viewerBranches = await app.inject({
      method: "GET",
      url: "/api/v1/branches/accessible",
      headers: { cookie: viewerCookie },
    });
    expect(viewerBranches.statusCode).toBe(200);
    expect(viewerBranches.json().branches.map((branch: { id: string }) => branch.id)).toEqual([branchId]);
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

    const exactIpSearch = await app.inject({
      method: "GET",
      url: `/api/v1/inventory/assets?branchId=${branchId}&q=192.0.2.10`,
      headers: { cookie: operatorCookie },
    });
    expect(exactIpSearch.statusCode).toBe(200);
    expect(exactIpSearch.json().page.total).toBe(1);
    expect(exactIpSearch.json().assets[0].id).toBe(switchAssetId);

    const secondPage = await app.inject({
      method: "GET",
      url: `/api/v1/inventory/assets?branchId=${branchId}&limit=1&offset=1`,
      headers: { cookie: operatorCookie },
    });
    expect(secondPage.statusCode).toBe(200);
    expect(secondPage.json().assets).toHaveLength(0);
    expect(secondPage.json().page).toEqual({ limit: 1, offset: 1, total: 1 });

    const nonMatchingSearch = await app.inject({
      method: "GET",
      url: `/api/v1/inventory/assets?branchId=${branchId}&q=NO-SUCH-ASSET-9F2C`,
      headers: { cookie: operatorCookie },
    });
    expect(nonMatchingSearch.statusCode).toBe(200);
    expect(nonMatchingSearch.json().page.total).toBe(0);
    expect(nonMatchingSearch.json().assets).toHaveLength(0);

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
      payload: {
        version: 1,
        location: "Server room / Rack 02",
        primaryIp: "192.0.2.11",
        macAddress: "02:00:00:00:00:11",
      },
    });
    expect(updateAsset.statusCode).toBe(200);
    expect(updateAsset.json().asset.version).toBe(2);
    expect(updateAsset.json().asset.primaryIp).toBe("192.0.2.11");
    expect(updateAsset.json().asset.macAddress).toBe("02:00:00:00:00:11");

    const clearNetworkIdentity = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}`,
      headers: { origin, cookie: operatorCookie },
      payload: { version: 2, primaryIp: null, macAddress: null },
    });
    expect(clearNetworkIdentity.statusCode).toBe(200);
    expect(clearNetworkIdentity.json().asset.version).toBe(3);
    expect(clearNetworkIdentity.json().asset.primaryIp).toBeNull();
    expect(clearNetworkIdentity.json().asset.macAddress).toBeNull();

    const invalidAssetIp = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}`,
      headers: { origin, cookie: operatorCookie },
      payload: { version: 3, primaryIp: "not-an-ip" },
    });
    expect(invalidAssetIp.statusCode).toBe(400);

    const invalidAssetMac = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}`,
      headers: { origin, cookie: operatorCookie },
      payload: { version: 3, macAddress: "invalid-mac" },
    });
    expect(invalidAssetMac.statusCode).toBe(400);

    const updatePort = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports/${portId}`,
      headers: { origin, cookie: operatorCookie },
      payload: {
        version: 1,
        alias: "Checkout terminal 01",
        configuredVlanId: 7,
        configuredTaggedVlans: [30, 40],
        connectedDeviceLabel: "POS-01",
      },
    });
    expect(updatePort.statusCode).toBe(200);
    expect(updatePort.json().port.version).toBe(2);
    expect(updatePort.json().port.configuredTaggedVlans).toEqual([30, 40]);

    const clearPortMetadata = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports/${portId}`,
      headers: { origin, cookie: operatorCookie },
      payload: {
        version: 2,
        alias: "",
        description: "",
        connectedDeviceLabel: "",
        configuredVlanId: null,
        configuredTaggedVlans: [],
      },
    });
    expect(clearPortMetadata.statusCode).toBe(200);
    expect(clearPortMetadata.json().port.version).toBe(3);
    expect(clearPortMetadata.json().port.alias).toBeNull();
    expect(clearPortMetadata.json().port.description).toBeNull();
    expect(clearPortMetadata.json().port.connectedDeviceLabel).toBeNull();
    expect(clearPortMetadata.json().port.configuredVlanId).toBeNull();
    expect(clearPortMetadata.json().port.configuredTaggedVlans).toEqual([]);

    const duplicateTaggedVlans = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports/${portId}`,
      headers: { origin, cookie: operatorCookie },
      payload: { version: 3, configuredTaggedVlans: [30, 30] },
    });
    expect(duplicateTaggedVlans.statusCode).toBe(400);

    const outOfRangeVlan = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports/${portId}`,
      headers: { origin, cookie: operatorCookie },
      payload: { version: 3, configuredVlanId: 4095 },
    });
    expect(outOfRangeVlan.statusCode).toBe(400);

    const stalePortUpdate = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports/${portId}`,
      headers: { origin, cookie: operatorCookie },
      payload: { version: 1, alias: "stale port edit" },
    });
    expect(stalePortUpdate.statusCode).toBe(409);

    const observation = await db.portObservation.create({
      data: {
        portId,
        source: "SNMP",
        adminState: "UP",
        operState: "UP",
        vlanId: 7,
        speedMbps: 1000,
      },
    });
    await db.portObservation.create({
      data: {
        portId,
        source: "SNMP",
        observedAt: new Date(observation.observedAt.getTime() + 1000),
        adminState: "UP",
        operState: "DOWN",
        vlanId: 7,
        speedMbps: 1000,
      },
    });

    const observationHistory = await app.inject({
      method: "GET",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports/${portId}/observations?limit=1&offset=0`,
      headers: { cookie: operatorCookie },
    });
    expect(observationHistory.statusCode).toBe(200);
    expect(observationHistory.json().page).toEqual({ limit: 1, offset: 0, total: 2 });
    expect(observationHistory.json().observations).toHaveLength(1);
    expect(observationHistory.json().observations[0].operState).toBe("DOWN");

    const observationHistorySecondPage = await app.inject({
      method: "GET",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports/${portId}/observations?limit=1&offset=1`,
      headers: { cookie: viewerCookie },
    });
    expect(observationHistorySecondPage.statusCode).toBe(200);
    expect(observationHistorySecondPage.json().page.total).toBe(2);
    expect(observationHistorySecondPage.json().observations).toHaveLength(1);
    expect(observationHistorySecondPage.json().observations[0].operState).toBe("UP");

    const mismatchedPortHistory = await app.inject({
      method: "GET",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports/${randomUUID()}/observations`,
      headers: { cookie: operatorCookie },
    });
    expect(mismatchedPortHistory.statusCode).toBe(404);

    await expect(
      db.portObservation.update({
        where: { id: observation.id },
        data: { operState: "DOWN" },
      }),
    ).rejects.toThrow(/append-only/);

    const staleUpdate = await app.inject({
      method: "PATCH",
      url: `/api/v1/inventory/assets/${switchAssetId}`,
      headers: { origin, cookie: operatorCookie },
      payload: { version: 1, location: "stale write" },
    });
    expect(staleUpdate.statusCode).toBe(409);

    await db.branch.update({ where: { id: branchId }, data: { status: "INACTIVE" } });
    const archivedBranchRead = await app.inject({
      method: "GET",
      url: `/api/v1/inventory/assets/${switchAssetId}/switch-ports`,
      headers: { cookie: operatorCookie },
    });
    expect(archivedBranchRead.statusCode).toBe(404);
  });
});
