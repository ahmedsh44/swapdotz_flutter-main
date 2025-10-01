import express, { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const app = express();
app.use(express.json());

// Constants
const PORT = process.env.PORT || 8080;
const PROJECT_ID = process.env.GCP_PROJECT;

// DESFire Constants
const CMD_AUTHENTICATE_ISO = 0x1A;  // ISO 3DES authentication
const CMD_AUTHENTICATE_AES = 0xAA;  // AES authentication
const CMD_ADDITIONAL_FRAME = 0xAF;  // Continue multi-frame
const CMD_CHANGE_KEY = 0xC4;        // Change key command

const SW_SUCCESS = '9100';          // Success
const SW_ADDITIONAL_FRAME = '91AF'; // More frames follow
const SW_LENGTH_ERROR = '917E';     // Length error
const SW_AUTH_ERROR = '91AE';       // Authentication error
const SW_CRYPTO_ERROR = '9197';     // Crypto error

// Session storage (in production, use Redis)
interface AuthSession {
  sessionId: string;
  keyVersion: number;
  keyNo: number;
  step: number;
  encRndB?: string;
  rndB?: Buffer;
  rndA?: Buffer;
  sessionKey?: Buffer;
  iv?: Buffer;
}

const sessions = new Map<string, AuthSession>();

// Secret Manager client
const secretClient = new SecretManagerServiceClient();

// Load master key from Secret Manager
let masterKey: Buffer | null = null;

async function loadMasterKey(): Promise<Buffer> {
  if (masterKey) return masterKey;

  if (process.env.DESFIRE_MASTER_KEY) {
    // Development: use env var
    masterKey = Buffer.from(process.env.DESFIRE_MASTER_KEY, 'hex');
    return masterKey;
  }

  // Production: load from Secret Manager
  const name = `projects/${PROJECT_ID}/secrets/desfire-master-key/versions/latest`;
  const [version] = await secretClient.accessSecretVersion({ name });
  const payload = version.payload?.data;
  
  if (!payload) {
    throw new Error('Failed to load master key');
  }

  masterKey = Buffer.from(payload.toString(), 'hex');
  return masterKey;
}

// Derive key for specific version
function deriveKey(masterKey: Buffer, keyVersion: number): Buffer {
  // Simple derivation: HMAC(masterKey, "version:N")
  // In production, use proper KDF
  const hmac = crypto.createHmac('sha256', masterKey);
  hmac.update(`version:${keyVersion}`);
  return hmac.digest().slice(0, 24); // 24 bytes for 3DES
}

// Build native APDU frame
function buildApdu(ins: number, data?: Buffer): string {
  const header = Buffer.from([0x90, ins, 0x00, 0x00]);
  
  if (data && data.length > 0) {
    const lc = Buffer.from([data.length]);
    const le = Buffer.from([0x00]);
    const apdu = Buffer.concat([header, lc, data, le]);
    return apdu.toString('base64');
  } else {
    // No data
    const apdu = Buffer.concat([header, Buffer.from([0x00, 0x00])]);
    return apdu.toString('base64');
  }
}

// Parse card response
function parseResponse(responseB64: string): { data: Buffer; sw: string } {
  const response = Buffer.from(responseB64, 'base64');
  
  if (response.length < 2) {
    throw new Error('Invalid response length');
  }

  const sw1 = response[response.length - 2];
  const sw2 = response[response.length - 1];
  const sw = Buffer.from([sw1, sw2]).toString('hex').toUpperCase();
  const data = response.slice(0, response.length - 2);

  return { data, sw };
}

// 3DES encryption (ECB mode for DESFire)
function encrypt3DES(key: Buffer, data: Buffer): Buffer {
  // DESFire uses 3DES in ECB mode for auth
  // Key is 24 bytes (3x8), data is 8-byte blocks
  const cipher = crypto.createCipheriv('des-ede3', key, null);
  cipher.setAutoPadding(false);
  return Buffer.concat([cipher.update(data), cipher.final()]);
}

// 3DES decryption (ECB mode)
function decrypt3DES(key: Buffer, data: Buffer): Buffer {
  const decipher = crypto.createDecipheriv('des-ede3', key, null);
  decipher.setAutoPadding(false);
  return Buffer.concat([decipher.update(data), decipher.final()]);
}

// XOR two buffers
function xorBuffers(a: Buffer, b: Buffer): Buffer {
  const result = Buffer.allocUnsafe(a.length);
  for (let i = 0; i < a.length; i++) {
    result[i] = a[i] ^ b[i % b.length];
  }
  return result;
}

// Rotate buffer left by n bytes
function rotateLeft(buffer: Buffer, n: number): Buffer {
  const result = Buffer.allocUnsafe(buffer.length);
  for (let i = 0; i < buffer.length; i++) {
    result[i] = buffer[(i + n) % buffer.length];
  }
  return result;
}

// Middleware: Verify IAM/OIDC token
async function verifyAuth(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // In production, verify the OIDC token properly
  // For now, just check it exists
  const token = authHeader.substring(7);
  
  if (!token) {
    return res.status(401).json({ error: 'Invalid token' });
  }

  // TODO: Verify token with Google OAuth2 client
  // const ticket = await client.verifyIdToken({
  //   idToken: token,
  //   audience: EXPECTED_AUDIENCE
  // });

  next();
}

// Apply auth middleware to all routes
app.use(verifyAuth);

// POST /apdu/auth-begin - Start ISO 3DES authentication
app.post('/apdu/auth-begin', async (req: Request, res: Response) => {
  try {
    const { sessionId, keyVersion, keyNo = 0 } = req.body;

    if (!sessionId || keyVersion === undefined) {
      return res.status(400).json({ error: 'Missing required parameters' });
    }

    // Initialize session
    const session: AuthSession = {
      sessionId,
      keyVersion,
      keyNo,
      step: 0
    };
    sessions.set(sessionId, session);

    // Build first auth APDU: 90 1A 00 00 01 <keyNo> 00
    const apdu = buildApdu(CMD_AUTHENTICATE_ISO, Buffer.from([keyNo]));

    res.json({
      apdus: [apdu],
      expect: SW_ADDITIONAL_FRAME // Expect 91 AF
    });
  } catch (error: any) {
    console.error('auth-begin error:', error);
    res.status(500).json({ error: error.message });
  }
});

// POST /apdu/auth-step - Continue authentication
app.post('/apdu/auth-step', async (req: Request, res: Response) => {
  try {
    const { sessionId, response, keyVersion } = req.body;

    if (!sessionId || !response) {
      return res.status(400).json({ error: 'Missing required parameters' });
    }

    const session = sessions.get(sessionId);
    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    // Parse card response
    const { data, sw } = parseResponse(response);

    if (session.step === 0) {
      // First response: encrypted RndB from card
      if (sw !== SW_ADDITIONAL_FRAME.toLowerCase() && sw !== SW_ADDITIONAL_FRAME) {
        return res.status(400).json({ error: `Unexpected SW: ${sw}` });
      }

      if (data.length !== 8) {
        return res.status(400).json({ error: 'Invalid RndB length' });
      }

      // Load and derive key
      const masterKey = await loadMasterKey();
      const key = deriveKey(masterKey, keyVersion);

      // Decrypt RndB
      const rndB = decrypt3DES(key, data);
      session.rndB = rndB;
      session.encRndB = data.toString('hex');

      // Generate RndA
      const rndA = crypto.randomBytes(8);
      session.rndA = rndA;

      // Build response: RndA || rotateLeft(RndB, 1)
      const rndBRotated = rotateLeft(rndB, 1);
      const responseData = Buffer.concat([rndA, rndBRotated]);

      // Encrypt response
      const encResponse = encrypt3DES(key, responseData);

      // Build continuation APDU: 90 AF 00 00 10 <encrypted_data> 00
      const apdu = buildApdu(CMD_ADDITIONAL_FRAME, encResponse);

      session.step = 1;
      sessions.set(sessionId, session);

      res.json({
        apdus: [apdu],
        done: false
      });

    } else if (session.step === 1) {
      // Second response: encrypted rotated RndA from card
      if (sw !== SW_SUCCESS.toLowerCase() && sw !== SW_SUCCESS) {
        return res.status(400).json({ error: `Auth failed, SW: ${sw}` });
      }

      if (data.length !== 8) {
        return res.status(400).json({ error: 'Invalid response length' });
      }

      // Load key
      const masterKey = await loadMasterKey();
      const key = deriveKey(masterKey, keyVersion);

      // Decrypt and verify rotated RndA
      const decrypted = decrypt3DES(key, data);
      const expectedRndA = rotateLeft(session.rndA!, 1);

      if (!decrypted.equals(expectedRndA)) {
        return res.status(400).json({ error: 'Authentication verification failed' });
      }

      // Generate session key from RndA and RndB
      // SessionKey = RndA[0:4] || RndB[0:4] || RndA[4:8] || RndB[4:8] || RndA[0:4] || RndB[0:4]
      const sessionKey = Buffer.concat([
        session.rndA!.slice(0, 4),
        session.rndB!.slice(0, 4),
        session.rndA!.slice(4, 8),
        session.rndB!.slice(4, 8),
        session.rndA!.slice(0, 4),
        session.rndB!.slice(0, 4)
      ]);

      session.sessionKey = sessionKey;
      session.iv = Buffer.alloc(8, 0); // Initial IV is zeros
      sessions.set(sessionId, session);

      res.json({
        done: true
      });
    } else {
      return res.status(400).json({ error: 'Invalid auth step' });
    }
  } catch (error: any) {
    console.error('auth-step error:', error);
    res.status(500).json({ error: error.message });
  }
});

// POST /apdu/change-key - Generate ChangeKey command
app.post('/apdu/change-key', async (req: Request, res: Response) => {
  try {
    const { sessionId, keyVersion, targetKey } = req.body;

    if (!sessionId || keyVersion === undefined || !targetKey) {
      return res.status(400).json({ error: 'Missing required parameters' });
    }

    const session = sessions.get(sessionId);
    if (!session || !session.sessionKey) {
      return res.status(404).json({ error: 'Session not authenticated' });
    }

    // Generate new key
    const newKey = crypto.randomBytes(24); // 24 bytes for 3DES

    // Build ChangeKey payload (simplified - real implementation needs proper CRC and padding)
    // Format: keyNo || newKey XOR oldKey || CRC32 || padding
    const keyNo = targetKey === 'mid' ? 0x01 : 0x00; // Key 1 for mid, 0 for master
    
    // Load current key
    const masterKey = await loadMasterKey();
    const currentKey = deriveKey(masterKey, keyVersion);

    // XOR new key with old key (simplified)
    const xoredKey = xorBuffers(newKey, currentKey);

    // Calculate CRC32 (placeholder - use proper CRC32)
    const crc = Buffer.alloc(4, 0);

    // Build payload
    const payload = Buffer.concat([
      Buffer.from([keyNo]),
      xoredKey,
      crc
    ]);

    // Pad to 32 bytes (8-byte blocks for 3DES)
    const paddedPayload = Buffer.concat([
      payload,
      Buffer.alloc(32 - payload.length, 0x80) // 0x80 padding
    ]);

    // Encrypt with session key (CBC mode)
    const cipher = crypto.createCipheriv('des-ede3-cbc', session.sessionKey, session.iv!);
    cipher.setAutoPadding(false);
    const encrypted = Buffer.concat([cipher.update(paddedPayload), cipher.final()]);

    // Build ChangeKey APDU
    const apdu = buildApdu(CMD_CHANGE_KEY, encrypted);

    // Generate verify token (hash of new key for verification)
    const verifyToken = crypto.createHash('sha256')
      .update(newKey)
      .update(Buffer.from(sessionId))
      .digest('hex');

    // Store for verification
    session.iv = encrypted.slice(-8); // Update IV for next command

    res.json({
      apdus: [apdu],
      verifyToken
    });
  } catch (error: any) {
    console.error('change-key error:', error);
    res.status(500).json({ error: error.message });
  }
});

// POST /apdu/change-key-verify - Verify key change
app.post('/apdu/change-key-verify', async (req: Request, res: Response) => {
  try {
    const { sessionId, responses, verifyToken, keyVersion } = req.body;

    if (!sessionId || !responses || !verifyToken) {
      return res.status(400).json({ error: 'Missing required parameters' });
    }

    // Parse response
    const lastResponse = responses[responses.length - 1];
    const { sw } = parseResponse(lastResponse);

    // Check if change was successful
    if (sw !== SW_SUCCESS.toLowerCase() && sw !== SW_SUCCESS) {
      return res.status(400).json({ 
        error: `Key change failed, SW: ${sw}`,
        ok: false 
      });
    }

    // In a real implementation, we would:
    // 1. Try authenticating with the new key
    // 2. Verify the card responds correctly
    // For now, just check the status word

    res.json({
      ok: true
    });
  } catch (error: any) {
    console.error('change-key-verify error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'healthy' });
});

// Start server
const server = app.listen(PORT, () => {
  console.log(`APDU service listening on port ${PORT}`);
});

// Cleanup sessions periodically (every 30 seconds)
setInterval(() => {
  const now = Date.now();
  const timeout = 30000; // 30 seconds
  
  for (const [sessionId, session] of sessions.entries()) {
    // Simple timeout based on sessionId (which includes timestamp)
    // In production, track creation time properly
    sessions.delete(sessionId);
  }
}, 30000);

export default app; 