import { AsyncLocalStorage } from "node:async_hooks";
import { spawn, type ChildProcess } from "node:child_process";
import { win32 as pathWin32 } from "node:path";
import type { CredentialKeyringStorage } from "./credential-keyring.js";
import { decodeKeyringFrame, decodeKeyringUtf8, encodeKeyringFrame, KeyringOpcode } from "./windows-keyring-protocol.js";

const MAX_PAYLOAD_BYTES = 32 * 1024;
const RESPONSE_TIMEOUT_MS = 10_000;

interface HelperProcess {
  stdin: NonNullable<ChildProcess["stdin"]>;
  stdout: NonNullable<ChildProcess["stdout"]>;
  once(event: "error", listener: (error: Error) => void): this;
  once(event: "close", listener: (code: number | null) => void): this;
  exitCode: number | null;
  kill(): boolean;
}
type SpawnHelper = (path: string) => HelperProcess;

class FrameChannel {
  private buffer = Buffer.alloc(0);
  private pending: { resolve: (frame: Buffer) => void; reject: (error: Error) => void } | undefined;
  private failed = false;

  constructor(private readonly process: HelperProcess) {
    process.stdout.on("data", (chunk: Buffer) => this.onData(Buffer.from(chunk)));
    process.once("error", () => this.fail());
    process.once("close", () => this.fail());
  }

  receive(): Promise<Buffer> {
    if (this.failed || this.pending) return Promise.reject(new Error("Windows keyring helper channel is unavailable."));
    return new Promise((resolve, reject) => {
      this.pending = { resolve, reject };
      this.consume();
    });
  }

  close(): void {
    this.fail();
  }

  private onData(chunk: Buffer): void {
    if (this.failed || !this.pending) {
      chunk.fill(0);
      this.fail();
      return;
    }
    if (this.buffer.length + chunk.length > MAX_PAYLOAD_BYTES + 6) {
      chunk.fill(0);
      this.fail();
      return;
    }
    this.buffer = Buffer.concat([this.buffer, chunk]);
    chunk.fill(0);
    this.consume();
  }

  private consume(): void {
    if (!this.pending || this.buffer.length < 6) return;
    const length = this.buffer.readUInt32BE(2);
    if (length > MAX_PAYLOAD_BYTES) { this.fail(); return; }
    const frameLength = 6 + length;
    if (this.buffer.length < frameLength) return;
    if (this.buffer.length !== frameLength) { this.fail(); return; }
    const frame = this.buffer;
    this.buffer = Buffer.alloc(0);
    const pending = this.pending;
    this.pending = undefined;
    pending.resolve(frame);
  }

  private fail(): void {
    if (this.failed) return;
    this.failed = true;
    this.buffer.fill(0);
    this.buffer = Buffer.alloc(0);
    const pending = this.pending;
    this.pending = undefined;
    pending?.reject(new Error("Windows keyring helper channel failed."));
  }
}

class WindowsKeyringTransaction {
  constructor(private readonly process: HelperProcess, private readonly channel: FrameChannel) {}

  async begin(): Promise<void> {
    await this.exchange(KeyringOpcode.BEGIN_TRANSACTION, Buffer.alloc(0), KeyringOpcode.BEGIN_OK, 0);
  }

  async read(): Promise<string | null> {
    const payload = await this.exchange(KeyringOpcode.READ_REGISTRY, Buffer.alloc(0), KeyringOpcode.READ_RESULT);
    if (payload.length < 1) throw new Error("Windows keyring helper returned an invalid read result.");
    const status = payload.readUInt8(0);
    if (status === 1 && payload.length === 1) return null;
    if (status !== 0 || payload.length === 1) throw new Error("Windows keyring helper returned an invalid read result.");
    return decodeKeyringUtf8(payload.subarray(1));
  }

  async write(contents: string): Promise<void> {
    const payload = Buffer.from(contents, "utf8");
    try {
      if (payload.length > MAX_PAYLOAD_BYTES) throw new Error("Credential keyring registry exceeds the size limit.");
      await this.exchange(KeyringOpcode.WRITE_REGISTRY_ATOMIC, payload, KeyringOpcode.WRITE_OK, 0);
    } finally { payload.fill(0); }
  }

  async end(): Promise<void> {
    await this.exchange(KeyringOpcode.END_TRANSACTION, Buffer.alloc(0), KeyringOpcode.END_OK, 0);
    this.process.stdin.end();
    await this.waitForSuccessfulExit();
  }

  private async waitForSuccessfulExit(): Promise<void> {
    const currentExitCode = this.process.exitCode;
    if (currentExitCode !== null) {
      if (currentExitCode !== 0) throw new Error("Windows keyring helper did not exit cleanly.");
      return;
    }

    await new Promise<void>((resolve, reject) => {
      let settled = false;
      const finish = (code: number | null) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        if (code === 0) resolve();
        else reject(new Error("Windows keyring helper did not exit cleanly."));
      };
      const timeout = setTimeout(() => {
        if (settled) return;
        this.process.kill();
        finish(null);
      }, RESPONSE_TIMEOUT_MS);
      this.process.once("close", finish);
      if (this.process.exitCode !== null) finish(this.process.exitCode);
    });
  }

  abort(): void {
    this.channel.close();
    this.process.kill();
  }

  private async exchange(
    opcode: number,
    payload: Buffer,
    expectedOpcode: number,
    expectedPayloadLength?: number,
  ): Promise<Buffer> {
    const frame = encodeKeyringFrame(opcode as never, payload);
    const responsePromise = this.channel.receive();
    const timeout = setTimeout(() => this.process.kill(), RESPONSE_TIMEOUT_MS);
    try {
      await new Promise<void>((resolve, reject) => {
        this.process.stdin.write(frame, (error) => error ? reject(error) : resolve());
      });
      const responseFrame = await responsePromise;
      try {
        const response = decodeKeyringFrame(responseFrame);
        if (response.opcode === KeyringOpcode.ERROR && response.payload.length === 1) {
          throw new Error("Windows keyring helper operation failed.");
        }
        if (response.opcode !== expectedOpcode ||
            (expectedPayloadLength !== undefined && response.payload.length !== expectedPayloadLength)) {
          throw new Error("Windows keyring helper protocol failure.");
        }
        return response.payload;
      } finally { responseFrame.fill(0); }
    } catch {
      this.abort();
      throw new Error("Windows keyring helper operation failed.");
    } finally {
      clearTimeout(timeout);
      frame.fill(0);
    }
  }
}

/**
 * Transport adapter only. The matching .NET storage operations and installer
 * provisioning are separate gates; this class is deliberately not registered
 * in the API composition root.
 */
export class WindowsKeyringStorageClient implements CredentialKeyringStorage {
  private readonly context = new AsyncLocalStorage<WindowsKeyringTransaction>();
  private tail: Promise<void> = Promise.resolve();

  constructor(
    private readonly helperPath: string,
    private readonly platform: NodeJS.Platform = process.platform,
    private readonly spawnHelper: SpawnHelper = (path) => {
      const child = spawn(path, [], { shell: false, windowsHide: true, stdio: ["pipe", "pipe", "ignore"] });
      if (!child.stdin || !child.stdout) throw new Error("Windows keyring helper pipes are unavailable.");
      return child as HelperProcess;
    },
  ) {
    if (platform !== "win32") throw new Error("Windows keyring storage is available only on Windows.");
    if (!pathWin32.isAbsolute(helperPath)) throw new Error("Windows keyring helper path must be absolute.");
  }

  async withExclusiveLock<T>(operation: () => Promise<T>): Promise<T> {
    if (this.context.getStore()) throw new Error("Nested credential keyring transactions are not supported.");
    const previous = this.tail;
    let release!: () => void;
    this.tail = new Promise<void>((resolve) => { release = resolve; });
    await previous;
    let transaction: WindowsKeyringTransaction | undefined;
    let callbackCompleted = false;
    try {
      const child = this.spawnHelper(this.helperPath);
      const channel = new FrameChannel(child);
      transaction = new WindowsKeyringTransaction(child, channel);
      await transaction.begin();
      const result = await this.context.run(transaction, operation);
      callbackCompleted = true;
      return result;
    } catch (error) {
      transaction?.abort();
      throw error;
    } finally {
      try {
        if (transaction && callbackCompleted) {
          try { await transaction.end(); }
          catch {
            transaction.abort();
            throw new Error("Windows keyring helper session did not terminate cleanly.");
          }
        } else {
          transaction?.abort();
        }
      } finally {
        release();
      }
    }
  }

  read(): Promise<string | null> {
    const transaction = this.context.getStore();
    if (!transaction) return Promise.reject(new Error("Credential keyring read requires an active transaction."));
    return transaction.read();
  }

  writeAtomic(contents: string): Promise<void> {
    const transaction = this.context.getStore();
    if (!transaction) return Promise.reject(new Error("Credential keyring write requires an active transaction."));
    return transaction.write(contents);
  }
}
