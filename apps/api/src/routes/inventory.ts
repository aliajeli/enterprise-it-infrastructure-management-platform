import { isIP } from "node:net";
import type { FastifyInstance } from "fastify";
import type { PrismaClient } from "@platform/database";
import type { ApiConfig } from "../config.js";
import { requireBranchAction, requirePlatformAction } from "../security/authorization.js";

type AssetKind =
  | "COMPUTER" | "SERVER" | "SWITCH" | "ROUTER" | "FIREWALL"
  | "NVR" | "CAMERA" | "PRINTER" | "POS" | "UPS" | "OTHER";
type PortText = string | null | undefined;

interface AssetQuery {
  branchId?: string;
  kind?: AssetKind;
  q?: string;
  limit?: number;
  offset?: number;
}

interface ObservationQuery {
  limit?: number;
  offset?: number;
}

interface CreateAssetBody {
  branchId: string;
  assetCode: string;
  name: string;
  kind: AssetKind;
  hostname?: string;
  primaryIp?: string;
  macAddress?: string;
  vendor?: string;
  model?: string;
  serialNumber?: string;
  location?: string;
  description?: string;
  switch?: {
    sysName?: string;
    sysDescr?: string;
    sysObjectId?: string;
    firmwareVersion?: string;
    reportedPortCount?: number;
  };
}


interface UpdateAssetBody {
  version: number;
  assetCode?: string;
  name?: string;
  status?: "ACTIVE" | "INACTIVE" | "RETIRED";
  hostname?: string;
  primaryIp?: string | null;
  macAddress?: string | null;
  vendor?: string;
  model?: string;
  serialNumber?: string;
  location?: string;
  description?: string;
}

interface CreatePortBody {
  ifIndex: number;
  name?: string;
  alias?: string;
  description?: string;
  configuredVlanId?: number;
  configuredTaggedVlans?: number[];
  connectedDeviceLabel?: string;
}

interface UpdatePortBody extends Omit<CreatePortBody, "configuredVlanId"> {
  version: number;
  configuredVlanId?: number | null;
}

function clean(value: PortText, max: number): string | undefined {
  if (value === undefined || value === null) return undefined;
  const result = value.trim();
  return result.length ? result.slice(0, max) : undefined;
}

function validMac(value: string): boolean {
  return /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i.test(value);
}

function validVlan(value: number | null | undefined): boolean {
  return value === undefined || value === null || (Number.isInteger(value) && value >= 1 && value <= 4094);
}

function validTaggedVlans(values: number[] | undefined): boolean {
  return values === undefined ||
    (values.length <= 4094 &&
      values.every((value) => Number.isInteger(value) && value >= 1 && value <= 4094) &&
      new Set(values).size === values.length);
}

function isPrismaCode(error: unknown, code: string): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === code;
}

function presentAsset(asset: {
  id: string; branchId: string; assetCode: string; name: string; kind: string;
  status: string; hostname: string | null; primaryIp: string | null;
  macAddress: string | null; vendor: string | null; model: string | null;
  serialNumber: string | null; location: string | null; description: string | null;
  version: number; createdAt: Date; updatedAt: Date;
}) {
  return asset;
}

export async function registerInventoryRoutes(
  app: FastifyInstance,
  db: PrismaClient,
  config: ApiConfig,
): Promise<void> {
  app.get<{ Querystring: AssetQuery }>(
    "/api/v1/inventory/assets",
    {
      schema: {
        querystring: {
          type: "object",
          additionalProperties: false,
          properties: {
            branchId: { type: "string", format: "uuid" },
            kind: { type: "string", enum: ["COMPUTER", "SERVER", "SWITCH", "ROUTER", "FIREWALL", "NVR", "CAMERA", "PRINTER", "POS", "UPS", "OTHER"] },
            q: { type: "string", maxLength: 120 },
            limit: { type: "integer", minimum: 1, maximum: 100, default: 50 },
            offset: { type: "integer", minimum: 0, maximum: 100000, default: 0 },
          },
        },
      },
    },
    async (request, reply) => {
      const actor = await requirePlatformAction(db, config, request, reply, "inventory.read");
      if (!actor) return;

      let branchIds: string[] | undefined;
      if (actor.user.role !== "ADMIN") {
        const grants = await db.userBranchAccess.findMany({
          where: {
            userId: actor.user.id,
            revokedAt: null,
            branch: { is: { status: "ACTIVE", deletedAt: null } },
          },
          select: { branchId: true },
        });
        branchIds = grants.map((grant) => grant.branchId);
      }
      if (request.query.branchId) {
        if (branchIds && !branchIds.includes(request.query.branchId)) {
          return reply.code(404).send({ error: { code: "RESOURCE_NOT_FOUND", message: "The requested resource was not found." } });
        }
        branchIds = [request.query.branchId];
      }

      const q = request.query.q?.trim();
      const searchConditions = q
        ? [
            { name: { contains: q, mode: "insensitive" as const } },
            { assetCode: { contains: q, mode: "insensitive" as const } },
            { hostname: { contains: q, mode: "insensitive" as const } },
            ...(isIP(q) ? [{ primaryIp: { equals: q } }] : []),
          ]
        : undefined;
      const where = {
        deletedAt: null,
        ...(branchIds ? { branchId: { in: branchIds } } : {}),
        ...(request.query.kind ? { kind: request.query.kind } : {}),
        ...(searchConditions ? { OR: searchConditions } : {}),
      };
      const [assets, total] = await db.$transaction([
        db.asset.findMany({
          where,
          orderBy: [{ branchId: "asc" }, { assetCode: "asc" }],
          take: request.query.limit ?? 50,
          skip: request.query.offset ?? 0,
          include: { switch: { include: { _count: { select: { ports: true } } } } },
        }),
        db.asset.count({ where }),
      ]);
      return reply.send({
        assets: assets.map((asset) => ({
          ...presentAsset(asset),
          switch: asset.switch
            ? { ...asset.switch, portCount: asset.switch._count.ports, _count: undefined }
            : null,
        })),
        page: {
          limit: request.query.limit ?? 50,
          offset: request.query.offset ?? 0,
          total,
        },
      });
    },
  );

  app.post<{ Body: CreateAssetBody }>(
    "/api/v1/inventory/assets",
    {
      config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
      schema: {
        body: {
          type: "object",
          required: ["branchId", "assetCode", "name", "kind"],
          additionalProperties: false,
          properties: {
            branchId: { type: "string", format: "uuid" },
            assetCode: { type: "string", minLength: 2, maxLength: 64 },
            name: { type: "string", minLength: 2, maxLength: 160 },
            kind: { type: "string", enum: ["COMPUTER", "SERVER", "SWITCH", "ROUTER", "FIREWALL", "NVR", "CAMERA", "PRINTER", "POS", "UPS", "OTHER"] },
            hostname: { type: "string", maxLength: 255 },
            primaryIp: { type: "string", maxLength: 64 },
            macAddress: { type: "string", maxLength: 17 },
            vendor: { type: "string", maxLength: 120 },
            model: { type: "string", maxLength: 120 },
            serialNumber: { type: "string", maxLength: 160 },
            location: { type: "string", maxLength: 255 },
            description: { type: "string", maxLength: 2000 },
            switch: {
              type: "object",
              additionalProperties: false,
              properties: {
                sysName: { type: "string", maxLength: 255 },
                sysDescr: { type: "string", maxLength: 1000 },
                sysObjectId: { type: "string", maxLength: 255 },
                firmwareVersion: { type: "string", maxLength: 160 },
                reportedPortCount: { type: "integer", minimum: 0, maximum: 4096 },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const body = request.body;
      const actor = await requireBranchAction(db, config, request, reply, body.branchId, "inventory.write");
      if (!actor) return;

      const assetCode = body.assetCode.trim().toUpperCase();
      const name = body.name.trim();
      const primaryIp = body.primaryIp?.trim();
      const macAddress = body.macAddress?.trim().toLowerCase();
      if (!/^[A-Z0-9][A-Z0-9._-]{1,63}$/.test(assetCode) || name.length < 2 ||
          (primaryIp && isIP(primaryIp) === 0) ||
          (macAddress && !validMac(macAddress)) ||
          (body.kind === "SWITCH" && !body.switch) ||
          (body.kind !== "SWITCH" && body.switch)) {
        return reply.code(400).send({
          error: { code: "INVALID_ASSET", message: "Asset fields or switch details are invalid." },
        });
      }

      try {
        const asset = await db.$transaction(async (tx) => {
          const created = await tx.asset.create({
            data: {
              branchId: body.branchId,
              assetCode,
              name,
              kind: body.kind,
              hostname: clean(body.hostname, 255),
              primaryIp,
              macAddress,
              vendor: clean(body.vendor, 120),
              model: clean(body.model, 120),
              serialNumber: clean(body.serialNumber, 160),
              location: clean(body.location, 255),
              description: clean(body.description, 2000),
              ...(body.switch ? {
                switch: { create: {
                  sysName: clean(body.switch.sysName, 255),
                  sysDescr: clean(body.switch.sysDescr, 1000),
                  sysObjectId: clean(body.switch.sysObjectId, 255),
                  firmwareVersion: clean(body.switch.firmwareVersion, 160),
                  reportedPortCount: body.switch.reportedPortCount,
                } },
              } : {}),
            },
            include: { switch: true },
          });
          await tx.auditEvent.create({
            data: {
              actorUserId: actor.user.id,
              actorType: "USER",
              action: "ASSET_CREATED",
              objectType: "asset",
              objectId: created.id,
              outcome: "SUCCESS",
              requestId: request.id,
              sourceIp: request.ip,
              metadata: { branchId: body.branchId, assetCode, kind: body.kind },
            },
          });
          return created;
        });
        return reply.code(201).send({ asset });
      } catch (error) {
        if (isPrismaCode(error, "P2002")) {
          return reply.code(409).send({ error: { code: "ASSET_CODE_EXISTS", message: "This asset code is already used in the branch." } });
        }
        throw error;
      }
    },
  );


  app.patch<{ Params: { assetId: string }; Body: UpdateAssetBody }>(
    "/api/v1/inventory/assets/:assetId",
    {
      schema: {
        params: { type: "object", required: ["assetId"], properties: { assetId: { type: "string", format: "uuid" } } },
        body: {
          type: "object", required: ["version"], additionalProperties: false,
          properties: {
            version: { type: "integer", minimum: 1 },
            assetCode: { type: "string", minLength: 2, maxLength: 64 },
            name: { type: "string", minLength: 2, maxLength: 160 },
            status: { type: "string", enum: ["ACTIVE", "INACTIVE", "RETIRED"] },
            hostname: { type: "string", maxLength: 255 },
            primaryIp: { type: ["string", "null"], maxLength: 64 },
            macAddress: { type: ["string", "null"], maxLength: 17 },
            vendor: { type: "string", maxLength: 120 },
            model: { type: "string", maxLength: 120 },
            serialNumber: { type: "string", maxLength: 160 },
            location: { type: "string", maxLength: 255 },
            description: { type: "string", maxLength: 2000 },
          },
        },
      },
    },
    async (request, reply) => {
      const existing = await db.asset.findFirst({
        where: { id: request.params.assetId, deletedAt: null },
        select: { id: true, branchId: true, kind: true },
      });
      if (!existing) {
        return reply.code(404).send({ error: { code: "ASSET_NOT_FOUND", message: "Asset not found." } });
      }
      const actor = await requireBranchAction(db, config, request, reply, existing.branchId, "inventory.write");
      if (!actor) return;
      const body = request.body;
      const assetCode = body.assetCode?.trim().toUpperCase();
      const primaryIp = body.primaryIp === null ? null : body.primaryIp?.trim();
      const macAddress = body.macAddress === null ? null : body.macAddress?.trim().toLowerCase();
      if ((assetCode !== undefined && !/^[A-Z0-9][A-Z0-9._-]{1,63}$/.test(assetCode)) ||
          (primaryIp !== undefined && primaryIp !== null && primaryIp.length > 0 && isIP(primaryIp) === 0) ||
          (macAddress !== undefined && macAddress !== null && macAddress.length > 0 && !validMac(macAddress))) {
        return reply.code(400).send({ error: { code: "INVALID_ASSET", message: "Asset fields are invalid." } });
      }
      try {
        const updated = await db.$transaction(async (tx) => {
          const changed = await tx.asset.updateMany({
            where: { id: existing.id, version: body.version, deletedAt: null },
            data: {
              ...(assetCode !== undefined ? { assetCode } : {}),
              ...(body.name !== undefined ? { name: body.name.trim() } : {}),
              ...(body.status !== undefined ? { status: body.status } : {}),
              ...(body.hostname !== undefined ? { hostname: clean(body.hostname, 255) ?? null } : {}),
              ...(body.primaryIp !== undefined ? { primaryIp: primaryIp || null } : {}),
              ...(body.macAddress !== undefined ? { macAddress: macAddress || null } : {}),
              ...(body.vendor !== undefined ? { vendor: clean(body.vendor, 120) ?? null } : {}),
              ...(body.model !== undefined ? { model: clean(body.model, 120) ?? null } : {}),
              ...(body.serialNumber !== undefined ? { serialNumber: clean(body.serialNumber, 160) ?? null } : {}),
              ...(body.location !== undefined ? { location: clean(body.location, 255) ?? null } : {}),
              ...(body.description !== undefined ? { description: clean(body.description, 2000) ?? null } : {}),
              version: { increment: 1 },
            },
          });
          if (changed.count !== 1) return null;
          const asset = await tx.asset.findUniqueOrThrow({ where: { id: existing.id } });
          await tx.auditEvent.create({
            data: {
              actorUserId: actor.user.id,
              actorType: "USER",
              action: "ASSET_UPDATED",
              objectType: "asset",
              objectId: asset.id,
              outcome: "SUCCESS",
              requestId: request.id,
              sourceIp: request.ip,
              metadata: { branchId: asset.branchId, version: asset.version },
            },
          });
          return asset;
        });
        if (!updated) {
          return reply.code(409).send({ error: { code: "ASSET_VERSION_CONFLICT", message: "Asset changed or no longer exists. Refresh and retry." } });
        }
        return reply.send({ asset: updated });
      } catch (error) {
        if (isPrismaCode(error, "P2002")) {
          return reply.code(409).send({ error: { code: "ASSET_CODE_EXISTS", message: "This asset code is already used in the branch." } });
        }
        throw error;
      }
    },
  );

  app.get<{ Params: { assetId: string } }>(
    "/api/v1/inventory/assets/:assetId/switch-ports",
    {
      schema: { params: { type: "object", required: ["assetId"], properties: { assetId: { type: "string", format: "uuid" } } } },
    },
    async (request, reply) => {
      const asset = await db.asset.findFirst({
        where: { id: request.params.assetId, kind: "SWITCH", deletedAt: null },
        include: { switch: { include: { ports: { orderBy: { ifIndex: "asc" }, include: { observations: { orderBy: { observedAt: "desc" }, take: 1 } } } } } },
      });
      if (!asset?.switch) {
        return reply.code(404).send({ error: { code: "SWITCH_NOT_FOUND", message: "Switch not found." } });
      }
      const actor = await requireBranchAction(db, config, request, reply, asset.branchId, "switch.metadata.read");
      if (!actor) return;
      return reply.send({ switch: { assetId: asset.id, name: asset.name }, ports: asset.switch.ports });
    },
  );

  app.get<{ Params: { assetId: string; portId: string }; Querystring: ObservationQuery }>(
    "/api/v1/inventory/assets/:assetId/switch-ports/:portId/observations",
    {
      schema: {
        params: {
          type: "object", required: ["assetId", "portId"],
          properties: {
            assetId: { type: "string", format: "uuid" },
            portId: { type: "string", format: "uuid" },
          },
        },
        querystring: {
          type: "object", additionalProperties: false,
          properties: {
            limit: { type: "integer", minimum: 1, maximum: 100, default: 25 },
            offset: { type: "integer", minimum: 0, maximum: 100000, default: 0 },
          },
        },
      },
    },
    async (request, reply) => {
      const port = await db.switchPort.findFirst({
        where: {
          id: request.params.portId,
          switch: { assetId: request.params.assetId, asset: { deletedAt: null } },
        },
        select: {
          id: true,
          ifIndex: true,
          switch: { select: { asset: { select: { branchId: true } } } },
        },
      });
      if (!port) {
        return reply.code(404).send({ error: { code: "SWITCH_PORT_NOT_FOUND", message: "Switch port not found." } });
      }
      const actor = await requireBranchAction(
        db, config, request, reply, port.switch.asset.branchId, "switch.metadata.read",
      );
      if (!actor) return;

      const limit = request.query.limit ?? 25;
      const offset = request.query.offset ?? 0;
      const where = { portId: port.id };
      const [observations, total] = await db.$transaction([
        db.portObservation.findMany({
          where,
          orderBy: [{ observedAt: "desc" }, { id: "desc" }],
          take: limit,
          skip: offset,
          select: {
            id: true, source: true, observedAt: true, adminState: true, operState: true,
            vlanId: true, ipAddress: true, macAddress: true, speedMbps: true,
          },
        }),
        db.portObservation.count({ where }),
      ]);
      return reply.send({
        port: { id: port.id, ifIndex: port.ifIndex },
        observations,
        page: { limit, offset, total },
      });
    },
  );

  app.post<{ Params: { assetId: string }; Body: CreatePortBody }>(
    "/api/v1/inventory/assets/:assetId/switch-ports",
    {
      schema: {
        params: { type: "object", required: ["assetId"], properties: { assetId: { type: "string", format: "uuid" } } },
        body: {
          type: "object",
          required: ["ifIndex"],
          additionalProperties: false,
          properties: {
            ifIndex: { type: "integer", minimum: 1, maximum: 65535 },
            name: { type: "string", maxLength: 160 },
            alias: { type: "string", maxLength: 160 },
            description: { type: "string", maxLength: 1000 },
            configuredVlanId: { type: "integer", minimum: 1, maximum: 4094 },
            configuredTaggedVlans: { type: "array", maxItems: 4094, uniqueItems: true, items: { type: "integer", minimum: 1, maximum: 4094 } },
            connectedDeviceLabel: { type: "string", maxLength: 255 },
          },
        },
      },
    },
    async (request, reply) => {
      const asset = await db.asset.findFirst({
        where: { id: request.params.assetId, kind: "SWITCH", deletedAt: null },
        include: { switch: true },
      });
      if (!asset?.switch) {
        return reply.code(404).send({ error: { code: "SWITCH_NOT_FOUND", message: "Switch not found." } });
      }
      const actor = await requireBranchAction(db, config, request, reply, asset.branchId, "switch.metadata.write");
      if (!actor) return;
      const body = request.body;
      if (!validVlan(body.configuredVlanId) || !validTaggedVlans(body.configuredTaggedVlans)) {
        return reply.code(400).send({ error: { code: "INVALID_VLAN", message: "VLAN IDs must be unique integers from 1 through 4094." } });
      }
      try {
        const port = await db.$transaction(async (tx) => {
          const created = await tx.switchPort.create({
            data: {
              switchId: asset.switch!.id,
              ifIndex: body.ifIndex,
              name: clean(body.name, 160),
              alias: clean(body.alias, 160),
              description: clean(body.description, 1000),
              configuredVlanId: body.configuredVlanId,
              configuredTaggedVlans: body.configuredTaggedVlans ?? [],
              connectedDeviceLabel: clean(body.connectedDeviceLabel, 255),
            },
          });
          await tx.auditEvent.create({
            data: {
              actorUserId: actor.user.id,
              actorType: "USER",
              action: "SWITCH_PORT_METADATA_CREATED",
              objectType: "switch_port",
              objectId: created.id,
              outcome: "SUCCESS",
              requestId: request.id,
              sourceIp: request.ip,
              metadata: { assetId: asset.id, ifIndex: body.ifIndex, configuredVlanId: body.configuredVlanId },
            },
          });
          return created;
        });
        return reply.code(201).send({ port });
      } catch (error) {
        if (isPrismaCode(error, "P2002")) {
          return reply.code(409).send({ error: { code: "SWITCH_PORT_EXISTS", message: "A port with this interface index already exists." } });
        }
        throw error;
      }
    },
  );

  app.patch<{ Params: { assetId: string; portId: string }; Body: UpdatePortBody }>(
    "/api/v1/inventory/assets/:assetId/switch-ports/:portId",
    {
      schema: {
        params: {
          type: "object", required: ["assetId", "portId"],
          properties: { assetId: { type: "string", format: "uuid" }, portId: { type: "string", format: "uuid" } },
        },
        body: {
          type: "object", required: ["version"], additionalProperties: false,
          properties: {
            version: { type: "integer", minimum: 1 },
            name: { type: "string", maxLength: 160 },
            alias: { type: "string", maxLength: 160 },
            description: { type: "string", maxLength: 1000 },
            configuredVlanId: { type: ["integer", "null"], minimum: 1, maximum: 4094 },
            configuredTaggedVlans: { type: "array", maxItems: 4094, uniqueItems: true, items: { type: "integer", minimum: 1, maximum: 4094 } },
            connectedDeviceLabel: { type: "string", maxLength: 255 },
          },
        },
      },
    },
    async (request, reply) => {
      const asset = await db.asset.findFirst({
        where: { id: request.params.assetId, kind: "SWITCH", deletedAt: null },
        include: { switch: true },
      });
      if (!asset?.switch) {
        return reply.code(404).send({ error: { code: "SWITCH_NOT_FOUND", message: "Switch not found." } });
      }
      const actor = await requireBranchAction(db, config, request, reply, asset.branchId, "switch.metadata.write");
      if (!actor) return;
      const body = request.body;
      if (!validVlan(body.configuredVlanId) || !validTaggedVlans(body.configuredTaggedVlans)) {
        return reply.code(400).send({ error: { code: "INVALID_VLAN", message: "VLAN IDs must be unique integers from 1 through 4094." } });
      }
      const updated = await db.$transaction(async (tx) => {
        const changed = await tx.switchPort.updateMany({
          where: { id: request.params.portId, switchId: asset.switch!.id, version: body.version },
          data: {
            ...(body.name !== undefined ? { name: clean(body.name, 160) ?? null } : {}),
            ...(body.alias !== undefined ? { alias: clean(body.alias, 160) ?? null } : {}),
            ...(body.description !== undefined ? { description: clean(body.description, 1000) ?? null } : {}),
            ...(body.configuredVlanId !== undefined ? { configuredVlanId: body.configuredVlanId } : {}),
            ...(body.configuredTaggedVlans !== undefined ? { configuredTaggedVlans: body.configuredTaggedVlans } : {}),
            ...(body.connectedDeviceLabel !== undefined ? { connectedDeviceLabel: clean(body.connectedDeviceLabel, 255) ?? null } : {}),
            version: { increment: 1 },
          },
        });
        if (changed.count !== 1) return null;
        const port = await tx.switchPort.findUniqueOrThrow({ where: { id: request.params.portId } });
        await tx.auditEvent.create({
          data: {
            actorUserId: actor.user.id,
            actorType: "USER",
            action: "SWITCH_PORT_METADATA_UPDATED",
            objectType: "switch_port",
            objectId: port.id,
            outcome: "SUCCESS",
            requestId: request.id,
            sourceIp: request.ip,
            metadata: { assetId: asset.id, ifIndex: port.ifIndex, version: port.version },
          },
        });
        return port;
      });
      if (!updated) {
        return reply.code(409).send({ error: { code: "PORT_VERSION_CONFLICT", message: "Port changed or no longer exists. Refresh and retry." } });
      }
      return reply.send({ port: updated });
    },
  );
}
