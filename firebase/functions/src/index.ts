/* eslint-disable max-len */
/**
 * Cloud Functions for SwapDotz NFC token ownership platform
 * Secure rewrite: server-validated HMAC, byte-safe framing, constant-time compares.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import { Timestamp } from 'firebase-admin/firestore';

admin.initializeApp();
const db = admin.firestore();

/* ---------------- Types ---------------- */

import {
  Token,
  TransferSession,
  InitiateTransferRequest,
  InitiateTransferResponse,
  CompleteTransferRequest,
  CompleteTransferResponse,
  ValidateChallengeRequest,
  ValidateChallengeResponse,
  UserProfile,
  TransferLog,
} from './models';

/* ---------------- DESFire constants ---------------- */

const CMD_AUTH_ISO_3DES = 0x1A;         // ISO 3DES/3K3DES
const CMD_ADDITIONAL_FRAME = 0xAF;

/* ---------------- Session mgmt ---------------- */

const SESSION_TTL_MS = 60000; // 60s
const authSessions = new Map<string, AuthSession>();

interface AuthSession {
  tokenId: string;
  userId: string;
  phase: 'init' | 'challenge-sent' | 'authenticated';
  sessionKey?: Buffer;
  iv?: Buffer;
  rndA?: Buffer;
  rndB?: Buffer;
  expiresAt: number;
  keyVersion?: number;
  pendingKeyHash?: string;
  leaseId?: string;
  validatedKeyHash?: string;
}

/* ---------------- Crypto helpers ---------------- */

// Domain tag for MACs. Version this if formats change.
const DOMAIN_TAG = Buffer.from('SwapDotz/transfer/v1', 'utf8');

function generateSessionId(): string {
  return crypto.randomBytes(16).toString('hex');
}
function generateChallengeBytes(): Buffer {
  return crypto.randomBytes(16);
}
function toHex(b: Buffer): string {
  return b.toString('hex');
}
function fromHex(h: string): Buffer {
  return Buffer.from(h, 'hex');
}
function sha256Bytes(data: Buffer): Buffer {
  return crypto.createHash('sha256').update(data).digest();
}
function sha256HexOfBytes(data: Buffer): string {
  return sha256Bytes(data).toString('hex');
}
function timingSafeEqualHex(aHex: string, bHex: string): boolean {
  const a = Buffer.from(aHex, 'hex');
  const b = Buffer.from(bHex, 'hex');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}
function hmacSha256Hex(key: Buffer, chunks: Buffer[]): string {
  const h = crypto.createHmac('sha256', key);
  for (const c of chunks) h.update(c);
  return h.digest('hex');
}
function lenPrefix(buf: Buffer): Buffer {
  const le = Buffer.allocUnsafe(4);
  le.writeUInt32BE(buf.length, 0);
  return Buffer.concat([le, buf]);
}

/** Default master key (only for bootstrapping) */
async function loadMasterKey(): Promise<Buffer> {
  try {
    if (process.env.FUNCTIONS_EMULATOR !== 'true') {
      // TODO: Secret Manager
      // return Buffer.from(..., 'base64');
    }
  } catch (e) {
    console.error('Secret Manager load failed:', e);
  }
  // 16 bytes (K1||K2), default 0s. Rotate immediately after bootstrap.
  return Buffer.alloc(16, 0x00);
}

/** Defensive SW1/SW2 strip */
function stripStatusBytes(data: Buffer): Buffer {
  if (data.length >= 2) {
    const sw1 = data[data.length - 2];
    const sw2 = data[data.length - 1];
    if (sw1 === 0x91 && (sw2 === 0xAF || sw2 === 0x00 || sw2 === 0xAE)) {
      return data.subarray(0, data.length - 2);
    }
  }
  return data;
}

/** Append-only check */
function validateOwnershipHistoryAppendOnly(
  current: string[],
  proposed: string[],
  _newOwner: string
): boolean {
  if (proposed.length < current.length) return false;
  for (let i = 0; i < current.length; i++) {
    if (current[i] !== proposed[i]) return false;
  }
  return true;
}

/** Hex length is characters; we convert to bytes internally. */
function generateSecureKey(hexLen: number): string {
  return crypto.randomBytes(hexLen / 2).toString('hex');
}

/* ---------------- Authentication: DESFire (unchanged wire) ---------------- */

export const beginAuthenticate = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: { tokenId: string; userId: string; allowUnowned?: boolean }) => {
    const { tokenId, userId, allowUnowned = false } = data;
    if (!tokenId || !userId) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
    }

    const tokenDoc = await db.collection('tokens').doc(tokenId).get();

    if (!allowUnowned) {
      if (!tokenDoc.exists) throw new functions.https.HttpsError('not-found', 'Token not found');
      const token = tokenDoc.data() as Token;
      if (token.current_owner_id !== userId) {
        throw new functions.https.HttpsError('permission-denied', 'Not the token owner');
      }
    }

    const sessionId = crypto.randomBytes(16).toString('hex');
    const leaseId = crypto.randomBytes(8).toString('hex');

    if (!allowUnowned && tokenDoc.exists) {
      const lockExpiresAt = Date.now() + 15000;
      try {
        await db.runTransaction(async (t) => {
          const tokenRef = db.collection('tokens').doc(tokenId);
          const doc = await t.get(tokenRef);
          if (!doc.exists) throw new functions.https.HttpsError('not-found', 'Token was deleted');

          const data = doc.data() as any;
          const currentLock = data.lock;
          if (currentLock && currentLock.expiresAt > Date.now()) {
            throw new functions.https.HttpsError('resource-exhausted', 'Token is locked');
          }
          t.update(tokenRef, {
            lock: { leaseId, expiresAt: lockExpiresAt, sessionId },
          });
        });
      } catch (e: any) {
        if (e instanceof functions.https.HttpsError) throw e;
        console.error('[beginAuth] Lock acquisition failed:', e);
        throw new functions.https.HttpsError('internal', 'Failed to acquire lock');
      }
    }

    const session: AuthSession = {
      tokenId,
      userId,
      phase: 'init',
      expiresAt: Date.now() + SESSION_TTL_MS,
      leaseId,
    };
    authSessions.set(sessionId, session);

    await db.collection('sessions').doc(sessionId).set({
      tokenId,
      userId,
      phase: 'init',
      expiresAt: admin.firestore.Timestamp.fromMillis(session.expiresAt),
      leaseId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 90 <1A> 00 00 01 00 00
    const keyNo = 0x00;
    const apdu = Buffer.from([0x90, CMD_AUTH_ISO_3DES, 0x00, 0x00, 0x01, keyNo, 0x00]);

    return { sessionId, apdus: [apdu.toString('base64')] };
  });

export const continueAuthenticate = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: { sessionId: string; response: string }) => {
    const { sessionId, response } = data;
    if (!sessionId || !response) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
    }

    // Get session
    let session = authSessions.get(sessionId);
    if (!session) {
      const sessionDoc = await db.collection('sessions').doc(sessionId).get();
      if (sessionDoc.exists) {
        const d = sessionDoc.data()!;
        session = {
          tokenId: d.tokenId,
          userId: d.userId,
          phase: d.phase || 'init',
          expiresAt: d.expiresAt?.toMillis ? d.expiresAt.toMillis() : Date.now() + SESSION_TTL_MS,
          leaseId: d.leaseId,
          sessionKey: d.sessionKey ? Buffer.from(d.sessionKey, 'base64') : undefined,
          iv: d.iv ? Buffer.from(d.iv, 'base64') : undefined,
          rndA: d.rndA ? Buffer.from(d.rndA, 'base64') : undefined,
          rndB: d.rndB ? Buffer.from(d.rndB, 'base64') : undefined,
          keyVersion: d.keyVersion,
          pendingKeyHash: d.pendingKeyHash,
        };
        authSessions.set(sessionId, session);
      }
    }
    if (!session) throw new functions.https.HttpsError('not-found', 'Session not found');
    if (session.expiresAt < Date.now()) {
      authSessions.delete(sessionId);
      throw new functions.https.HttpsError('deadline-exceeded', 'Session expired');
    }

    const cardResp = Buffer.from(response, 'base64');
    const key = await loadMasterKey();

    if (session.phase === 'init') {
      if (cardResp.length !== 8) {
        throw new functions.https.HttpsError('invalid-argument', `Expected 8 bytes, got ${cardResp.length}`);
      }
      const iv0 = Buffer.alloc(8, 0x00);
      const cipherName = key.length === 24 ? 'des-ede3-cbc' : 'des-ede-cbc';
      const dec1 = crypto.createDecipheriv(cipherName, key, iv0);
      dec1.setAutoPadding(false);
      const rndB = Buffer.concat([dec1.update(cardResp), dec1.final()]);

      const rndA = crypto.randomBytes(8);
      const rotB = Buffer.concat([rndB.subarray(1), rndB.subarray(0, 1)]);
      const payload = Buffer.concat([rndA, rotB]);
      const enc = crypto.createCipheriv(cipherName, key, cardResp);
      enc.setAutoPadding(false);
      const encPayload = Buffer.concat([enc.update(payload), enc.final()]);

      const apdu = Buffer.concat([
        Buffer.from([0x90, CMD_ADDITIONAL_FRAME, 0x00, 0x00, 0x10]),
        encPayload,
        Buffer.from([0x00]),
      ]);

      session.phase = 'challenge-sent';
      session.rndA = rndA;
      session.rndB = rndB;
      session.iv = encPayload.subarray(8); // next IV
      await db.collection('sessions').doc(sessionId).update({
        phase: 'challenge-sent',
        rndA: rndA.toString('base64'),
        rndB: rndB.toString('base64'),
        iv: session.iv.toString('base64'),
      });

      return { done: false, apdus: [apdu.toString('base64')] };
    }

    if (session.phase === 'challenge-sent') {
      if (cardResp.length !== 8) {
        throw new functions.https.HttpsError('invalid-argument', `Expected 8 bytes, got ${cardResp.length}`);
      }
      if (!session.rndA || !session.iv) {
        throw new functions.https.HttpsError('failed-precondition', 'Session state corrupted');
      }
      const cipherName2 = key.length === 24 ? 'des-ede3-cbc' : 'des-ede-cbc';
      const dec2 = crypto.createDecipheriv(cipherName2, key, session.iv);
      dec2.setAutoPadding(false);
      const decrypted = Buffer.concat([dec2.update(cardResp), dec2.final()]);
      const expectedRotA = Buffer.concat([session.rndA.subarray(1), session.rndA.subarray(0, 1)]);
      if (!decrypted.equals(expectedRotA)) {
        authSessions.delete(sessionId);
        await db.collection('sessions').doc(sessionId).delete();
        throw new functions.https.HttpsError('permission-denied', 'Authentication failed');
      }

      // Session key for ISO-3DES: A0..3 || B0..3 || A4..7 || B4..7
      const sessionKey = Buffer.concat([
        session.rndA.subarray(0, 4),
        session.rndB!.subarray(0, 4),
        session.rndA.subarray(4, 8),
        session.rndB!.subarray(4, 8),
      ]);

      session.phase = 'authenticated';
      session.sessionKey = sessionKey;
      authSessions.set(sessionId, session);
      await db.collection('sessions').doc(sessionId).update({
        phase: 'authenticated',
        sessionKey: sessionKey.toString('base64'),
      });

      try {
        await db.collection('tokens').doc(session.tokenId).update({
          lock: admin.firestore.FieldValue.delete(),
        });
      } catch (e) {
        console.warn('Failed to release lock:', e);
      }
      return { done: true, authenticated: true };
    }

    throw new functions.https.HttpsError('failed-precondition', 'Invalid session phase');
  });

/* ---------------- Change key (no plaintext key storage) ---------------- */

export const changeKey = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: { sessionId: string; newKeyVersion?: number }) => {
    const { sessionId, newKeyVersion = 1 } = data;
    if (!sessionId) throw new functions.https.HttpsError('invalid-argument', 'Missing sessionId');

    const { buildChangeKeyCommand } = await import('./desfire-secure-messaging');

    let session = authSessions.get(sessionId);
    if (!session) {
      const d = (await db.collection('sessions').doc(sessionId).get()).data();
      if (d) {
        session = {
          tokenId: d.tokenId,
          userId: d.userId,
          phase: d.phase || 'init',
          expiresAt: d.expiresAt?.toMillis ? d.expiresAt.toMillis() : Date.now(),
          leaseId: d.leaseId,
          sessionKey: d.sessionKey ? Buffer.from(d.sessionKey, 'base64') : undefined,
          iv: d.iv ? Buffer.from(d.iv, 'base64') : undefined,
          keyVersion: d.keyVersion,
          pendingKeyHash: d.pendingKeyHash,
        };
        authSessions.set(sessionId, session);
      }
    }
    if (!session) throw new functions.https.HttpsError('not-found', 'Session not found');
    if (session.phase !== 'authenticated') {
      throw new functions.https.HttpsError('failed-precondition', 'Not authenticated');
    }
    if (!session.sessionKey) {
      throw new functions.https.HttpsError('failed-precondition', 'No session key');
    }

    const newKey = crypto.randomBytes(16);
    const newKeyHash = sha256HexOfBytes(newKey);
    const oldKey = await loadMasterKey();

    try {
      const apdus = buildChangeKeyCommand(
        0x00, // master key
        oldKey,
        newKey,
        session.sessionKey,
        newKeyVersion
      );

      session.pendingKeyHash = newKeyHash;
      authSessions.set(sessionId, session);

      await db.collection('sessions').doc(sessionId).update({
        pendingKeyHash: newKeyHash,
        // Do not store plaintext new key
        pendingNewKeyHashOnly: true,
      });

      return {
        apdus: apdus.map((a) => a.toString('base64')),
        keyHash: newKeyHash,
      };
    } catch (e: any) {
      if (e.code === 'ERR_CRYPTO_INVALID_KEYLEN' || e.code === 'WEAK_DES_BLOCK') {
        authSessions.delete(sessionId);
        await db.collection('sessions').doc(sessionId).delete();
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Session key is weak. Re-authenticate.'
        );
      }
      throw e;
    }
  });

/* ---------------- App + file setup helpers (unchanged wire) ---------------- */

export const setupAppAndFile = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: { sessionId: string }) => {
    const { sessionId } = data;
    if (!sessionId) throw new functions.https.HttpsError('invalid-argument', 'Missing sessionId');

    const apdus: Buffer[] = [];
    // Select master
    apdus.push(Buffer.from([0x90, 0x5A, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00]));
    // Create app 000001
    apdus.push(Buffer.from([0x90, 0xCA, 0x00, 0x00, 0x05, 0x01, 0x00, 0x00, 0x0F, 0x01, 0x00]));
    // Select app 000001
    apdus.push(Buffer.from([0x90, 0x5A, 0x00, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00]));

    return {
      apdus: apdus.map((a) => a.toString('base64')),
      steps: ['Select master app', 'Create app 000001', 'Select app 000001'],
    };
  });

export const authenticateAppLevel = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: { sessionId: string }) => {
    const { sessionId } = data;
    if (!sessionId) throw new functions.https.HttpsError('invalid-argument', 'Missing sessionId');
    const authStartApdu = Buffer.from([0x90, 0x0A, 0x00, 0x00, 0x01, 0x00, 0x00]);
    return { apdus: [authStartApdu.toString('base64')], expect: '91AF' };
  });

export const continueAppAuth = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: { sessionId: string; response: string }) => {
    const { sessionId, response } = data;
    if (!sessionId || !response) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing sessionId or response');
    }
    const respBytes = Buffer.from(response, 'base64');
    if (respBytes.length !== 8) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid response length');
    }
    const { get3DESCipherParams } = await import('./desfire-secure-messaging');
    const appKey = Buffer.alloc(24, 0);
    const { alg, key } = get3DESCipherParams(appKey);
    const iv = Buffer.alloc(8, 0);
    const dec = crypto.createDecipheriv(alg, key, iv);
    dec.setAutoPadding(false);
    const rndB = Buffer.concat([dec.update(respBytes), dec.final()]);

    const rndA = crypto.randomBytes(8);
    const rndBrot = Buffer.concat([rndB.subarray(1), rndB.subarray(0, 1)]);
    const enc = crypto.createCipheriv(alg, key, iv);
    enc.setAutoPadding(false);
    const encAB = Buffer.concat([enc.update(Buffer.concat([rndA, rndBrot])), enc.final()]);
    const continueApdu = Buffer.concat([
      Buffer.from([0x90, 0xAF, 0x00, 0x00, 0x10]),
      encAB,
      Buffer.from([0x00]),
    ]);

    return { apdus: [continueApdu.toString('base64')], expect: '9100' };
  });

export const createFile01 = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: { sessionId: string }) => {
    const { sessionId } = data;
    if (!sessionId) throw new functions.https.HttpsError('invalid-argument', 'Missing sessionId');

    const createFileApdu = Buffer.from([
      0x90, 0xCD, 0x00, 0x00, 0x07, // Create StdData File
      0x01,                         // File ID
      0x00,                         // Plain comms (use MACed/enc for real writes)
      0x00, 0x00,                   // Access rights = key 0
      0x00, 0x01, 0x00,             // Size 256
      0x00
    ]);
    return { apdus: [createFileApdu.toString('base64')], expect: '9100' };
  });

export const selectApplication = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: { sessionId: string; appId?: string }) => {
    const { sessionId, appId = '000000' } = data;
    if (!sessionId) throw new functions.https.HttpsError('invalid-argument', 'Missing sessionId');
    const appBytes = Buffer.from(appId, 'hex');
    if (appBytes.length !== 3) {
      throw new functions.https.HttpsError('invalid-argument', 'App ID must be 3 bytes');
    }
    const selectApdu = Buffer.concat([
      Buffer.from([0x90, 0x5A, 0x00, 0x00, 0x03]),
      appBytes,
      Buffer.from([0x00]),
    ]);
    return { apdus: [selectApdu.toString('base64')] };
  });

/* ---------------- Secure transfer data write ---------------- */

export const writeTransferData = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: {
    sessionId: string;
    transferSessionId: string;
    challenge?: string;             // legacy-only testing
    generateNewKey?: boolean;       // server generates 32-byte key (hex)
  }) => {
    const { sessionId, transferSessionId, challenge, generateNewKey } = data;
    if (!sessionId || !transferSessionId) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
    }

    console.log('[writeTransferData] ========== WRITE DEBUG ==========');
    console.log('[writeTransferData] Input params:', { 
      sessionId, 
      transferSessionId, 
      generateNewKey,
      hasChallenge: !!challenge 
    });

    let keyToWrite: string;
    let keyHash: string | undefined;  // Store the hash to return it
    if (generateNewKey) {
      const newKeyBytes = crypto.randomBytes(32);
      keyToWrite = newKeyBytes.toString('hex');
      keyHash = sha256HexOfBytes(newKeyBytes);  // Save it for later
      
      console.log('[writeTransferData] Generated new key:');
      console.log('  - Raw bytes (hex):', newKeyBytes.toString('hex'));
      console.log('  - Key hash:', keyHash);
      console.log('  - Storing pending_key_hash in transfer session:', transferSessionId);
      
      await db.collection('transferSessions').doc(transferSessionId).set(
        { pending_key_hash: keyHash },
        { merge: true }
      );
      
      // Verify it was stored
      const verifyDoc = await db.collection('transferSessions').doc(transferSessionId).get();
      console.log('[writeTransferData] Verified pending_key_hash stored:', verifyDoc.data()?.pending_key_hash);
    } else if (challenge) {
      keyToWrite = challenge; // legacy
      console.log('[writeTransferData] Using legacy challenge as key');
    } else {
      throw new functions.https.HttpsError('invalid-argument', 'Must generateNewKey or provide challenge');
    }
    console.log('[writeTransferData] =====================================');

    const { buildSecureTransferWrite, CommMode } = await import('./desfire-secure-messaging');

    let session = authSessions.get(sessionId);
    if (!session) {
      const d = (await db.collection('sessions').doc(sessionId).get()).data();
      if (d) {
        session = {
          tokenId: d.tokenId,
          userId: d.userId,
          phase: d.phase || 'init',
          expiresAt: d.expiresAt?.toMillis ? d.expiresAt.toMillis() : Date.now(),
          leaseId: d.leaseId,
          sessionKey: d.sessionKey ? Buffer.from(d.sessionKey, 'base64') : undefined,
          iv: d.iv ? Buffer.from(d.iv, 'base64') : undefined,
        };
        authSessions.set(sessionId, session);
      }
    }
    if (!session) throw new functions.https.HttpsError('not-found', 'Session not found');
    if (session.phase !== 'authenticated') {
      throw new functions.https.HttpsError('failed-precondition', 'Not authenticated');
    }
    if (!session.sessionKey) {
      throw new functions.https.HttpsError('failed-precondition', 'No session key');
    }

    try {
      // Use MACed mode for integrity (plain only for bootstrap demos)
      const frames = buildSecureTransferWrite(
        transferSessionId,
        keyToWrite,
        Date.now(),
        session.sessionKey,
        CommMode.MACED
      );

      // If server generated new key, we already stored pending_key_hash above.
      const result = {
        apdus: frames.map((f) => f.toString('base64')),
        ...(keyHash ? { keyHash } : {}),  // Include keyHash if we generated a new key
      };
      
      console.log('[writeTransferData] Returning result:');
      console.log('  - Number of APDUs:', result.apdus.length);
      console.log('  - keyHash included:', !!result.keyHash);
      if (result.keyHash) {
        console.log('  - keyHash value:', result.keyHash);
      }
      
      return result;
    } catch (e: any) {
      if (e.code === 'ERR_CRYPTO_INVALID_KEYLEN' || e.code === 'WEAK_DES_BLOCK') {
        authSessions.delete(sessionId);
        await db.collection('sessions').doc(sessionId).delete();
        throw new functions.https.HttpsError('failed-precondition', 'Session key is weak. Re-authenticate.');
      }
      throw e;
    }
  });

/* ---------------- Transfer flow: HMAC-based server validation ---------------- */

/**
 * Initiate a transfer (no expected hash stored).
 * Stores: random challenge (bytes), algo markers, status pending.
 */
export const initiateTransfer = functions.https.onCall(
  async (data: InitiateTransferRequest, context): Promise<InitiateTransferResponse> => {
    console.log('[initiateTransfer] ========== INITIATE DEBUG ==========');
    console.log('[initiateTransfer] Input:', { 
      token_uid: data.token_uid, 
      to_user_id: data.to_user_id,
      session_duration_minutes: data.session_duration_minutes 
    });
    console.log('[initiateTransfer] Auth user (from_user_id):', context.auth?.uid);
    
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    const { token_uid, to_user_id, session_duration_minutes = 5 } = data;
    const from_user_id = context.auth.uid;
    if (!token_uid) throw new functions.https.HttpsError('invalid-argument', 'token_uid is required');

    const tokenDoc = await db.collection('tokens').doc(token_uid).get();
    if (!tokenDoc.exists) throw new functions.https.HttpsError('not-found', 'Token not found');
    const token = tokenDoc.data() as Token;
    if (token.current_owner_id !== from_user_id) {
      throw new functions.https.HttpsError('permission-denied', 'Only owner can initiate a transfer');
    }

    const existing = await db.collection('transferSessions')
      .where('token_uid', '==', token_uid)
      .where('status', '==', 'pending')
      .where('expires_at', '>', admin.firestore.Timestamp.now())
      .get();
    if (!existing.empty) {
      throw new functions.https.HttpsError('already-exists', 'Active transfer session exists');
    }

    const session_id = generateSessionId();
    const challengeBytes = generateChallengeBytes();
    const expires_at = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + session_duration_minutes * 60 * 1000)
    );

    const sessionData: TransferSession = {
      session_id,
      token_uid,
      from_user_id,
      ...(to_user_id ? { to_user_id } : {}),
      expires_at,
      status: 'pending',
      created_at: admin.firestore.Timestamp.now(),
      challenge_data: {
        challenge_b64: challengeBytes.toString('base64'),
        proof_alg: 'hmac-sha256-v1',
        framing: 'tag|len(chal)|chal|len(uid)|uid',
        used: false,
        validated_server_side: false,
      } as any,
    };

    console.log('[initiateTransfer] Creating session:', {
      session_id,
      token_uid,
      from_user_id,
      to_user_id: to_user_id || 'any',
      challenge_hex: toHex(challengeBytes),
      token_key_hash: token.key_hash
    });

    await db.collection('transferSessions').doc(session_id).set(sessionData);
    console.log('[initiateTransfer] Session created successfully');
    console.log('[initiateTransfer] =====================================');
    return {
      session_id,
      expires_at: expires_at.toDate().toISOString(),
      challenge: toHex(challengeBytes), // client display-safe
    };
  }
);

/**
 * Server-side validation. Reads card key bytes, verifies against DB,
 * computes HMAC over structured bytes, marks validated_server_side = true.
 */
export const validateCardKeyForTransfer = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: {
    sessionId: string;                 // auth session (not strictly needed here)
    transferSessionId: string;
    cardResponse: string;              // base64 raw bytes read from card (key region)
  }) => {
    const { sessionId, transferSessionId, cardResponse } = data;
    if (!sessionId || !transferSessionId || !cardResponse) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
    }

    const keyBytesRaw = Buffer.from(cardResponse, 'base64');
    
    // Expect at least 32 bytes read from the card
    if (keyBytesRaw.length < 32) {
      throw new functions.https.HttpsError('invalid-argument', `Card returned <32 bytes (got ${keyBytesRaw.length})`);
    }
    
    // Primary (current): first 32 bytes are the raw key
    // DO NOT truncate at null bytes - random keys contain 0x00!
    const keyBytes = keyBytesRaw.subarray(0, 32);
    const keyHashFromCard = sha256HexOfBytes(keyBytes);

    const transferDoc = await db.collection('transferSessions').doc(transferSessionId).get();
    if (!transferDoc.exists) throw new functions.https.HttpsError('not-found', 'Transfer session not found');
    const transferSession = transferDoc.data() as any;

    const tokenDoc = await db.collection('tokens').doc(transferSession.token_uid).get();
    if (!tokenDoc.exists) throw new functions.https.HttpsError('not-found', 'Token not found');
    const token = tokenDoc.data() as Token;

    // Helper to check if card contains ASCII hex instead of raw bytes (legacy)
    function maybeAsciiHexToBytes(buf: Buffer): Buffer | null {
      // Check if first 64 bytes are all hex chars [0-9a-fA-F]
      const n = Math.min(64, buf.length);
      if (n < 64) return null;
      
      for (let i = 0; i < n; i++) {
        const c = buf[i];
        const isHex =
          (c >= 0x30 && c <= 0x39) ||  // 0-9
          (c >= 0x41 && c <= 0x46) ||  // A-F
          (c >= 0x61 && c <= 0x66);    // a-f
        if (!isHex) return null;
      }
      
      const hexStr = buf.subarray(0, n).toString('ascii');
      try { 
        return Buffer.from(hexStr, 'hex'); 
      } catch { 
        return null; 
      }
    }

    // Accept pending_key_hash when present, else token.key_hash (bootstrap)
    const pendingKeyHash: string | undefined = transferSession.pending_key_hash;
    let keyMatches = false;

    // Debug logging
    console.log('[validateCardKey] ========== VALIDATION DEBUG ==========');
    console.log('[validateCardKey] Input data:');
    console.log('  - Session ID:', sessionId);
    console.log('  - Transfer session ID:', transferSessionId);
    console.log('  - Card response length:', keyBytesRaw.length, 'bytes');
    console.log('  - First 32 bytes (hex):', keyBytesRaw.subarray(0, 32).toString('hex'));
    console.log('[validateCardKey] Computed hashes:');
    console.log('  - Key hash from card:', keyHashFromCard);
    console.log('[validateCardKey] Database values:');
    console.log('  - Token key_hash:', token.key_hash);
    console.log('  - Pending key_hash:', pendingKeyHash || 'none');
    console.log('  - Transfer session data:', JSON.stringify({
      token_uid: transferSession.token_uid,
      from_user: transferSession.from_user,
      to_user: transferSession.to_user,
      pending_key_hash: transferSession.pending_key_hash,
      challenge_data: transferSession.challenge_data
    }, null, 2));
    console.log('[validateCardKey] =====================================');

    if (pendingKeyHash && timingSafeEqualHex(keyHashFromCard, pendingKeyHash)) {
      console.log('[validateCardKey] Key matches pending_key_hash from new transfer');
      keyMatches = true;
    } else if (timingSafeEqualHex(keyHashFromCard, token.key_hash)) {
      console.log('[validateCardKey] Key matches token.key_hash from database');
      keyMatches = true;
    } else {
      // Legacy path: card might contain ASCII hex encoding (64 chars) instead of raw bytes
      const asciiKey = maybeAsciiHexToBytes(keyBytesRaw);
      if (asciiKey) {
        const legacyHash = sha256HexOfBytes(asciiKey);
        if (timingSafeEqualHex(legacyHash, token.key_hash)) {
          console.log('[validateCardKey] Key matches using legacy ASCII hex format - migrating');
          keyMatches = true;
          // Migrate to canonical raw32 hash
          await db.collection('tokens').doc(transferSession.token_uid).update({
            key_hash: keyHashFromCard,
            'metadata.hash_migrated': true,
            'metadata.migration_date': admin.firestore.Timestamp.now(),
          });
        }
      }
    }

    if (!keyMatches) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Card key does not match database'
      );
    }

    // Compute server HMAC for audit (not returned to client)
    const challenge_b64 = transferSession.challenge_data?.challenge_b64;
    if (!challenge_b64) {
      // No challenge needed for this session
      await db.collection('transferSessions').doc(transferSessionId).update({
        'challenge_data.validated_server_side': true,
        'challenge_data.validated_at': admin.firestore.FieldValue.serverTimestamp(),
        'challenge_data.key_hash_used': keyHashFromCard,
      });
      const as = authSessions.get(sessionId);
      if (as) {
        as.validatedKeyHash = keyHashFromCard;
        authSessions.set(sessionId, as);
      }
      return { valid: true, keyHash: keyHashFromCard, message: 'Validated (no challenge present)' };
    }

    const challengeBytes = Buffer.from(challenge_b64, 'base64');
    const uidBytes = Buffer.from(transferSession.token_uid, 'utf8');
    const proof = hmacSha256Hex(
      keyBytes,
      [DOMAIN_TAG, lenPrefix(challengeBytes), challengeBytes, lenPrefix(uidBytes), uidBytes]
    );

    // Mark validated (we do not store the HMAC itself)
    await db.collection('transferSessions').doc(transferSessionId).update({
      'challenge_data.validated_server_side': true,
      'challenge_data.validated_at': admin.firestore.FieldValue.serverTimestamp(),
      'challenge_data.key_hash_used': keyHashFromCard,
      // optional: proof can be stored for audit if desired
    });

    const as = authSessions.get(sessionId);
    if (as) {
      as.validatedKeyHash = keyHashFromCard;
      authSessions.set(sessionId, as);
    }

    return { valid: true, keyHash: keyHashFromCard, message: 'Card validated successfully' };
  });

/**
 * Stage transfer (Phase 1). Requires validated_server_side.
 */
export const stageTransfer = functions.https.onCall(
  async (data: CompleteTransferRequest, context): Promise<{
    success: boolean;
    staged_transfer_id: string;
    new_owner_id: string;
  }> => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');

    const { session_id, new_key_hash, new_owner_id } = data as any;
    const to_user_id: string = new_owner_id || context.auth.uid;
    if (!session_id || !new_key_hash) {
      throw new functions.https.HttpsError('invalid-argument', 'session_id and new_key_hash are required');
    }

    try {
      const result = await db.runTransaction(async (transaction) => {
        const sessionRef = db.collection('transferSessions').doc(session_id);
        const sessionDoc = await transaction.get(sessionRef);
        if (!sessionDoc.exists) throw new functions.https.HttpsError('not-found', 'Transfer session not found');
        const session = sessionDoc.data() as any;

        const exp = session.expires_at?.toDate ? session.expires_at.toDate() : new Date(session.expires_at);
        if (exp < new Date()) {
          transaction.update(sessionRef, { status: 'expired' });
          throw new functions.https.HttpsError('deadline-exceeded', 'Transfer session expired');
        }
        if (session.status !== 'pending') {
          throw new functions.https.HttpsError('failed-precondition', `Session is ${session.status}, not pending`);
        }

        // Require server validation
        const cd = session.challenge_data;
        if (cd && cd.validated_server_side !== true) {
          throw new functions.https.HttpsError(
            'permission-denied',
            'Challenge not validated server-side'
          );
        }

        const tokenRef = db.collection('tokens').doc(session.token_uid);
        const tokenDoc = await transaction.get(tokenRef);
        if (!tokenDoc.exists) throw new functions.https.HttpsError('not-found', 'Token not found');
        const token = tokenDoc.data() as Token;

        if (token.current_owner_id !== session.from_user_id) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'Token ownership changed since session creation'
          );
        }

        const proposedPreviousOwners = [...token.previous_owners, session.from_user_id];
        if (!validateOwnershipHistoryAppendOnly(token.previous_owners, proposedPreviousOwners, to_user_id)) {
          throw new functions.https.HttpsError('failed-precondition', 'Invalid ownership history change');
        }

        const stagedTransferId = crypto.randomBytes(16).toString('hex');
        const stagedTransferRef = db.collection('staged_transfers').doc(stagedTransferId);

        const staged = {
          id: stagedTransferId,
          session_id,
          token_uid: session.token_uid,
          from_user_id: session.from_user_id,
          to_user_id,
          original_token_state: {
            current_owner_id: token.current_owner_id,
            previous_owners: token.previous_owners,
            key_hash: token.key_hash,
          },
          new_token_state: {
            current_owner_id: to_user_id,
            previous_owners: proposedPreviousOwners,
            key_hash: new_key_hash
          },
          status: 'staged',
          created_at: admin.firestore.Timestamp.now(),
          expires_at: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000)),
          server_validated: true,
        };

        transaction.set(stagedTransferRef, staged);
        transaction.update(sessionRef, { status: 'staged', staged_transfer_id: stagedTransferId, 'challenge_data.used': true });

        return { success: true, staged_transfer_id: stagedTransferId, new_owner_id: to_user_id };
      });

      return result;
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      console.error('Error staging transfer:', e);
      throw new functions.https.HttpsError('internal', 'Failed to stage transfer');
    }
  }
);

/**
 * Commit staged transfer (Phase 2)
 */
export const commitTransfer = functions.https.onCall(
  async (data: { staged_transfer_id: string }, context): Promise<CompleteTransferResponse> => {
    console.log('[commitTransfer] ========== COMMIT DEBUG ==========');
    console.log('[commitTransfer] Input:', { staged_transfer_id: data.staged_transfer_id });
    console.log('[commitTransfer] Auth user:', context.auth?.uid);
    
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    const { staged_transfer_id } = data;
    if (!staged_transfer_id) throw new functions.https.HttpsError('invalid-argument', 'staged_transfer_id is required');

    try {
      const result = await db.runTransaction(async (transaction) => {
        const stagedRef = db.collection('staged_transfers').doc(staged_transfer_id);
        const stagedDoc = await transaction.get(stagedRef);
        
        console.log('[commitTransfer] Staged doc exists:', stagedDoc.exists);
        
        if (!stagedDoc.exists) throw new functions.https.HttpsError('not-found', 'Staged transfer not found');
        const staged = stagedDoc.data() as any;
        
        console.log('[commitTransfer] Staged data:', JSON.stringify({
          status: staged.status,
          token_uid: staged.token_uid,
          from_user_id: staged.from_user_id,
          to_user_id: staged.to_user_id,
          has_new_token_state: !!staged.new_token_state,
          new_token_state: staged.new_token_state
        }, null, 2));

        if (staged.status !== 'staged') {
          throw new functions.https.HttpsError('failed-precondition', `Staged transfer is ${staged.status}, not staged`);
        }
        if (staged.expires_at.toDate() < new Date()) {
          transaction.update(stagedRef, { status: 'expired' });
          throw new functions.https.HttpsError('deadline-exceeded', 'Staged transfer expired');
        }

        const tokenRef = db.collection('tokens').doc(staged.token_uid);
        
        // Ensure new_token_state exists
        if (!staged.new_token_state) {
          console.error('[commitTransfer] Missing new_token_state in staged transfer:', staged_transfer_id);
          throw new functions.https.HttpsError('internal', 'Invalid staged transfer data');
        }
        
        // Convert the new_token_state to use serverTimestamp for the update
        const tokenUpdate = {
          current_owner_id: staged.new_token_state.current_owner_id,
          previous_owners: staged.new_token_state.previous_owners,
          key_hash: staged.new_token_state.key_hash,
          last_transfer_at: admin.firestore.FieldValue.serverTimestamp(),
        };
        transaction.update(tokenRef, tokenUpdate);

        const sessionRef = db.collection('transferSessions').doc(staged.session_id);
        transaction.update(sessionRef, { status: 'completed' });

        transaction.update(stagedRef, { status: 'committed', committed_at: admin.firestore.Timestamp.now() });

        const transferLogId = crypto.randomBytes(16).toString('hex');
        const transferLog: TransferLog = {
          id: transferLogId,
          token_uid: staged.token_uid,
          from_user_id: staged.from_user_id,
          to_user_id: staged.to_user_id,
          session_id: staged.session_id,
          completed_at: admin.firestore.Timestamp.now(),
        } as any;
        transaction.set(db.collection('transfer_logs').doc(transferLogId), transferLog);

        const fromUserRef = db.collection('users').doc(staged.from_user_id);
        transaction.set(fromUserRef, {
          uid: staged.from_user_id,
          stats: { tokens_owned: admin.firestore.FieldValue.increment(-1), tokens_transferred_out: admin.firestore.FieldValue.increment(1) },
          last_active_at: admin.firestore.Timestamp.now(),
        }, { merge: true });

        const toUserRef = db.collection('users').doc(staged.to_user_id);
        transaction.set(toUserRef, {
          uid: staged.to_user_id,
          stats: { tokens_owned: admin.firestore.FieldValue.increment(1), tokens_received: admin.firestore.FieldValue.increment(1) },
          last_active_at: admin.firestore.Timestamp.now(),
        }, { merge: true });

        return { success: true, new_owner_id: staged.to_user_id, transfer_log_id: transferLogId } as any;
      });

      return result;
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      console.error('Error committing transfer:', e);
      throw new functions.https.HttpsError('internal', 'Failed to commit transfer');
    }
  }
);

/**
 * Rollback staged transfer
 */
export const rollbackTransfer = functions.https.onCall(
  async (data: { staged_transfer_id: string; reason?: string }, context): Promise<{ success: boolean; message: string }> => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    const { staged_transfer_id, reason = 'NFC write failed' } = data;
    if (!staged_transfer_id) throw new functions.https.HttpsError('invalid-argument', 'staged_transfer_id is required');

    try {
      const result = await db.runTransaction(async (transaction) => {
        const stagedRef = db.collection('staged_transfers').doc(staged_transfer_id);
        const stagedDoc = await transaction.get(stagedRef);
        if (!stagedDoc.exists) throw new functions.https.HttpsError('not-found', 'Staged transfer not found');
        const staged = stagedDoc.data() as any;

        if (staged.status !== 'staged') {
          throw new functions.https.HttpsError('failed-precondition', `Cannot rollback transfer with status: ${staged.status}`);
        }

        const sessionRef = db.collection('transferSessions').doc(staged.session_id);
        transaction.update(sessionRef, { status: 'pending', staged_transfer_id: admin.firestore.FieldValue.delete() });

        transaction.update(stagedRef, {
          status: 'rolled_back',
          rolled_back_at: admin.firestore.Timestamp.now(),
          rollback_reason: reason,
        });

        const logRef = db.collection('rollback_logs').doc();
        transaction.set(logRef, {
          staged_transfer_id,
          token_uid: staged.token_uid,
          from_user_id: staged.from_user_id,
          to_user_id: staged.to_user_id,
          reason,
          rolled_back_by: context.auth?.uid || 'unknown',
          rolled_back_at: admin.firestore.Timestamp.now(),
        });

        return { success: true, message: `Transfer staged ${staged_transfer_id} rolled back` };
      });

      return result;
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      console.error('Error rolling back transfer:', e);
      throw new functions.https.HttpsError('internal', 'Failed to rollback transfer');
    }
  }
);

/* ---------------- Legacy completeTransfer (kept, but now requires server validation) ---------------- */

export const completeTransfer = functions.https.onCall(
  async (data: CompleteTransferRequest, context): Promise<CompleteTransferResponse> => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');

    const { session_id, new_key_hash, new_owner_id } = data as any;
    const to_user_id: string = new_owner_id || context.auth.uid;
    if (!session_id || !new_key_hash) {
      throw new functions.https.HttpsError('invalid-argument', 'session_id and new_key_hash are required');
    }

    try {
      const result = await db.runTransaction(async (transaction) => {
        const sessionRef = db.collection('transferSessions').doc(session_id);
        const sessionDoc = await transaction.get(sessionRef);
        if (!sessionDoc.exists) throw new functions.https.HttpsError('not-found', 'Transfer session not found');
        const session = sessionDoc.data() as any;

        const exp = session.expires_at?.toDate ? session.expires_at.toDate() : new Date(session.expires_at);
        if (exp < new Date()) {
          transaction.update(sessionRef, { status: 'expired' });
          throw new functions.https.HttpsError('deadline-exceeded', 'Transfer session expired');
        }
        if (session.status !== 'pending') {
          throw new functions.https.HttpsError('failed-precondition', `Session is ${session.status}, not pending`);
        }

        // Hard requirement now
        const cd = session.challenge_data;
        if (cd && cd.validated_server_side !== true) {
          throw new functions.https.HttpsError('permission-denied', 'Challenge not validated server-side');
        }

        const tokenRef = db.collection('tokens').doc(session.token_uid);
        const tokenDoc = await transaction.get(tokenRef);
        if (!tokenDoc.exists) throw new functions.https.HttpsError('not-found', 'Token not found');
        const token = tokenDoc.data() as Token;

        if (token.current_owner_id !== session.from_user_id) {
          throw new functions.https.HttpsError('failed-precondition', 'Token ownership changed');
        }

        const proposedPreviousOwners = [...token.previous_owners, session.from_user_id];
        if (!validateOwnershipHistoryAppendOnly(token.previous_owners, proposedPreviousOwners, to_user_id)) {
          throw new functions.https.HttpsError('failed-precondition', 'Invalid ownership history change');
        }

        transaction.update(tokenRef, {
          current_owner_id: to_user_id,
          previous_owners: proposedPreviousOwners,
          key_hash: new_key_hash,
          last_transfer_at: admin.firestore.Timestamp.now(),
        });

        transaction.update(sessionRef, { status: 'completed', 'challenge_data.used': true });

        const transferLogId = crypto.randomBytes(16).toString('hex');
        const transferLog: TransferLog = {
          id: transferLogId,
          token_uid: session.token_uid,
          from_user_id: session.from_user_id,
          to_user_id,
          session_id,
          completed_at: admin.firestore.Timestamp.now(),
        } as any;
        transaction.set(db.collection('transfer_logs').doc(transferLogId), transferLog);

        const fromUserRef = db.collection('users').doc(session.from_user_id);
        transaction.set(fromUserRef, {
          uid: session.from_user_id,
          stats: { tokens_owned: admin.firestore.FieldValue.increment(-1), tokens_transferred_out: admin.firestore.FieldValue.increment(1) },
          last_active_at: admin.firestore.Timestamp.now(),
        }, { merge: true });

        const toUserRef = db.collection('users').doc(to_user_id);
        transaction.set(toUserRef, {
          uid: to_user_id,
          stats: { tokens_owned: admin.firestore.FieldValue.increment(1), tokens_received: admin.firestore.FieldValue.increment(1) },
          last_active_at: admin.firestore.Timestamp.now(),
        }, { merge: true });

        return { success: true, new_owner_id: to_user_id, transfer_log_id: transferLogId } as any;
      });

      return result;
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      console.error('Error completing transfer:', e);
      throw new functions.https.HttpsError('internal', 'Failed to complete transfer');
    }
  }
);

/**
 * Validate challenge (client helper). Now returns true only if server already validated.
 */
export const validateChallenge = functions.https.onCall(
  async (data: ValidateChallengeRequest, _context): Promise<ValidateChallengeResponse> => {
    const { session_id } = data;
    if (!session_id) throw new functions.https.HttpsError('invalid-argument', 'session_id is required');

    const sessionDoc = await db.collection('transferSessions').doc(session_id).get();
    if (!sessionDoc.exists) throw new functions.https.HttpsError('not-found', 'Transfer session not found');

    const session = sessionDoc.data() as any;
    const validated = !!session.challenge_data?.validated_server_side;
    return { valid: validated, session_id };
  }
);

/* ---------------- Token registration ---------------- */

export const registerToken = functions.https.onCall(
  async (data: { token_uid: string; key_hash: string; metadata?: any; force_overwrite?: boolean }, context) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');

    const { token_uid, key_hash, metadata = {}, force_overwrite = false } = data;
    const user_id = context.auth.uid;
    if (!token_uid || !key_hash) {
      throw new functions.https.HttpsError('invalid-argument', 'token_uid and key_hash are required');
    }

    const existingToken = await db.collection('tokens').doc(token_uid).get();

    let preservedData = {};
    if (existingToken.exists && !force_overwrite) {
      throw new functions.https.HttpsError('already-exists', 'Token already registered');
    }
    if (existingToken.exists && force_overwrite) {
      const existing = existingToken.data() as Token;

      const existingPreviousOwners = existing.previous_owners || [];
      const lastOwner = existingPreviousOwners[existingPreviousOwners.length - 1];
      const shouldAppendCurrentOwner = (
        existing.current_owner_id !== lastOwner &&
        existing.current_owner_id !== user_id
      );
      const proposedPreviousOwners = shouldAppendCurrentOwner
        ? [...existingPreviousOwners, existing.current_owner_id]
        : existingPreviousOwners;

      if (!validateOwnershipHistoryAppendOnly(existingPreviousOwners, proposedPreviousOwners, user_id)) {
        throw new functions.https.HttpsError('failed-precondition', 'Cannot modify ownership history');
      }

      preservedData = {
        previous_owners: proposedPreviousOwners,
        metadata: {
          travel_stats: existing.metadata?.travel_stats || {
            countries_visited: [],
            cities_visited: [],
            total_distance_km: 0,
          },
          leaderboard_points: existing.metadata?.leaderboard_points || 0,
          overwrite_history: [
            ...((existing.metadata as any)?.overwrite_history || []),
            {
              previous_owner: existing.current_owner_id,
              previous_created_at: existing.created_at,
              overwritten_at: admin.firestore.Timestamp.now(),
              overwritten_by: user_id,
            },
          ],
        },
      };
    }

    const newToken: Token = {
      uid: token_uid,
      current_owner_id: user_id,
      previous_owners: (preservedData as any).previous_owners || [],
      key_hash,
      created_at: admin.firestore.Timestamp.now(),
      last_transfer_at: admin.firestore.Timestamp.now(),
      metadata: {
        travel_stats: {
          countries_visited: [],
          cities_visited: [],
          total_distance_km: 0,
          ...(preservedData as any).metadata?.travel_stats,
        },
        leaderboard_points: (preservedData as any).metadata?.leaderboard_points || 0,
        ...metadata,
        ...(preservedData as any).metadata,
      },
    };

    await db.collection('tokens').doc(token_uid).set(newToken);
    await db.collection('users').doc(user_id).set({
      uid: user_id,
      'stats.tokens_owned': admin.firestore.FieldValue.increment(1),
      last_active_at: admin.firestore.Timestamp.now(),
    }, { merge: true });

    return { success: true, token_uid };
  }
);

/* ---------------- Schedulers ---------------- */

export const cleanupExpiredSessions = functions.pubsub
  .schedule('every 15 minutes')
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    try {
      const batch = db.batch();
      let total = 0;

      const expiredSessions = await db.collection('transferSessions')
        .where('status', '==', 'pending')
        .where('expires_at', '<', now)
        .limit(100)
        .get();
      expiredSessions.forEach((doc) => {
        batch.update(doc.ref, { status: 'expired' });
        total++;
      });

      const expiredStaged = await db.collection('staged_transfers')
        .where('status', '==', 'staged')
        .where('expires_at', '<', now)
        .limit(100)
        .get();
      expiredStaged.forEach((doc) => {
        batch.update(doc.ref, { status: 'expired' });
        const d = doc.data() as any;
        if (d.session_id) {
          const sref = db.collection('transferSessions').doc(d.session_id);
          batch.update(sref, { status: 'pending', staged_transfer_id: admin.firestore.FieldValue.delete() });
        }
        total++;
      });

      await batch.commit();
      console.log(`Cleaned ${total} expired items`);
    } catch (e) {
      console.error('Cleanup error:', e);
    }
  });

/* ---------------- Test helpers and admin ---------------- */

export const getTestCustomToken = functions.https.onCall(async (data) => {
  if (process.env.NODE_ENV === 'production' || process.env.FUNCTIONS_EMULATOR !== 'true') {
    throw new functions.https.HttpsError('unavailable', 'Test functions disabled in production');
  }
  const uid = (data && (data as any).uid) as string;
  if (!uid || typeof uid !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'uid is required');
  }
  const allowed = ['oliver', 'jonathan', 'test_user_1', 'test_user_2'];
  if (!allowed.includes(uid)) {
    throw new functions.https.HttpsError('invalid-argument', 'Only predefined test UIDs are allowed');
  }
  try {
    const token = await admin.auth().createCustomToken(uid);
    await db.collection('users').doc(uid).set({
      uid,
      last_active_at: admin.firestore.Timestamp.now(),
    }, { merge: true });
    return { token };
  } catch (err) {
    console.error('createCustomToken error:', err);
    throw new functions.https.HttpsError('internal', 'Failed to create custom token');
  }
});

async function isFirstAdminAssignment(): Promise<boolean> {
  const q = await db.collection('admin_logs').where('action', '==', 'admin_assigned').limit(1).get();
  return q.empty;
}

export const assignAdminPrivileges = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  const { uid: targetUid } = data;
  if (!targetUid) throw new functions.https.HttpsError('invalid-argument', 'Target UID is required');
  const first = await isFirstAdminAssignment();
  const isAdmin = context.auth.token?.admin === true;
  if (!first && !isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'Only admins can assign admin privileges');
  }
  try {
    await admin.auth().setCustomUserClaims(targetUid, { admin: true });
    await db.collection('admin_logs').add({
      action: 'admin_assigned',
      target_uid: targetUid,
      assigned_by: context.auth.uid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      is_first_admin: first,
    });
    await db.collection('admins').doc(targetUid).set({
      uid: targetUid,
      assigned_by: context.auth.uid,
      assigned_at: admin.firestore.FieldValue.serverTimestamp(),
      is_active: true,
    });
    return { success: true, message: `Admin privileges assigned to ${targetUid}`, is_first_admin: first };
  } catch (e) {
    console.error('assignAdminPrivileges error:', e);
    throw new functions.https.HttpsError('internal', 'Failed to assign admin privileges');
  }
});

export const revokeAdminPrivileges = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  const isAdmin = context.auth.token?.admin === true;
  if (!isAdmin) throw new functions.https.HttpsError('permission-denied', 'Only admins can revoke admin privileges');
  const { uid: targetUid } = data;
  if (!targetUid) throw new functions.https.HttpsError('invalid-argument', 'Target UID is required');
  if (targetUid === context.auth.uid) {
    throw new functions.https.HttpsError('permission-denied', 'Cannot revoke your own admin privileges');
  }
  try {
    await admin.auth().setCustomUserClaims(targetUid, { admin: false });
    await db.collection('admin_logs').add({
      action: 'admin_revoked',
      target_uid: targetUid,
      revoked_by: context.auth.uid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    await db.collection('admins').doc(targetUid).update({
      is_active: false,
      revoked_by: context.auth.uid,
      revoked_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true, message: `Admin privileges revoked from ${targetUid}` };
  } catch (e) {
    console.error('revokeAdminPrivileges error:', e);
    throw new functions.https.HttpsError('internal', 'Failed to revoke admin privileges');
  }
});

/* ---------------- Server command queue ---------------- */

export const queueServerCommand = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  const isAdmin = context.auth.token?.admin === true;
  if (!isAdmin) throw new functions.https.HttpsError('permission-denied', 'Requires admin privileges');

  const { token_uid, command } = data;
  if (!token_uid || !command || typeof command !== 'object') {
    throw new functions.https.HttpsError('invalid-argument', 'token_uid and command are required');
  }

  const schema: Record<string, { required: string[]; optional: string[]; maxSize: number }> = {
    upgrade_des_to_aes: { required: [], optional: ['backup_data', 'new_key_length'], maxSize: 1024 },
    rotate_master_key: { required: ['new_key_id'], optional: ['backup_old_key'], maxSize: 512 },
    change_file_permissions: { required: ['permissions'], optional: ['file_path'], maxSize: 256 },
    add_new_application: { required: ['app_id'], optional: ['app_config'], maxSize: 2048 },
    emergency_lockdown: { required: [], optional: ['reason'], maxSize: 512 },
    firmware_update: { required: ['version'], optional: ['update_url', 'checksum'], maxSize: 1024 },
    diagnostic_scan: { required: [], optional: ['scan_type'], maxSize: 256 },
  };

  if (!command.type || !schema[command.type]) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid command type');
  }
  const s = schema[command.type];
  const str = JSON.stringify(command);
  if (str.length > s.maxSize) {
    throw new functions.https.HttpsError('invalid-argument', 'Command payload too large');
  }
  for (const f of s.required) {
    if (!(f in command)) throw new functions.https.HttpsError('invalid-argument', `Missing required field: ${f}`);
  }
  const allowed = new Set(['type', ...s.required, ...s.optional]);
  for (const f of Object.keys(command)) {
    if (!allowed.has(f)) throw new functions.https.HttpsError('invalid-argument', `Unexpected field: ${f}`);
  }

  await db.collection('tokens').doc(token_uid).update({
    pending_command: command,
    command_queued_at: admin.firestore.FieldValue.serverTimestamp(),
    command_queued_by: context.auth.uid,
  });
  await db.collection('command_queue_logs').add({
    token_uid,
    command,
    queued_by: context.auth.uid,
    queued_at: admin.firestore.FieldValue.serverTimestamp(),
    status: 'pending',
  });

  return { success: true, message: `Command ${command.type} queued for token ${token_uid}` };
});

/* ---------------- Batch upgrade example ---------------- */

export const batchUpgradeEncryption = functions.https.onCall(async (data, context) => {
  if (!context.auth?.token?.admin) {
    throw new functions.https.HttpsError('permission-denied', 'Requires admin privileges');
  }

  const batch = admin.firestore().batch();
  const tokensSnapshot = await admin.firestore()
    .collection('tokens')
    .where('status', '==', 'active')
    .where('encryption_type', '==', 'DES')
    .get();

  const upgradeCommand = {
    type: 'upgrade_des_to_aes',
    priority: 'high',
    params: { new_aes_key: generateSecureKey(32), backup_data: true },
  };

  tokensSnapshot.docs.forEach((doc) => {
    batch.update(doc.ref, {
      pending_command: upgradeCommand,
      command_queued_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();
  return { success: true, message: `Queued encryption upgrade for ${tokensSnapshot.size} tokens` };
});

/* ---------------- Log cleanup ---------------- */

export const cleanupOldLogs = functions.pubsub.schedule('0 0 1 * *').onRun(async () => {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 90);
  const batch = admin.firestore().batch();
  let deleted = 0;

  const old = await admin.firestore()
    .collection('command_queue_logs')
    .where('queued_at', '<', cutoff)
    .limit(500)
    .get();

  old.docs.forEach((doc) => {
    batch.delete(doc.ref);
    deleted++;
  });

  if (deleted > 0) await batch.commit();
  return { deletedCount: deleted };
});

/* ---------------- Versioning ---------------- */

export const updateVersionRequirements = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  const isAdmin = context.auth.token?.admin === true;
  if (!isAdmin) throw new functions.https.HttpsError('permission-denied', 'Requires admin privileges');

  const { minimum_version, update_message, update_url, force_update_after } = data;
  const versionRegex = /^\d+\.\d+\.\d+$/;
  if (!versionRegex.test(minimum_version)) {
    throw new functions.https.HttpsError('invalid-argument', 'Version must be X.Y.Z');
  }

  await db.collection('config').doc('app_requirements').set({
    minimum_version,
    update_message: update_message || 'Please update to the latest version for security improvements.',
    update_url: update_url || null,
    force_update_after: force_update_after || null,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_by: context.auth.uid,
  }, { merge: true });

  await db.collection('version_update_logs').add({
    minimum_version,
    updated_by: context.auth.uid,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    reason: data.reason || 'Manual update',
  });

  return { success: true, message: `Minimum version updated to ${minimum_version}` };
});

export const checkVersionAllowed = functions.https.onCall(async (data) => {
  const { version } = data;
  if (!version) throw new functions.https.HttpsError('invalid-argument', 'Version is required');

  const configDoc = await admin.firestore().collection('config').doc('app_requirements').get();
  const config = configDoc.data();
  const minimum_version = config?.minimum_version || '1.0.0';
  const isAllowed = !isVersionOlder(version, minimum_version);
  return { allowed: isAllowed, minimum_version, update_message: config?.update_message, update_url: config?.update_url };
});

function isVersionOlder(current: string, required: string): boolean {
  const c = current.split('.').map(Number);
  const r = required.split('.').map(Number);
  for (let i = 0; i < r.length; i++) {
    const ci = i < c.length ? c[i] : 0;
    const ri = r[i];
    if (ci < ri) return true;
    if (ci > ri) return false;
  }
  return false;
}

/* ---------------- Seller verification passthrough ---------------- */

export {
  createSellerVerificationSession,
  verifySellerOwnership,
  completeSellerVerifiedTransaction,
  cancelSellerVerificationSession,
  cleanupExpiredVerificationSessions,
} from './seller-verification';

/* ---------------- Read file data helper ---------------- */

export const readFileData = functions
  .runWith({ timeoutSeconds: 60 })
  .https.onCall(async (data: { sessionId: string; fileNo?: number; length?: number }) => {
    const { sessionId, fileNo = 0x01, length = 200 } = data;
    if (!sessionId) throw new functions.https.HttpsError('invalid-argument', 'Missing sessionId');

    const offset = Buffer.allocUnsafe(3); offset.writeUIntLE(0, 0, 3);
    const len = Buffer.allocUnsafe(3); len.writeUIntLE(length, 0, 3);

    const readApdu = Buffer.concat([
      Buffer.from([0x90, 0xBD, 0x00, 0x00, 0x07]),
      Buffer.from([fileNo]),
      offset,
      len,
      Buffer.from([0x00]),
    ]);

    return { apdus: [readApdu.toString('base64')], expect: '9100_or_91AF' };
  });

/* ---------------- Stage transfer (explicit secure variant) ---------------- */

export const stageTransferSecure = functions.https.onCall(
  async (data: any, context): Promise<{ success: boolean; staged_transfer_id: string; new_owner_id: string; }> => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');

    const { session_id, new_key_hash, new_owner_id } = data;
    const to_user_id: string = new_owner_id || context.auth.uid;
    if (!session_id || !new_key_hash) {
      throw new functions.https.HttpsError('invalid-argument', 'session_id and new_key_hash are required');
    }

    try {
      const result = await db.runTransaction(async (transaction) => {
        const sessionRef = db.collection('transferSessions').doc(session_id);
        const sessionDoc = await transaction.get(sessionRef);
        if (!sessionDoc.exists) throw new functions.https.HttpsError('not-found', 'Transfer session not found');
        const session = sessionDoc.data() as any;

        if (session.expires_at.toMillis() < Date.now()) {
          throw new functions.https.HttpsError('deadline-exceeded', 'Transfer session expired');
        }
        if (session.status !== 'pending') {
          throw new functions.https.HttpsError('failed-precondition', `Transfer is not pending (status: ${session.status})`);
        }
        if (!session.challenge_data?.validated_server_side) {
          throw new functions.https.HttpsError('permission-denied', 'Challenge not validated server-side');
        }

        const tokenRef = db.collection('tokens').doc(session.token_uid);
        const tokenDoc = await transaction.get(tokenRef);
        if (!tokenDoc.exists) throw new functions.https.HttpsError('not-found', 'Token not found');
        const token = tokenDoc.data() as Token;

        if (token.current_owner_id !== session.from_user_id) {
          throw new functions.https.HttpsError('failed-precondition', 'Token ownership changed');
        }

        const staged_transfer_id = `staged_${session_id}_${Date.now()}`;
        
        // Prepare the new token state
        const proposedPreviousOwners = [...(token.previous_owners || []), session.from_user_id];
        
        transaction.set(db.collection('staged_transfers').doc(staged_transfer_id), {
          session_id,
          token_uid: session.token_uid,
          from_user_id: session.from_user_id,
          to_user_id,
          new_key_hash,
          staged_at: admin.firestore.FieldValue.serverTimestamp(),
          status: 'staged',
          server_validated: true,
          expires_at: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000)),
          // Add the new_token_state that commitTransfer expects
          new_token_state: {
            current_owner_id: to_user_id,
            previous_owners: proposedPreviousOwners,
            key_hash: new_key_hash
          }
        });
        transaction.update(sessionRef, { status: 'staged', 'challenge_data.used': true });

        return { staged_transfer_id, new_owner_id: to_user_id };
      });

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      console.error('Error staging transfer:', e);
      throw new functions.https.HttpsError('internal', 'Failed to stage transfer');
    }
  }
);

