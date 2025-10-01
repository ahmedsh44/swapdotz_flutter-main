#!/usr/bin/env node

/**
 * CLI simulator for testing server-authoritative DESFire flow
 * Simulates card responses for CI/testing
 */

const crypto = require('crypto');

// Mock Firebase Functions (replace with actual HTTP calls in real test)
class MockFunctions {
  constructor() {
    this.sessions = new Map();
  }

  async beginAuthenticate({ tokenId, userId }) {
    const sessionId = crypto.randomBytes(16).toString('hex');
    
    // Store session
    this.sessions.set(sessionId, {
      tokenId,
      userId,
      phase: 'auth',
      keyVersion: 1
    });

    // Return first auth APDU (90 1A 00 00 01 00 00)
    const apdu = Buffer.from([0x90, 0x1A, 0x00, 0x00, 0x01, 0x00, 0x00]);
    
    return {
      sessionId,
      apdus: [apdu.toString('base64')],
      expect: '91AF'
    };
  }

  async continueAuthenticate({ sessionId, response }) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error('Session not found');

    if (session.phase === 'auth') {
      // First response received, send continuation
      const apdu = Buffer.from([0x90, 0xAF, 0x00, 0x00, 0x10]);
      const data = crypto.randomBytes(16); // Encrypted RndA || rotated RndB
      const fullApdu = Buffer.concat([apdu, data, Buffer.from([0x00])]);
      
      session.phase = 'auth-cont';
      
      return {
        apdus: [fullApdu.toString('base64')],
        done: false
      };
    } else {
      // Auth complete
      session.phase = 'auth-ok';
      return { done: true };
    }
  }

  async changeKey({ sessionId, targetKey }) {
    const session = this.sessions.get(sessionId);
    if (!session || session.phase !== 'auth-ok') {
      throw new Error('Session not authenticated');
    }

    // Return ChangeKey APDU
    const apdu = Buffer.from([0x90, 0xC4, 0x00, 0x00, 0x20]);
    const data = crypto.randomBytes(32); // Encrypted key data
    const fullApdu = Buffer.concat([apdu, data, Buffer.from([0x00])]);
    
    const verifyToken = crypto.randomBytes(16).toString('hex');
    
    return {
      apdus: [fullApdu.toString('base64')],
      verifyToken
    };
  }

  async confirmChangeKey({ sessionId, responses, verifyToken }) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error('Session not found');
    
    // Check last response status
    const lastResponse = Buffer.from(responses[responses.length - 1], 'base64');
    const sw = lastResponse.slice(-2).toString('hex');
    
    if (sw === '9100') {
      session.phase = 'mid-ok';
      return { ok: true };
    }
    
    return { ok: false };
  }

  async finalizeTransfer({ sessionId, newOwnerId }) {
    const session = this.sessions.get(sessionId);
    if (!session || session.phase !== 'mid-ok') {
      throw new Error('Invalid session state');
    }
    
    console.log(`Transfer complete: ${session.tokenId} -> ${newOwnerId}`);
    session.phase = 'complete';
    
    return { success: true };
  }
}

// Card simulator
class CardSimulator {
  constructor() {
    this.key = Buffer.from('000102030405060708090A0B0C0D0E0F1011121314151617', 'hex');
    this.rndB = null;
    this.rndA = null;
  }

  transceive(apduBase64) {
    const apdu = Buffer.from(apduBase64, 'base64');
    const ins = apdu[1];
    
    switch (ins) {
      case 0x1A: // Authenticate ISO
        return this.handleAuthStart();
        
      case 0xAF: // Additional Frame
        return this.handleAuthContinue(apdu);
        
      case 0xC4: // ChangeKey
        return this.handleChangeKey(apdu);
        
      default:
        // Unknown command
        return Buffer.from([0x91, 0x6E]).toString('base64');
    }
  }

  handleAuthStart() {
    // Generate and encrypt RndB
    this.rndB = crypto.randomBytes(8);
    const encRndB = this.encrypt3DES(this.key, this.rndB);
    
    // Return encrypted RndB with 91 AF (more frames)
    return Buffer.concat([encRndB, Buffer.from([0x91, 0xAF])]).toString('base64');
  }

  handleAuthContinue(apdu) {
    // Extract encrypted data
    const lc = apdu[4];
    const data = apdu.slice(5, 5 + lc);
    
    // Decrypt
    const decrypted = this.decrypt3DES(this.key, data);
    
    // Extract RndA and rotated RndB
    this.rndA = decrypted.slice(0, 8);
    const rndBRotated = decrypted.slice(8, 16);
    
    // Verify rotated RndB
    const expectedRotated = this.rotateLeft(this.rndB, 1);
    if (!rndBRotated.equals(expectedRotated)) {
      return Buffer.from([0x91, 0xAE]).toString('base64'); // Auth error
    }
    
    // Return encrypted rotated RndA with 91 00 (success)
    const rndARotated = this.rotateLeft(this.rndA, 1);
    const encResponse = this.encrypt3DES(this.key, rndARotated);
    
    return Buffer.concat([encResponse, Buffer.from([0x91, 0x00])]).toString('base64');
  }

  handleChangeKey(apdu) {
    // Simulate successful key change
    return Buffer.from([0x91, 0x00]).toString('base64');
  }

  encrypt3DES(key, data) {
    // Simple mock - in real implementation use proper 3DES
    return Buffer.from(data).reverse();
  }

  decrypt3DES(key, data) {
    // Simple mock - in real implementation use proper 3DES
    return Buffer.from(data).reverse();
  }

  rotateLeft(buffer, n) {
    const result = Buffer.allocUnsafe(buffer.length);
    for (let i = 0; i < buffer.length; i++) {
      result[i] = buffer[(i + n) % buffer.length];
    }
    return result;
  }
}

// Main test flow
async function runTest() {
  console.log('=== DESFire Server-Authoritative Test ===\n');
  
  const functions = new MockFunctions();
  const card = new CardSimulator();
  
  try {
    // 1. Begin authentication
    console.log('1. Starting authentication...');
    const { sessionId, apdus, expect } = await functions.beginAuthenticate({
      tokenId: 'test-token-123',
      userId: 'user-alice'
    });
    
    console.log(`   Session: ${sessionId}`);
    console.log(`   First APDU: ${apdus[0]}`);
    console.log(`   Expecting: ${expect}\n`);
    
    // Simulate card response
    const response1 = card.transceive(apdus[0]);
    console.log(`   Card response: ${response1.substring(0, 50)}...\n`);
    
    // 2. Continue authentication
    console.log('2. Continuing authentication...');
    const cont1 = await functions.continueAuthenticate({
      sessionId,
      response: response1
    });
    
    if (!cont1.done) {
      console.log(`   Next APDU: ${cont1.apdus[0].substring(0, 50)}...`);
      
      const response2 = card.transceive(cont1.apdus[0]);
      console.log(`   Card response: ${response2}\n`);
      
      const cont2 = await functions.continueAuthenticate({
        sessionId,
        response: response2
      });
      
      console.log(`   Authentication complete: ${cont2.done}\n`);
    }
    
    // 3. Change key
    console.log('3. Changing key...');
    const { apdus: keyApdus, verifyToken } = await functions.changeKey({
      sessionId,
      targetKey: 'new'
    });
    
    console.log(`   ChangeKey APDU: ${keyApdus[0].substring(0, 50)}...`);
    console.log(`   Verify token: ${verifyToken}\n`);
    
    const keyResponse = card.transceive(keyApdus[0]);
    console.log(`   Card response: ${keyResponse}\n`);
    
    // 4. Confirm key change
    console.log('4. Confirming key change...');
    const confirmed = await functions.confirmChangeKey({
      sessionId,
      responses: [keyResponse],
      verifyToken
    });
    
    console.log(`   Key change confirmed: ${confirmed.ok}\n`);
    
    // 5. Finalize transfer
    console.log('5. Finalizing transfer...');
    const result = await functions.finalizeTransfer({
      sessionId,
      newOwnerId: 'user-bob'
    });
    
    console.log(`   Transfer finalized: ${result.success}\n`);
    
    console.log('✅ Test completed successfully!');
    
  } catch (error) {
    console.error('❌ Test failed:', error);
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  runTest();
}

module.exports = { MockFunctions, CardSimulator, runTest }; 