#!/usr/bin/env node

/**
 * Test script for Firebase-only DESFire implementation
 * Tests the complete flow with all crypto in Firebase Functions
 */

const crypto = require('crypto');

// Simulated Firebase Functions (replace with actual deployed functions in production)
class FirebaseFunctions {
  constructor() {
    this.sessions = new Map();
    this.tokens = new Map();
    
    // Initialize test token
    this.tokens.set('test-token-123', {
      ownerId: 'user-alice',
      keyVersion: 0,
      keyHash: null
    });
  }

  /**
   * Simulate beginAuthenticate callable
   */
  async beginAuthenticate({ tokenId, userId }) {
    console.log(`[Firebase] Starting auth for token ${tokenId}, user ${userId}`);
    
    const token = this.tokens.get(tokenId);
    if (!token) throw new Error('Token not found');
    
    if (token.lock && token.lock.expiresAt > Date.now()) {
      throw new Error('Token is locked');
    }
    
    // Create session
    const sessionId = crypto.randomBytes(16).toString('hex');
    const session = {
      tokenId,
      userId,
      phase: 'auth',
      keyVersion: token.keyVersion,
      expiresAt: Date.now() + 15000,
      // Crypto state (normally in Functions memory)
      key: Buffer.from('000102030405060708090A0B0C0D0E0F1011121314151617', 'hex')
    };
    
    this.sessions.set(sessionId, session);
    
    // Lock token
    token.lock = {
      sessionId,
      expiresAt: session.expiresAt
    };
    
    // Return first auth APDU: 90 1A 00 00 01 00 00
    const apdu = Buffer.from([0x90, 0x1A, 0x00, 0x00, 0x01, 0x00, 0x00]);
    
    return {
      sessionId,
      apdus: [apdu.toString('base64')]
    };
  }

  /**
   * Simulate continueAuthenticate callable
   */
  async continueAuthenticate({ sessionId, response }) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error('Session not found');
    
    if (session.expiresAt < Date.now()) {
      throw new Error('Session expired');
    }
    
    const responseBytes = Buffer.from(response, 'base64');
    const sw = responseBytes.slice(-2).toString('hex');
    const data = responseBytes.slice(0, -2);
    
    console.log(`[Firebase] Processing response with SW=${sw}`);
    
    if (session.phase === 'auth' && !session.rndB) {
      // First response: encrypted RndB
      if (sw !== '91af') throw new Error(`Unexpected SW: ${sw}`);
      
      // Decrypt RndB (mock)
      session.rndB = Buffer.from(data).reverse(); // Mock decrypt
      session.rndA = crypto.randomBytes(8);
      
      // Build response: RndA || rotateLeft(RndB, 1)
      const rotated = Buffer.concat([
        session.rndB.slice(1),
        session.rndB.slice(0, 1)
      ]);
      
      const response = Buffer.concat([session.rndA, rotated]);
      const encrypted = Buffer.from(response).reverse(); // Mock encrypt
      
      // Build APDU: 90 AF 00 00 10 <encrypted> 00
      const apdu = Buffer.concat([
        Buffer.from([0x90, 0xAF, 0x00, 0x00, 0x10]),
        encrypted,
        Buffer.from([0x00])
      ]);
      
      console.log('[Firebase] Sending RndA || rot(RndB)');
      
      return {
        apdus: [apdu.toString('base64')]
      };
      
    } else if (session.rndA && session.rndB) {
      // Second response: encrypted rotated RndA
      if (sw !== '9100') throw new Error('Auth failed');
      
      // Verify (mock - just check it's 8 bytes)
      if (data.length !== 8) throw new Error('Invalid response');
      
      // Generate session key
      session.sessionKey = Buffer.concat([
        session.rndA.slice(0, 4),
        session.rndB.slice(0, 4),
        session.rndA.slice(4, 8),
        session.rndB.slice(4, 8),
        session.rndA.slice(0, 4),
        session.rndB.slice(0, 4)
      ]);
      
      session.phase = 'auth-ok';
      console.log('[Firebase] Authentication complete, session key generated');
      
      return { done: true };
    }
    
    throw new Error('Invalid session state');
  }

  /**
   * Simulate changeKey callable
   */
  async changeKey({ sessionId }) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error('Session not found');
    
    if (session.phase !== 'auth-ok') {
      throw new Error('Not authenticated');
    }
    
    console.log('[Firebase] Generating ChangeKey APDU');
    
    // Generate new key (server-side only!)
    const newKey = crypto.randomBytes(24);
    session.pendingKey = newKey;
    
    // Build encrypted ChangeKey payload (mock)
    const payload = crypto.randomBytes(32); // Mock encrypted data
    
    // Build APDU: 90 C4 00 00 20 <encrypted> 00
    const apdu = Buffer.concat([
      Buffer.from([0x90, 0xC4, 0x00, 0x00, 0x20]),
      payload,
      Buffer.from([0x00])
    ]);
    
    return {
      apdus: [apdu.toString('base64')]
    };
  }

  /**
   * Simulate confirmAndFinalize callable
   */
  async confirmAndFinalize({ sessionId, response, newOwnerId }) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error('Session not found');
    
    const responseBytes = Buffer.from(response, 'base64');
    const sw = responseBytes.slice(-2).toString('hex');
    
    if (sw !== '9100') {
      throw new Error(`Key change failed: ${sw}`);
    }
    
    console.log('[Firebase] Key change confirmed, finalizing transfer');
    
    // Update token in "Firestore"
    const token = this.tokens.get(session.tokenId);
    if (!token) throw new Error('Token not found');
    
    const previousOwner = token.ownerId;
    token.ownerId = newOwnerId;
    token.keyVersion++;
    token.keyHash = crypto.createHash('sha256')
      .update(session.pendingKey)
      .digest('hex');
    delete token.lock;
    
    // Clean up session
    this.sessions.delete(sessionId);
    
    console.log(`[Firebase] Transfer complete: ${previousOwner} -> ${newOwnerId}`);
    console.log(`[Firebase] New key version: ${token.keyVersion}`);
    console.log(`[Firebase] New key hash: ${token.keyHash.substring(0, 16)}...`);
    
    return { success: true };
  }
}

// Mock NFC card
class MockCard {
  constructor() {
    this.key = Buffer.from('000102030405060708090A0B0C0D0E0F1011121314151617', 'hex');
    this.rndB = null;
  }

  transceive(apduBase64) {
    const apdu = Buffer.from(apduBase64, 'base64');
    const ins = apdu[1];
    
    console.log(`[Card] Received APDU with INS=0x${ins.toString(16)}`);
    
    switch (ins) {
      case 0x1A: // Authenticate ISO
        // Generate and "encrypt" RndB
        this.rndB = crypto.randomBytes(8);
        const encRndB = Buffer.from(this.rndB).reverse(); // Mock encrypt
        console.log('[Card] Sending encrypted RndB');
        return Buffer.concat([encRndB, Buffer.from([0x91, 0xAF])]).toString('base64');
        
      case 0xAF: // Additional frame
        // Return "encrypted" rotated RndA
        const encRndA = crypto.randomBytes(8); // Mock
        console.log('[Card] Sending encrypted rotated RndA');
        return Buffer.concat([encRndA, Buffer.from([0x91, 0x00])]).toString('base64');
        
      case 0xC4: // ChangeKey
        console.log('[Card] Key changed successfully');
        return Buffer.from([0x91, 0x00]).toString('base64');
        
      default:
        return Buffer.from([0x91, 0x6E]).toString('base64'); // Command not supported
    }
  }
}

// Mobile app simulator (just forwards APDUs)
class MobileApp {
  constructor(functions, card) {
    this.functions = functions;
    this.card = card;
  }

  async performTransfer(tokenId, currentUserId, newOwnerId) {
    console.log('\n=== Mobile App: Starting Transfer ===\n');
    
    try {
      // 1. Begin authentication
      console.log('[App] Calling beginAuthenticate...');
      const { sessionId, apdus: authApdus } = await this.functions.beginAuthenticate({
        tokenId,
        userId: currentUserId
      });
      
      console.log(`[App] Got session: ${sessionId}`);
      console.log(`[App] Forwarding APDU to card...`);
      
      // Forward to card
      let cardResponse = this.card.transceive(authApdus[0]);
      console.log(`[App] Got card response, forwarding to Firebase...\n`);
      
      // 2. Continue authentication rounds
      let authDone = false;
      while (!authDone) {
        const result = await this.functions.continueAuthenticate({
          sessionId,
          response: cardResponse
        });
        
        if (result.done) {
          authDone = true;
          console.log('[App] Authentication complete!\n');
        } else {
          console.log('[App] Forwarding next APDU to card...');
          cardResponse = this.card.transceive(result.apdus[0]);
          console.log('[App] Got card response, continuing...\n');
        }
      }
      
      // 3. Change key
      console.log('[App] Calling changeKey...');
      const { apdus: keyApdus } = await this.functions.changeKey({ sessionId });
      
      console.log('[App] Forwarding ChangeKey APDU to card...');
      const keyResponse = this.card.transceive(keyApdus[0]);
      console.log('[App] Got card response\n');
      
      // 4. Finalize
      console.log('[App] Calling confirmAndFinalize...');
      const result = await this.functions.confirmAndFinalize({
        sessionId,
        response: keyResponse,
        newOwnerId
      });
      
      if (result.success) {
        console.log('[App] ✅ Transfer complete!\n');
      }
      
    } catch (error) {
      console.error('[App] ❌ Transfer failed:', error.message);
    }
  }
}

// Run test
async function runTest() {
  console.log('=== Firebase-Only DESFire Test ===');
  console.log('All cryptography happens in Firebase Functions');
  console.log('The mobile app only forwards opaque APDUs\n');
  
  const functions = new FirebaseFunctions();
  const card = new MockCard();
  const app = new MobileApp(functions, card);
  
  await app.performTransfer(
    'test-token-123',
    'user-alice',
    'user-bob'
  );
  
  // Verify final state
  const token = functions.tokens.get('test-token-123');
  console.log('=== Final Token State ===');
  console.log(`Owner: ${token.ownerId}`);
  console.log(`Key Version: ${token.keyVersion}`);
  console.log(`Key Hash: ${token.keyHash?.substring(0, 16)}...`);
  console.log(`Lock: ${token.lock ? 'LOCKED' : 'unlocked'}`);
  
  if (token.ownerId === 'user-bob' && token.keyVersion === 1 && !token.lock) {
    console.log('\n✅ All tests passed!');
  } else {
    console.log('\n❌ Test failed - unexpected final state');
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  runTest().catch(console.error);
}

module.exports = { FirebaseFunctions, MockCard, MobileApp }; 