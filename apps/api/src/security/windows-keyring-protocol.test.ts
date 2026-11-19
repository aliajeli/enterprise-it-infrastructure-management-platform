import { describe, expect, it } from "vitest";
import {
  decodeKeyringFrame,
  decodeKeyringUtf8,
  encodeKeyringFrame,
  KeyringOpcode,
} from "./windows-keyring-protocol.js";

describe("Windows keyring helper protocol framing", () => {
  it("round-trips empty transaction control frames", () => {
    const frame = encodeKeyringFrame(KeyringOpcode.BEGIN_TRANSACTION);
    expect(decodeKeyringFrame(frame)).toEqual({
      version: 1,
      opcode: KeyringOpcode.BEGIN_TRANSACTION,
      payload: Buffer.alloc(0),
    });
  });

  it("round-trips bounded UTF-8 registry payloads without path fields", () => {
    const json = JSON.stringify({ formatVersion: 1, activeVersion: "k000001", label: "شعبه مرکزی" });
    const frame = encodeKeyringFrame(KeyringOpcode.WRITE_REGISTRY_ATOMIC, Buffer.from(json, "utf8"));
    const decoded = decodeKeyringFrame(frame);
    expect(decoded.opcode).toBe(KeyringOpcode.WRITE_REGISTRY_ATOMIC);
    expect(decodeKeyringUtf8(decoded.payload)).toBe(json);
  });

  it("rejects truncated frames, length mismatches and trailing bytes", () => {
    const valid = encodeKeyringFrame(KeyringOpcode.READ_REGISTRY);
    expect(() => decodeKeyringFrame(valid.subarray(0, 5))).toThrow("Invalid keyring protocol frame");
    const truncated = Buffer.from(valid);
    truncated.writeUInt32BE(1, 2);
    expect(() => decodeKeyringFrame(truncated)).toThrow("Invalid keyring protocol frame");
    const trailing = Buffer.concat([valid, Buffer.from([0])]);
    expect(() => decodeKeyringFrame(trailing)).toThrow("Invalid keyring protocol frame");
  });

  it("rejects unsupported versions and unknown opcodes", () => {
    const badVersion = encodeKeyringFrame(KeyringOpcode.END_TRANSACTION);
    badVersion.writeUInt8(2, 0);
    expect(() => decodeKeyringFrame(badVersion)).toThrow("Invalid keyring protocol frame");
    const badOpcode = encodeKeyringFrame(KeyringOpcode.END_TRANSACTION);
    badOpcode.writeUInt8(0x7f, 1);
    expect(() => decodeKeyringFrame(badOpcode)).toThrow("Invalid keyring protocol frame");
  });

  it("rejects oversized frames and invalid UTF-8", () => {
    expect(() => encodeKeyringFrame(KeyringOpcode.WRITE_REGISTRY_ATOMIC, Buffer.alloc(32 * 1024 + 1)))
      .toThrow("Invalid keyring protocol frame");
    expect(() => decodeKeyringUtf8(Buffer.from([0xc3, 0x28])))
      .toThrow("Invalid keyring protocol text payload");
  });
});
