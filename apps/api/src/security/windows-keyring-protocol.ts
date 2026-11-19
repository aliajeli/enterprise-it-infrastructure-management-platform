const PROTOCOL_VERSION = 1;
const HEADER_BYTES = 6;
const MAX_PAYLOAD_BYTES = 32 * 1024;

export const KeyringOpcode = {
  BEGIN_TRANSACTION: 0x01,
  READ_REGISTRY: 0x02,
  WRITE_REGISTRY_ATOMIC: 0x03,
  END_TRANSACTION: 0x04,
  BEGIN_OK: 0x81,
  READ_RESULT: 0x82,
  WRITE_OK: 0x83,
  END_OK: 0x84,
  ERROR: 0xff,
} as const;

export type KeyringOpcodeValue = (typeof KeyringOpcode)[keyof typeof KeyringOpcode];

const VALID_OPCODES = new Set<number>(Object.values(KeyringOpcode));

export interface KeyringFrame {
  version: 1;
  opcode: KeyringOpcodeValue;
  payload: Buffer;
}

/**
 * Version 1 frame: uint8 version, uint8 opcode, uint32-be payload length,
 * followed by exactly payload-length bytes. Paths are never part of a frame.
 */
export function encodeKeyringFrame(opcode: KeyringOpcodeValue, payload: Buffer = Buffer.alloc(0)): Buffer {
  if (!VALID_OPCODES.has(opcode) || !Buffer.isBuffer(payload) || payload.length > MAX_PAYLOAD_BYTES) {
    throw new Error("Invalid keyring protocol frame.");
  }
  const frame = Buffer.allocUnsafe(HEADER_BYTES + payload.length);
  frame.writeUInt8(PROTOCOL_VERSION, 0);
  frame.writeUInt8(opcode, 1);
  frame.writeUInt32BE(payload.length, 2);
  payload.copy(frame, HEADER_BYTES);
  return frame;
}

export function decodeKeyringFrame(frame: Buffer): KeyringFrame {
  if (!Buffer.isBuffer(frame) || frame.length < HEADER_BYTES || frame.length > HEADER_BYTES + MAX_PAYLOAD_BYTES) {
    throw new Error("Invalid keyring protocol frame.");
  }
  const version = frame.readUInt8(0);
  const opcode = frame.readUInt8(1);
  const payloadLength = frame.readUInt32BE(2);
  if (
    version !== PROTOCOL_VERSION ||
    !VALID_OPCODES.has(opcode) ||
    payloadLength > MAX_PAYLOAD_BYTES ||
    frame.length !== HEADER_BYTES + payloadLength
  ) {
    throw new Error("Invalid keyring protocol frame.");
  }
  return {
    version: 1,
    opcode: opcode as KeyringOpcodeValue,
    payload: Buffer.from(frame.subarray(HEADER_BYTES)),
  };
}

export function decodeKeyringUtf8(payload: Buffer): string {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(payload);
  } catch {
    throw new Error("Invalid keyring protocol text payload.");
  }
}
