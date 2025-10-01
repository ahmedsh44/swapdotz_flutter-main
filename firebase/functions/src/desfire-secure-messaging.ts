/* eslint-disable max-len */
/**
 * DESFire Secure Messaging implementation for server-authoritative operations
 *
 * Implements (DES/3DES sessions):
 * - CRC16-IBM (little-endian) for data/cryptograms
 * - ISO9797-1 M2 padding (0x80 then zeros)
 * - 3DES-CBC MAC (last 8 bytes)
 * - 3DES-CBC enciphered payloads (IV=0, no extra MAC)
 * - ChangeKey and WriteData APDU builders with proper framing
 *
 * Note: AES sessions require CRC32 and AES-CMAC (not implemented here).
 */

import * as crypto from 'crypto';

// DESFire command codes
export const CMD_WRITE_DATA = 0x3D;
export const CMD_CHANGE_KEY = 0xC4;
export const CMD_COMMIT_TRANSACTION = 0xC7;
export const CMD_ABORT_TRANSACTION = 0xA7;

// Communication modes
export enum CommMode {
  PLAIN = 0x00,
  MACED = 0x01,
  ENCIPHERED = 0x03,
}

/**
 * CRC16-IBM (reflected) for DES/3DES sessions, little-endian output.
 */
export function calculateCRC16(data: Buffer): Buffer {
  let crc = 0xFFFF;
  for (let i = 0; i < data.length; i++) {
    crc ^= data[i];
    for (let j = 0; j < 8; j++) {
      const lsb = crc & 1;
      crc >>>= 1;
      if (lsb) crc ^= 0xA001;
    }
  }
  const out = Buffer.allocUnsafe(2);
  out.writeUInt16LE(crc & 0xFFFF, 0);
  return out;
}

/**
 * CRC32 (reflected, poly 0xEDB88320) for AES sessions (not used in DES/3DES).
 */
export function calculateCRC32(data: Buffer): Buffer {
  const polynomial = 0xEDB88320;
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < data.length; i++) {
    crc ^= data[i];
    for (let j = 0; j < 8; j++) {
      crc = (crc & 1) ? (crc >>> 1) ^ polynomial : (crc >>> 1);
    }
  }
  crc = ~crc >>> 0;
  const result = Buffer.allocUnsafe(4);
  result.writeUInt32LE(crc, 0);
  return result;
}

/**
 * Enforce odd parity per DES spec (LSB is parity bit per byte).
 * Safe: DES ignores parity in key schedule; card and host remain consistent.
 */
function enforceOddParity(key: Buffer): Buffer {
  const adjusted = Buffer.from(key);
  for (let i = 0; i < adjusted.length; i++) {
    let byte = adjusted[i];
    let ones = 0;
    for (let bit = 1; bit < 8; bit++) if (byte & (1 << bit)) ones++;
    // Set LSB (parity) so total ones is odd
    if (ones % 2 === 0) byte |= 0x01; else byte &= 0xFE;
    adjusted[i] = byte;
  }
  return adjusted;
}

/**
 * Prepare a DES/3DES key for OpenSSL:
 * - 24 bytes: use as-is (K1||K2||K1 or K1||K2||K3) → cipher 'des-ede3-cbc'
 * - 16 bytes: use as-is (K1||K2)                   → cipher 'des-ede-cbc'
 * - 8 bytes : duplicate to 16 (K||K)               → cipher 'des-ede-cbc'
 * Always enforce odd parity; NEVER XOR/mutate data bits.
 */
export function get3DESCipherParams(rawKey: Buffer): { alg: 'des-ede-cbc' | 'des-ede3-cbc'; key: Buffer } {
  if (!Buffer.isBuffer(rawKey)) throw new Error(`Key is not a Buffer: ${typeof rawKey}`);

  if (rawKey.length === 24) {
    return { alg: 'des-ede3-cbc', key: enforceOddParity(rawKey) };
  }
  if (rawKey.length === 16) {
    return { alg: 'des-ede-cbc', key: enforceOddParity(rawKey) };
  }
  if (rawKey.length === 8) {
    const k16 = Buffer.concat([rawKey, rawKey]); // K||K
    return { alg: 'des-ede-cbc', key: enforceOddParity(k16) };
  }
  throw new Error(`Invalid DES/3DES key length: ${rawKey.length}`);
}

/**
 * ISO9797-1 Method 2 padding (0x80 then zeros) to blockSize.
 */
export function applyPadding(data: Buffer, blockSize: number): Buffer {
  const padLength = blockSize - ((data.length + 1) % blockSize);
  const padding = Buffer.alloc(padLength + 1);
  padding[0] = 0x80;
  return Buffer.concat([data, padding]);
}

/**
 * Remove ISO9797-1 M2 padding.
 */
export function removePadding(data: Buffer): Buffer {
  let i = data.length - 1;
  while (i >= 0 && data[i] === 0x00) i--;
  if (i >= 0 && data[i] === 0x80) return data.subarray(0, i);
  return data;
}

/**
 * AES-CMAC placeholder – not used for DES/3DES sessions.
 */
export function calculateCMAC(_key: Buffer, _data: Buffer): Buffer {
  throw new Error('AES-CMAC not implemented here. Use a proper CMAC lib for AES sessions.');
}

/**
 * 3DES CBC-MAC (DES/3DES sessions): MAC = last 8 bytes of 3DES-CBC over padded data.
 * IV = 0x00..00, NoPadding at cipher level (we pad manually).
 *
 * If OpenSSL rejects a weak DES block, we throw with code 'WEAK_DES_BLOCK' – caller should re-auth.
 */
export function calculate3DESMAC(rawKey: Buffer, data: Buffer): Buffer {
  const { alg, key } = get3DESCipherParams(rawKey);
  const padded = applyPadding(data, 8);
  const iv = Buffer.alloc(8, 0);
  try {
    const cipher = crypto.createCipheriv(alg, key, iv);
    cipher.setAutoPadding(false);
    const enc = Buffer.concat([cipher.update(padded), cipher.final()]);
    return enc.subarray(enc.length - 8);
  } catch (e: any) {
    e.code = e.code ?? 'WEAK_DES_BLOCK';
    e.hint = 'OpenSSL rejected this DES key (weak or policy). Re-auth to derive a new session key, then retry.';
    throw e;
  }
}

// Frame size constants for WriteData
const MAX_FIRST_WRITE = 55 - 7; // first frame body minus (fileNo+offset(3)+len(3)) = 7
const MAX_NEXT = 59;

/**
 * Build WriteData command frames (CMD 0x3D) with proper APDU chaining.
 * - PLAIN: raw data
 * - MACED: append CRC16 to data; MAC over cmd||fileNo||offset||len||data||crc
 * - ENCIPHERED: encrypt (data||CRC16||pad) with 3DES-CBC IV=0, no separate MAC
 * 
 * Returns an array of APDU frames (first frame + continuation frames if needed)
 */
export function buildWriteDataFrames(
  fileNo: number,
  offset: number,
  data: Buffer,
  sessionKey: Buffer,
  commMode: CommMode,
  _cmdCounter: number // not used for 3DES
): Buffer[] {
  const cmd = CMD_WRITE_DATA;
  const offsetBytes = Buffer.allocUnsafe(3); offsetBytes.writeUIntLE(offset, 0, 3);
  const lengthBytes = Buffer.allocUnsafe(3); lengthBytes.writeUIntLE(data.length, 0, 3);

  // Build the payload according to the mode
  let payload: Buffer; // what will be split across frames (after the 7 param bytes)
  
  if (commMode === CommMode.PLAIN) {
    payload = data;
  } else if (commMode === CommMode.MACED) {
    // CRC16 over cmd+params+data
    const crcBase = Buffer.concat([Buffer.from([cmd, fileNo]), offsetBytes, lengthBytes, data]);
    const crc16 = calculateCRC16(crcBase);
    const dataWithCRC = Buffer.concat([data, crc16]);

    // MAC over cmd||fileNo||offset||len||dataWithCRC
    const macInput = Buffer.concat([
      Buffer.from([cmd]), Buffer.from([fileNo]),
      offsetBytes, lengthBytes, dataWithCRC,
    ]);
    const mac = calculate3DESMAC(sessionKey, macInput);

    // The framed message body is dataWithCRC followed by MAC (MAC always at the end)
    payload = Buffer.concat([dataWithCRC, mac]);
  } else {
    // ENCIPHERED: encrypt (data||CRC16||pad) with 3DES-CBC IV=0
    const crcBase = Buffer.concat([Buffer.from([cmd, fileNo]), offsetBytes, lengthBytes, data]);
    const crc16 = calculateCRC16(crcBase);
    const plaintext = applyPadding(Buffer.concat([data, crc16]), 8);

    const { alg, key } = get3DESCipherParams(sessionKey);
    const iv = Buffer.alloc(8, 0);
    
    try {
      const cipher = crypto.createCipheriv(alg, key, iv);
      cipher.setAutoPadding(false);
      payload = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    } catch (e: any) {
      e.code = e.code ?? 'WEAK_DES_BLOCK';
      e.hint = 'OpenSSL rejected this DES key (weak or policy). Re-auth to derive a new session key, then retry.';
      throw e;
    }
  }

  // Now frame: first frame includes params + first slice of payload
  const frames: Buffer[] = [];
  const firstSlice = payload.subarray(0, Math.min(payload.length, MAX_FIRST_WRITE));
  
  frames.push(Buffer.concat([
    Buffer.from([0x90, cmd, 0x00, 0x00]),
    Buffer.from([7 + firstSlice.length]),    // Lc
    Buffer.from([fileNo]), offsetBytes, lengthBytes,
    firstSlice,
    Buffer.from([0x00]),                     // Le
  ]));

  // Continuation frames over the remaining payload
  let off = firstSlice.length;
  while (off < payload.length) {
    const chunk = payload.subarray(off, Math.min(off + MAX_NEXT, payload.length));
    frames.push(Buffer.concat([
      Buffer.from([0x90, 0xAF, 0x00, 0x00]),
      Buffer.from([chunk.length]),
      chunk,
      Buffer.from([0x00]),
    ]));
    off += chunk.length;
  }

  return frames;
}

// Keep the old name as an alias for backward compatibility
export const buildWriteDataCommand = buildWriteDataFrames;

/**
 * Build ChangeKey (CMD 0xC4) for DES/3DES keys.
 * - CRC16 over new key
 * - XOR newKey with oldKey (24b or 16b normalized consistently)
 * - Append CRC16 and keyVersion
 * - Pad and encrypt with 3DES-CBC IV=0
 * - Frame across 0xC4 first frame + 0xAF continuation frames
 */
export function buildChangeKeyCommand(
  keyNo: number,
  oldKey: Buffer,
  newKey: Buffer,
  sessionKey: Buffer,
  keyVersion: number = 0
): Buffer[] {
  // For XOR we need both keys the same length. DESFire supports 2-key or 3-key.
  // Keep original widths (16 or 24) if provided; if 8, upgrade to 16 (K||K).
  const normKey = (k: Buffer): Buffer => {
    if (k.length === 24) return enforceOddParity(k);
    if (k.length === 16) return enforceOddParity(k);
    if (k.length === 8)  return enforceOddParity(Buffer.concat([k, k]));
    throw new Error(`Invalid key length for ChangeKey: ${k.length}`);
  };

  const oldK = normKey(oldKey);
  const newK = normKey(newKey);

  // CRC16 over *new key* (use the exact width you are changing to)
  const newKeyCRC16 = calculateCRC16(newK);

  // XORed key (same-key-number change; master or app keys alike)
  if (oldK.length !== newK.length) {
    throw new Error(`Old/New key length mismatch (old=${oldK.length}, new=${newK.length})`);
  }
  const xored = Buffer.alloc(oldK.length);
  for (let i = 0; i < oldK.length; i++) xored[i] = newK[i] ^ oldK[i];

  const cryptogram = Buffer.concat([xored, newKeyCRC16, Buffer.from([keyVersion])]);
  const padded = applyPadding(cryptogram, 8);

  const { alg, key } = get3DESCipherParams(sessionKey);
  const iv = Buffer.alloc(8, 0);

  let enc: Buffer;
  try {
    const cipher = crypto.createCipheriv(alg, key, iv);
    cipher.setAutoPadding(false);
    enc = Buffer.concat([cipher.update(padded), cipher.final()]);
  } catch (e: any) {
    e.code = e.code ?? 'WEAK_DES_BLOCK';
    e.hint = 'OpenSSL rejected this DES key (weak or policy). Re-auth to derive a new session key, then retry.';
    throw e;
  }

  // Frame split (short APDU): first frame can carry ~55 bytes minus keyNo byte.
  const frames: Buffer[] = [];
  const MAX_FIRST = 55 - 1; // minus keyNo
  const MAX_NEXT  = 59;

  const firstChunk = enc.subarray(0, Math.min(enc.length, MAX_FIRST));
  frames.push(Buffer.concat([
    Buffer.from([0x90, CMD_CHANGE_KEY, 0x00, 0x00]),
    Buffer.from([1 + firstChunk.length]),
    Buffer.from([keyNo]),
    firstChunk,
    Buffer.from([0x00]),
  ]));

  let off = firstChunk.length;
  while (off < enc.length) {
    const chunk = enc.subarray(off, Math.min(off + MAX_NEXT, enc.length));
    frames.push(Buffer.concat([
      Buffer.from([0x90, 0xAF, 0x00, 0x00]),
      Buffer.from([chunk.length]),
      chunk,
      Buffer.from([0x00]),
    ]));
    off += chunk.length;
  }
  return frames;
}

/**
 * Helper to build a MACed WriteData of your JSON transfer blob into file 0x01.
 * Returns an array of APDU frames to send sequentially.
 */
export function buildSecureTransferWrite(
  sessionId: string,
  challenge: string,
  timestamp: number,
  sessionKey: Buffer,
  commMode: CommMode = CommMode.MACED
): Buffer[] {
  // Check if challenge is hex string (64 chars) or raw data
  let payload: Buffer;
  if (challenge.length === 64 && /^[0-9a-fA-F]+$/.test(challenge)) {
    // Hex string - convert to raw bytes (32 bytes)
    payload = Buffer.from(challenge, 'hex');
    console.log('[buildSecureTransferWrite] Converting hex string to', payload.length, 'raw bytes');
  } else {
    // Assume it's already a string to write as-is
    payload = Buffer.from(challenge, 'utf8');
    console.log('[buildSecureTransferWrite] Using string as-is:', payload.length, 'bytes');
  }
  
  // Write to file 01 in application 000001 with PLAIN mode
  // (matching what desfire.dart does)
  return buildWriteDataFrames(0x01, 0x00, payload, sessionKey, CommMode.PLAIN, 0);
}

/**
 * Parse trailing 0x91xx from a card response.
 */
export function parseWriteDataResponse(response: Buffer): { success: boolean; error?: string } {
  if (response.length < 2) return { success: false, error: 'Response too short' };
  const sw1 = response[response.length - 2];
  const sw2 = response[response.length - 1];

  if (sw1 === 0x91 && sw2 === 0x00) return { success: true };
  if (sw1 === 0x91 && sw2 === 0x7E) return { success: false, error: 'Length error' };
  if (sw1 === 0x91 && sw2 === 0x9D) return { success: false, error: 'Permission denied' };
  if (sw1 === 0x91 && sw2 === 0xBD) return { success: false, error: 'File not found' };

  return { success: false, error: `Unknown status: ${sw1.toString(16)}${sw2.toString(16)}` };
}
 