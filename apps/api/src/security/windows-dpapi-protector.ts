import { spawn } from "node:child_process";
import { isAbsolute } from "node:path";

const PROTOCOL_VERSION = 1;
const OP_PROTECT = 1;
const OP_UNPROTECT = 2;
const KEY_BYTES = 32;
const MAX_FRAME_BYTES = 16 * 1024;
const RESPONSE_TIMEOUT_MS = 5_000;

function encodeRequest(operation: number, installationId: string, key: Buffer): Buffer {
  const installation = Buffer.from(installationId, "utf8");
  if (installation.length < 1 || installation.length > 128 || key.length !== KEY_BYTES) {
    throw new Error("Invalid DPAPI request.");
  }
  const body = Buffer.allocUnsafe(8 + installation.length + key.length);
  body.writeUInt8(PROTOCOL_VERSION, 0);
  body.writeUInt8(operation, 1);
  body.writeUInt16BE(installation.length, 2);
  body.writeUInt32BE(key.length, 4);
  installation.copy(body, 8);
  key.copy(body, 8 + installation.length);
  const frame = Buffer.allocUnsafe(4 + body.length);
  frame.writeUInt32BE(body.length, 0);
  body.copy(frame, 4);
  body.fill(0);
  installation.fill(0);
  return frame;
}

function decodeResponse(frame: Buffer, operation: number): Buffer {
  if (frame.length < 9) throw new Error("DPAPI helper protocol failure.");
  const length = frame.readUInt32BE(0);
  if (length !== frame.length - 4 || length > MAX_FRAME_BYTES) {
    throw new Error("DPAPI helper protocol failure.");
  }
  const status = frame.readUInt8(4);
  const payloadLength = frame.readUInt32BE(5);
  if (
    payloadLength !== length - 5 ||
    status !== 0 ||
    payloadLength < 1 ||
    payloadLength > MAX_FRAME_BYTES ||
    (operation === OP_UNPROTECT && payloadLength !== KEY_BYTES)
  ) {
    throw new Error("DPAPI operation failed.");
  }
  return Buffer.from(frame.subarray(9));
}

/**
 * Calls a fixed-purpose .NET helper. No shell, arguments, environment secrets,
 * temporary files or textual key encoding are used. The helper path must be
 * absolute and provisioned by the trusted installer.
 */
export class WindowsDpapiProtector {
  constructor(
    private readonly helperPath: string,
    private readonly installationId: string,
    private readonly platform: NodeJS.Platform = process.platform,
  ) {
    if (!isAbsolute(helperPath)) throw new Error("DPAPI helper path must be absolute.");
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(installationId)) {
      throw new Error("Invalid installation identifier.");
    }
  }

  protect(key: Buffer): Promise<Buffer> {
    return this.invoke(OP_PROTECT, key);
  }

  unprotect(protectedKey: Buffer): Promise<Buffer> {
    return this.invoke(OP_UNPROTECT, protectedKey);
  }

  private invoke(operation: number, payload: Buffer): Promise<Buffer> {
    if (this.platform !== "win32") {
      return Promise.reject(new Error("Windows DPAPI is available only on Windows."));
    }
    if (!Buffer.isBuffer(payload) || payload.length !== KEY_BYTES) {
      return Promise.reject(new Error("DPAPI accepts exactly one 32-byte key."));
    }

    const request = encodeRequest(operation, this.installationId, payload);
    return new Promise((resolve, reject) => {
      const child = spawn(this.helperPath, [], {
        shell: false,
        windowsHide: true,
        stdio: ["pipe", "pipe", "ignore"],
      });
      const chunks: Buffer[] = [];
      let received = 0;
      let settled = false;
      const finish = (error?: Error, result?: Buffer) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        request.fill(0);
        for (const chunk of chunks) chunk.fill(0);
        if (error) reject(error);
        else if (result) resolve(result);
        else reject(new Error("DPAPI helper returned no result."));
      };
      const timeout = setTimeout(() => {
        child.kill();
        finish(new Error("DPAPI helper timed out."));
      }, RESPONSE_TIMEOUT_MS);

      child.stdout.on("data", (chunk: Buffer) => {
        received += chunk.length;
        if (received > MAX_FRAME_BYTES + 4) {
          child.kill();
          finish(new Error("DPAPI helper response exceeded the size limit."));
          return;
        }
        chunks.push(Buffer.from(chunk));
      });
      child.on("error", () => finish(new Error("DPAPI helper could not be started.")));
      child.on("close", (code) => {
        if (settled) return;
        if (code !== 0) {
          finish(new Error("DPAPI helper failed."));
          return;
        }
        const response = Buffer.concat(chunks);
        try {
          finish(undefined, decodeResponse(response, operation));
        } catch {
          finish(new Error("DPAPI helper protocol failure."));
        } finally {
          response.fill(0);
        }
      });
      child.stdin.on("error", () => finish(new Error("DPAPI helper request failed.")));
      child.stdin.end(request, () => request.fill(0));
    });
  }
}
