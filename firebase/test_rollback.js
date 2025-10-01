/**
 * Test script for the rollback functionality
 * This demonstrates the two-phase commit pattern for NFC transfers
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin (for testing purposes)
// In production, this would be initialized in the Firebase Functions environment
const serviceAccount = require('./service-account-key.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'swapdotz-dev' // Replace with your project ID
});

const db = admin.firestore();

async function testRollbackScenario() {
  console.log('Testing rollback functionality...');
  
  try {
    // Simulate a staged transfer that needs to be rolled back
    const stagedTransferId = 'test_staged_' + Date.now();
    const sessionId = 'test_session_' + Date.now();
    const tokenUid = 'test_token_123';
    
    console.log('1. Creating a mock staged transfer...');
    
    // Create a mock staged transfer document
    await db.collection('staged_transfers').doc(stagedTransferId).set({
      id: stagedTransferId,
      session_id: sessionId,
      token_uid: tokenUid,
      from_user_id: 'alice',
      to_user_id: 'bob',
      original_token_state: {
        current_owner_id: 'alice',
        previous_owners: [],
        key_hash: 'original_key_hash_123',
      },
      new_token_state: {
        current_owner_id: 'bob',
        previous_owners: ['alice'],
        key_hash: 'new_key_hash_456',
        last_transfer_at: admin.firestore.Timestamp.now(),
      },
      status: 'staged',
      created_at: admin.firestore.Timestamp.now(),
      expires_at: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 10 * 60 * 1000) // 10 minutes from now
      ),
    });
    
    // Create a mock session with staged status
    await db.collection('transfer_sessions').doc(sessionId).set({
      session_id: sessionId,
      token_uid: tokenUid,
      from_user_id: 'alice',
      to_user_id: 'bob',
      status: 'staged',
      staged_transfer_id: stagedTransferId,
      created_at: admin.firestore.Timestamp.now(),
      expires_at: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 5 * 60 * 1000) // 5 minutes from now
      ),
    });
    
    console.log('2. Simulating rollback due to NFC write failure...');
    
    // Simulate the rollback transaction (this would normally be called via Cloud Function)
    const rollbackResult = await db.runTransaction(async (transaction) => {
      const stagedTransferRef = db.collection('staged_transfers').doc(stagedTransferId);
      const stagedTransferDoc = await transaction.get(stagedTransferRef);
      
      if (!stagedTransferDoc.exists) {
        throw new Error('Staged transfer not found');
      }
      
      const stagedTransfer = stagedTransferDoc.data();
      
      if (stagedTransfer.status !== 'staged') {
        throw new Error(`Cannot rollback transfer with status: ${stagedTransfer.status}`);
      }
      
      // Restore session status to pending to allow retry
      const sessionRef = db.collection('transfer_sessions').doc(stagedTransfer.session_id);
      transaction.update(sessionRef, { 
        status: 'pending',
        staged_transfer_id: admin.firestore.FieldValue.delete()
      });
      
      // Mark staged transfer as rolled back
      transaction.update(stagedTransferRef, { 
        status: 'rolled_back',
        rolled_back_at: admin.firestore.Timestamp.now(),
        rollback_reason: 'NFC write failed - test scenario'
      });
      
      // Log rollback event for audit
      const rollbackLogRef = db.collection('rollback_logs').doc();
      transaction.set(rollbackLogRef, {
        staged_transfer_id: stagedTransferId,
        token_uid: stagedTransfer.token_uid,
        from_user_id: stagedTransfer.from_user_id,
        to_user_id: stagedTransfer.to_user_id,
        reason: 'NFC write failed - test scenario',
        rolled_back_by: 'test_script',
        rolled_back_at: admin.firestore.Timestamp.now(),
      });
      
      return {
        success: true,
        message: `Transfer ${stagedTransferId} rolled back successfully`
      };
    });
    
    console.log('3. Verifying rollback results...');
    
    // Verify the rollback worked
    const updatedStagedTransfer = await db.collection('staged_transfers').doc(stagedTransferId).get();
    const updatedSession = await db.collection('transfer_sessions').doc(sessionId).get();
    
    const stagedData = updatedStagedTransfer.data();
    const sessionData = updatedSession.data();
    
    console.log('Staged transfer status:', stagedData?.status);
    console.log('Session status:', sessionData?.status);
    console.log('Session staged_transfer_id field:', sessionData?.staged_transfer_id);
    
    // Check rollback log was created
    const rollbackLogs = await db.collection('rollback_logs')
      .where('staged_transfer_id', '==', stagedTransferId)
      .get();
    
    console.log('Rollback logs created:', rollbackLogs.size);
    
    if (stagedData?.status === 'rolled_back' && 
        sessionData?.status === 'pending' && 
        !sessionData?.staged_transfer_id &&
        rollbackLogs.size > 0) {
      console.log('✅ ROLLBACK TEST PASSED: All changes successfully rolled back!');
    } else {
      console.log('❌ ROLLBACK TEST FAILED: Rollback did not work as expected');
    }
    
    console.log('4. Cleanup - removing test data...');
    
    // Clean up test data
    await db.collection('staged_transfers').doc(stagedTransferId).delete();
    await db.collection('transfer_sessions').doc(sessionId).delete();
    
    // Clean up rollback logs
    const rollbackLogDocs = await rollbackLogs;
    const batch = db.batch();
    rollbackLogDocs.forEach(doc => {
      batch.delete(doc.ref);
    });
    await batch.commit();
    
    console.log('Test completed and cleanup finished.');
    
  } catch (error) {
    console.error('❌ Test failed with error:', error);
  } finally {
    process.exit(0);
  }
}

// Run the test
testRollbackScenario();