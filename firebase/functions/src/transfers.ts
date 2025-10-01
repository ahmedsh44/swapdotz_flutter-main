import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

/**
 * SECURITY: Validates that ownership history can only be appended to, never modified
 * This ensures immutable ownership records with only forward-only changes
 */
function validateOwnershipHistoryAppendOnly(
  existingOwners: string[],
  newOwners: string[],
  newCurrentOwner: string
): boolean {
  // If no existing owners, any new array is valid for first-time registration
  if (existingOwners.length === 0) {
    return true;
  }

  // New array must be longer than or equal to existing (append-only)
  if (newOwners.length < existingOwners.length) {
    console.error('SECURITY VIOLATION: Ownership history shortened', {
      existingLength: existingOwners.length,
      newLength: newOwners.length,
    });
    return false;
  }

  // All existing entries must remain unchanged in their original positions
  for (let i = 0; i < existingOwners.length; i++) {
    if (existingOwners[i] !== newOwners[i]) {
      console.error('SECURITY VIOLATION: Ownership history modified at position', {
        position: i,
        existing: existingOwners[i],
        new: newOwners[i],
      });
      return false;
    }
  }

  // If length increased, validate that only one entry was added
  if (newOwners.length > existingOwners.length) {
    const addedEntries = newOwners.slice(existingOwners.length);

    // Should only add one entry and it should be different from the last existing owner
    if (addedEntries.length !== 1) {
      console.error('SECURITY VIOLATION: Multiple owners added at once', {
        addedEntries,
      });
      return false;
    }

    // The added entry should be a valid user ID (not the current new owner)
    const addedOwner = addedEntries[0];
    if (addedOwner === newCurrentOwner) {
      console.error('SECURITY VIOLATION: Cannot add current owner to previous owners', {
        addedOwner,
        newCurrentOwner,
      });
      return false;
    }
  }

  return true;
}

type TokenDoc = {
  ownerUid: string;
  counter: number; // n
  chainHead?: string; // optional hash head (bytes encoded as base64 string)
  status?: 'OK' | 'PENDING' | 'INCONSISTENT';
  tagUid?: string; // optional NFC UID for best-effort check

  // Legacy fields for backward compatibility
  uid?: string;
  current_owner_id?: string;
  previous_owners?: string[];
  key_hash?: string;
  created_at?: admin.firestore.Timestamp;
  last_transfer_at?: admin.firestore.Timestamp;
  metadata?: any;
};

type PendingDoc = {
  fromUid: string;
  toUid: string | null; // bound at finalize
  nNext: number; // counter + 1
  hNext?: string; // optional next hash head (base64)
  expiresAt: admin.firestore.Timestamp;
  state: 'OPEN' | 'COMMITTED' | 'EXPIRED' | 'CANCELED';
  createdAt: admin.firestore.FieldValue;
};

// Removed unused function nowTs()

function ttlMinutes(m: number) {
  const ms = m * 60 * 1000;
  return admin.firestore.Timestamp.fromMillis(Date.now() + ms);
}

/**
 * Initiate a secure transfer: owner creates a single OPEN pending for this token.
 * Body: { tokenId: string }
 */
export const initiateSecureTransfer = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required.');
  }
  const tokenId = String(data?.tokenId || '').trim();
  if (!tokenId) {
    throw new functions.https.HttpsError('invalid-argument', 'tokenId required.');
  }

  const tokenRef = db.collection('tokens').doc(tokenId);
  const pendingRef = db.collection('pendingTransfers').doc(tokenId);

  // CRITICAL: Query for ALL legacy transfer sessions BEFORE the transaction
  // These must be cleaned up to prevent blocking future transfers
  const sessionQuery = await db.collection('transfer_sessions')
    .where('token_uid', '==', tokenId)
    .where('status', '==', 'pending')
    .get();
  
  console.log(`[initiateSecureTransfer] Found ${sessionQuery.docs.length} legacy sessions for token ${tokenId}`);
  const legacySessionRefs = sessionQuery.docs.map(doc => doc.ref);

  return await db.runTransaction(async (tx) => {
    const tokenSnap = await tx.get(tokenRef);
    if (!tokenSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Token not found.');
    }
    const token = tokenSnap.data() as TokenDoc;

    // Support both new and legacy token formats
    const currentOwner = token.ownerUid || token.current_owner_id;
    if (currentOwner !== uid) {
      throw new functions.https.HttpsError('permission-denied', 'Only current owner can initiate.');
    }

    const pendingSnap = await tx.get(pendingRef);
    if (pendingSnap.exists) {
      const pending = pendingSnap.data() as PendingDoc;
      
      // Check the state of the existing pending transfer
      if (pending.state === 'COMMITTED') {
        // This shouldn't happen - if transfer was committed, ownership should have changed
        throw new functions.https.HttpsError('failed-precondition', 
          'Transfer was already completed. Token ownership records may be out of sync.');
      }
      
      if (pending.state === 'OPEN' && pending.expiresAt.toMillis() > Date.now()) {
        // There's an active transfer that hasn't expired
        // Only allow the owner to overwrite their own pending transfer
        if (pending.fromUid !== uid) {
          throw new functions.https.HttpsError('failed-precondition', 
            'Another user has an active transfer for this token.');
        }
        // Owner can overwrite their own pending transfer
        console.log(`Overwriting existing OPEN transfer for token ${tokenId}`);
      }
      
      // For EXPIRED or CANCELED states, or owner overwriting their own OPEN transfer,
      // we'll proceed to create a new one
    }

    const nNext = (token.counter ?? 0) + 1;
    const expiresAt = ttlMinutes(10);

    const pending: PendingDoc = {
      fromUid: uid,
      toUid: null,
      nNext,
      // hNext is optional; compute on backend that ties to your hash chain if you use one
      expiresAt,
      state: 'OPEN',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    tx.set(pendingRef, pending, { merge: false });

    // Clean up any legacy transfer sessions when creating secure transfer
    legacySessionRefs.forEach(sessionRef => {
      tx.update(sessionRef, { 
        status: 'cancelled',
        cancelled_reason: 'Superseded by secure transfer initiation',
        cancelled_at: admin.firestore.FieldValue.serverTimestamp()
      });
    });

    // Optionally mark token as PENDING for UX (server-owned field)
    tx.update(tokenRef, { status: 'PENDING' });

    console.log(`Initiated secure transfer for token ${tokenId}, cleaned ${legacySessionRefs.length} legacy sessions`);

    return { ok: true, tokenId, nNext, expiresAt: expiresAt.toMillis() };
  });
});

/**
 * Finalize a secure transfer: receiver claims pending and ownership flips atomically.
 * Body: { tokenId: string, tagUid?: string }
 * The caller becomes the new owner (toUid).
 */
export const finalizeSecureTransfer = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required.');
  }
  const tokenId = String(data?.tokenId || '').trim();
  if (!tokenId) {
    throw new functions.https.HttpsError('invalid-argument', 'tokenId required.');
  }
  const tagUidParam = data?.tagUid ? String(data.tagUid) : undefined;

  const tokenRef = db.collection('tokens').doc(tokenId);
  const pendingRef = db.collection('pendingTransfers').doc(tokenId);
  const eventsRef = db.collection('events').doc(); // append-only event log

  // CRITICAL: Query for ALL legacy transfer sessions BEFORE the transaction
  // These MUST be cleaned up when ownership changes to prevent blocking
  const sessionQuery = await db.collection('transfer_sessions')
    .where('token_uid', '==', tokenId)
    .where('status', '==', 'pending')
    .get();
  
  console.log(`[finalizeSecureTransfer] Found ${sessionQuery.docs.length} legacy sessions to clean up for token ${tokenId}`);
  const legacySessionRefs = sessionQuery.docs.map(doc => doc.ref);

  return await db.runTransaction(async (tx) => {
    const [tokenSnap, pendingSnap] = await Promise.all([
      tx.get(tokenRef),
      tx.get(pendingRef),
    ]);

    if (!tokenSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Token not found.');
    }
    const token = tokenSnap.data() as TokenDoc;

    if (!pendingSnap.exists) {
      throw new functions.https.HttpsError('failed-precondition', 'No pending transfer.');
    }
    const pending = pendingSnap.data() as PendingDoc;

    // Handle different states
    if (pending.state === 'COMMITTED') {
      // This is a bug - COMMITTED transfers should have been deleted
      // Clean it up now since the transfer is already complete
      console.log('[finalizeSecureTransfer] Found COMMITTED transfer that should have been deleted - cleaning up');
      tx.delete(pendingRef);
      
      // Return success since the transfer was already completed
      return {
        ok: true,
        tokenId,
        newOwnerUid: pending.toUid || uid,
        counter: token.counter || 0,
        message: 'Transfer was already completed - cleaned up stale record'
      };
    }
    
    if (pending.state !== 'OPEN') {
      throw new functions.https.HttpsError('failed-precondition', `Pending transfer is ${pending.state}, expected OPEN.`);
    }

    // Expiry check
    if (pending.expiresAt.toMillis() <= Date.now()) {
      tx.update(pendingRef, { state: 'EXPIRED' });
      // Clear token status back to OK
      tx.update(tokenRef, { status: 'OK' });
      throw new functions.https.HttpsError('deadline-exceeded', 'Pending transfer expired.');
    }

    // Enforce "no intermediates": fromUid must equal current owner in ledger.
    const currentOwner = token.ownerUid || token.current_owner_id;
    if (pending.fromUid !== currentOwner) {
      throw new functions.https.HttpsError('aborted', 'Owner changed; pending is invalid.');
    }

    // Optional NFC sanity check (best-effort): if you store tagUid on token,
    // require client to provide the same UID they just tapped.
    if (token.tagUid && tagUidParam && token.tagUid !== tagUidParam) {
      throw new functions.https.HttpsError('failed-precondition', 'Tag UID mismatch.');
    }

    // Bind receiver if not bound; otherwise ensure same receiver
    const toUid = pending.toUid ?? uid;
    if (pending.toUid && pending.toUid !== uid) {
      throw new functions.https.HttpsError('permission-denied',
        'This pending is bound to a different receiver.');
    }

    // SECURITY: Update both new and legacy ownership fields atomically
    // This ensures backward compatibility while enforcing the new security model
    const nNext = pending.nNext;
    const previousOwners = token.previous_owners || [];
    const shouldAppendCurrentOwner = currentOwner &&
      !previousOwners.includes(currentOwner);

    // SECURITY: Validate ownership history using append-only validation
    const proposedPreviousOwners = shouldAppendCurrentOwner ?
      [...previousOwners, currentOwner] : previousOwners;

    if (!validateOwnershipHistoryAppendOnly(
      previousOwners, proposedPreviousOwners, toUid)) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Invalid ownership history modification detected in secure transfer');
    }

    const tokenUpdate: any = {
      ownerUid: toUid,
      counter: nNext,
      status: 'OK',
      updated_at: admin.firestore.FieldValue.serverTimestamp(),

      // Legacy fields for backward compatibility
      current_owner_id: toUid,
      last_transfer_at: admin.firestore.FieldValue.serverTimestamp(),
      previous_owners: proposedPreviousOwners,
    };

    // chainHead: pending.hNext ?? token.chainHead, // uncomment when you compute hNext
    tx.update(tokenRef, tokenUpdate);

    // SECURITY: Delete ALL pending transfer records for this token
    // 1. Delete the secure transfer pending document
    tx.delete(pendingRef);
    
    // 2. Clean up any legacy transfer_sessions for this token
    legacySessionRefs.forEach(sessionRef => {
      // Mark legacy sessions as cancelled
      tx.update(sessionRef, { 
        status: 'cancelled',
        cancelled_reason: 'Superseded by secure transfer completion',
        cancelled_at: admin.firestore.FieldValue.serverTimestamp()
      });
    });

    // Append event (optional but recommended for audit)
    tx.set(eventsRef, {
      tokenId,
      fromOwner: currentOwner,
      toOwner: toUid,
      counter: nNext,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      type: 'TRANSFER',
      legacy_sessions_cleaned: legacySessionRefs.length,
    }, { merge: false });

    return { ok: true, tokenId, newOwnerUid: toUid, counter: nNext };
  });
});

/**
 * Cleanup expired pending transfers (scheduled function)
 */
export const cleanupExpiredPendings = functions.pubsub
  .schedule('every 15 minutes')
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const batch = db.batch();

    // Find expired pending transfers
    const expiredQuery = await db.collection('pendingTransfers')
      .where('state', '==', 'OPEN')
      .where('expiresAt', '<=', now)
      .limit(100) // Process in batches
      .get();

    console.log(`Found ${expiredQuery.size} expired pending transfers`);

    expiredQuery.docs.forEach((doc) => {
      const tokenId = doc.id;

      // Mark pending as expired
      batch.update(doc.ref, { state: 'EXPIRED' });

      // Reset token status to OK
      const tokenRef = db.collection('tokens').doc(tokenId);
      batch.update(tokenRef, { status: 'OK' });
    });

    if (expiredQuery.size > 0) {
      await batch.commit();
      console.log(`Cleaned up ${expiredQuery.size} expired pending transfers`);
    }

    return null;
  });

/**
 * Manual cleanup function for stale COMMITTED transfers
 * Note: The autoCleanupCommittedTransfers trigger handles this automatically,
 * but this function can be used for manual batch cleanup if needed.
 * 
 * This function will:
 * 1. Find all COMMITTED transfers
 * 2. Fix ownership if needed
 * 3. Delete the COMMITTED documents
 */
export const cleanupStaleCommittedTransfers = functions.https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated'
    );
  }

  console.log('[cleanupStaleCommittedTransfers] Starting manual cleanup...');

  try {
    const pendingTransfersRef = admin.firestore().collection('pendingTransfers');
    const snapshot = await pendingTransfersRef.where('state', '==', 'COMMITTED').get();

    if (snapshot.empty) {
      console.log('[cleanupStaleCommittedTransfers] No stale COMMITTED transfers found');
      return { 
        ok: true, 
        message: 'No stale COMMITTED transfers found',
        count: 0,
        ownershipFixed: 0
      };
    }

    console.log(`[cleanupStaleCommittedTransfers] Found ${snapshot.size} stale COMMITTED transfers`);

    const results = {
      deleted: [] as string[],
      ownershipFixed: [] as string[],
      errors: [] as string[]
    };

    // Process each COMMITTED transfer individually
    for (const doc of snapshot.docs) {
      const tokenId = doc.id;
      const transferData = doc.data() as PendingDoc;
      
      try {
        console.log(`[cleanupStaleCommittedTransfers] Processing token ${tokenId}`);
        
        // Check and fix ownership if needed
        const tokenDoc = await admin.firestore().collection('tokens').doc(tokenId).get();
        if (tokenDoc.exists) {
          const token = tokenDoc.data();
          const currentOwner = token?.ownerUid || token?.current_owner_id;
          
          if (transferData.toUid && currentOwner !== transferData.toUid) {
            console.log(`  - Fixing ownership: ${currentOwner} -> ${transferData.toUid}`);
            
            const previousOwners = token?.previous_owners || [];
            const updatedPreviousOwners = previousOwners.includes(transferData.fromUid) 
              ? previousOwners 
              : [...previousOwners, transferData.fromUid];
            
            await tokenDoc.ref.update({
              ownerUid: transferData.toUid,
              current_owner_id: transferData.toUid,
              counter: transferData.nNext || token?.counter || 0,
              status: 'OK',
              last_transfer_at: admin.firestore.FieldValue.serverTimestamp(),
              previous_owners: updatedPreviousOwners
            });
            
            results.ownershipFixed.push(tokenId);
          }
        }
        
        // Delete the COMMITTED transfer
        await doc.ref.delete();
        results.deleted.push(tokenId);
        console.log(`  - Deleted COMMITTED transfer for token ${tokenId}`);
        
      } catch (error) {
        console.error(`  - Error processing token ${tokenId}:`, error);
        results.errors.push(tokenId);
      }
    }

    console.log('[cleanupStaleCommittedTransfers] Cleanup complete');
    console.log(`  - Deleted: ${results.deleted.length} transfers`);
    console.log(`  - Fixed ownership: ${results.ownershipFixed.length} tokens`);
    console.log(`  - Errors: ${results.errors.length}`);
    
    return { 
      ok: true, 
      message: `Processed ${snapshot.size} COMMITTED transfers`,
      count: snapshot.size,
      deleted: results.deleted.length,
      ownershipFixed: results.ownershipFixed.length,
      errors: results.errors.length,
      tokenIds: results.deleted
    };

  } catch (error: any) {
    console.error('[cleanupStaleCommittedTransfers] Error:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to cleanup stale transfers',
      error.message
    );
  }
});

/**
 * Firestore Trigger: Ensure ownership is correct for COMMITTED transfers, then clean them up
 * 
 * PRIMARY PURPOSE: Ensure token ownership matches the COMMITTED transfer
 * SECONDARY PURPOSE: Delete the COMMITTED transfer document (which shouldn't exist)
 * 
 * This handles the edge case where a transfer gets set to COMMITTED instead of deleted
 * (This shouldn't happen with the new code, but handles legacy/buggy cases)
 */
export const autoCleanupCommittedTransfers = functions.firestore
  .document('pendingTransfers/{tokenId}')
  .onWrite(async (change, context) => {
    const tokenId = context.params.tokenId;
    
    // If document was deleted, nothing to do
    if (!change.after.exists) {
      return null;
    }
    
    const data = change.after.data() as PendingDoc;
    
    // Only process COMMITTED transfers
    if (data.state !== 'COMMITTED') {
      return null;
    }
    
    console.log(`[autoCleanupCommittedTransfers] COMMITTED transfer detected for token ${tokenId}`);
    console.log(`  Transfer was from: ${data.fromUid} to: ${data.toUid}`);
    console.log(`  PRIORITY 1: Ensure ownership is correctly set`);
    console.log(`  PRIORITY 2: Delete this COMMITTED transfer document`);
    
    try {
      // STEP 1: ENSURE CORRECT OWNERSHIP (Critical!)
      const tokenDoc = await db.collection('tokens').doc(tokenId).get();
      
      if (!tokenDoc.exists) {
        console.error(`[autoCleanupCommittedTransfers] CRITICAL: Token ${tokenId} not found!`);
        console.error(`  Transfer claims to be from ${data.fromUid} to ${data.toUid}`);
        console.error(`  But the token doesn't exist in the database`);
        // Delete the orphaned pendingTransfer
        await change.after.ref.delete();
        return null;
      }
      
      const token = tokenDoc.data();
      const currentOwner = token?.ownerUid || token?.current_owner_id;
      const previousOwners = token?.previous_owners || [];
      
      // CRITICAL: Check if ownership matches the COMMITTED transfer
      if (data.toUid && currentOwner !== data.toUid) {
        console.error(`[autoCleanupCommittedTransfers] CRITICAL OWNERSHIP MISMATCH!`);
        console.error(`  COMMITTED transfer says owner should be: ${data.toUid}`);
        console.error(`  But token document says owner is: ${currentOwner}`);
        console.error(`  This is a SECURITY ISSUE - fixing ownership now...`);
        
        // Build the correct ownership history
        const updatedPreviousOwners = previousOwners.includes(data.fromUid) 
          ? previousOwners 
          : [...previousOwners, data.fromUid];
        
        // FIX THE OWNERSHIP to match what the COMMITTED transfer says
        const ownershipUpdate = {
          // Set both ownership fields for compatibility
          ownerUid: data.toUid,
          current_owner_id: data.toUid,
          
          // Update the counter if provided
          counter: data.nNext || token?.counter || 0,
          
          // Clear any error status
          status: 'OK',
          
          // Update transfer timestamp
          last_transfer_at: admin.firestore.FieldValue.serverTimestamp(),
          
          // Update ownership history
          previous_owners: updatedPreviousOwners
        };
        
        await tokenDoc.ref.update(ownershipUpdate);
        
        console.log(`[autoCleanupCommittedTransfers] ✅ OWNERSHIP CORRECTED`);
        console.log(`  Token ${tokenId} now owned by ${data.toUid}`);
        console.log(`  Previous owner ${data.fromUid} added to history`);
      } else if (data.toUid && currentOwner === data.toUid) {
        console.log(`[autoCleanupCommittedTransfers] ✅ Ownership already correct`);
        console.log(`  Token ${tokenId} is correctly owned by ${data.toUid}`);
      } else if (!data.toUid) {
        console.warn(`[autoCleanupCommittedTransfers] WARNING: COMMITTED transfer has no toUid`);
        console.warn(`  This is unusual - the transfer was committed but no recipient specified`);
        console.warn(`  Current owner remains: ${currentOwner}`);
      }
      
      // STEP 2: DELETE THE COMMITTED TRANSFER (it shouldn't exist)
      await change.after.ref.delete();
      console.log(`[autoCleanupCommittedTransfers] ✅ Deleted COMMITTED transfer document`);
      console.log(`  COMMITTED transfers should be deleted, not kept`);
      console.log(`  This was likely from old code that set state to COMMITTED instead of deleting`);
      
      // STEP 3: LOG FOR AUDIT
      await db.collection('cleanup_logs').add({
        type: 'AUTO_CLEANUP_COMMITTED',
        tokenId: tokenId,
        fromUid: data.fromUid,
        toUid: data.toUid,
        previousOwner: currentOwner,
        newOwner: data.toUid || currentOwner,
        ownershipWasCorrected: data.toUid && currentOwner !== data.toUid,
        committedAt: data.createdAt,
        cleanedUpAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log(`[autoCleanupCommittedTransfers] ✅ Cleanup complete for token ${tokenId}`);
      
    } catch (error) {
      console.error(`[autoCleanupCommittedTransfers] ERROR during cleanup:`, error);
      
      // Even if there's an error, TRY to delete the COMMITTED transfer
      // because it should never exist
      try {
        await change.after.ref.delete();
        console.log(`[autoCleanupCommittedTransfers] Force deleted COMMITTED transfer despite error`);
      } catch (deleteError) {
        console.error(`[autoCleanupCommittedTransfers] CRITICAL: Could not delete COMMITTED transfer:`, deleteError);
        console.error(`  Manual intervention required for token ${tokenId}`);
      }
    }
    
    return null;
  });
