import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

export const createSellerVerificationSession = functions.https.onCall(async (data, context) => {
  // Validate authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { token_id, listing_id, payment_intent_id, amount, buyer_id } = data;

  // Validate inputs
  if (!token_id || !listing_id || !payment_intent_id || !amount || !buyer_id) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
  }

  try {
    // Get the listing to verify seller
    const listingDoc = await db.collection('marketplace_listings').doc(listing_id).get();
    if (!listingDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Listing not found');
    }

    const listing = listingDoc.data()!;
    const sellerId = listing.sellerId;

    // Verify the token exists and is owned by the seller
    const tokenDoc = await db.collection('tokens').doc(token_id).get();
    if (!tokenDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Token not found');
    }

    const token = tokenDoc.data()!;
    if (token.current_owner_id !== sellerId) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Seller is not the current owner of this token'
      );
    }

    // Create verification session (30 days from now)
    const now = new Date();
    const expiresAt = new Date(now.getTime() + (30 * 24 * 60 * 60 * 1000)); // 30 days

    const sessionId = `verification_${payment_intent_id}_${Date.now()}`;

    const sessionData = {
      session_id: sessionId,
      token_id,
      seller_id: sellerId,
      buyer_id,
      listing_id,
      payment_intent_id,
      amount,
      created_at: now.toISOString(),
      expires_at: expiresAt.toISOString(),
      status: 'pending_nfc_scan',
      nfc_verified_at: null,
      completed_at: null,
      metadata: {
        listing_title: listing.title || 'SwapDot',
        listing_price: listing.price,
        platform_fee: Math.round(amount * 0.05), // 5% platform fee
      },
    };

    // Store verification session
    await db.collection('seller_verification_sessions').doc(sessionId).set(sessionData);

    // Update listing status to indicate payment received
    await db.collection('marketplace_listings').doc(listing_id).update({
      status: 'payment_received',
      verification_session_id: sessionId,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Log the event
    await db.collection('events').add({
      type: 'seller_verification_session_created',
      token_uid: token_id,
      seller_id: sellerId,
      buyer_id,
      listing_id,
      session_id: sessionId,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: {
        amount,
        payment_intent_id,
        expires_at: expiresAt.toISOString(),
      },
    });

    return sessionData;
  } catch (error) {
    console.error('Error creating seller verification session:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
      'internal',
      'Failed to create seller verification session'
    );
  }
});

export const verifySellerOwnership = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { session_id, token_id, nfc_data } = data;

  if (!session_id || !token_id || !nfc_data) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
  }

  try {
    return await db.runTransaction(async (transaction) => {
      // Get verification session
      const sessionRef = db.collection('seller_verification_sessions').doc(session_id);
      const sessionDoc = await transaction.get(sessionRef);

      if (!sessionDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Verification session not found');
      }

      const session = sessionDoc.data()!;

      // Verify user is the seller
      if (session.seller_id !== context.auth!.uid) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Only the seller can verify ownership'
        );
      }

      // Check if session is still valid
      if (session.status !== 'pending_nfc_scan') {
        throw new functions.https.HttpsError('failed-precondition', `Session status is ${session.status}, cannot verify`);
      }

      // Check if session has expired
      const now = new Date();
      const expiresAt = new Date(session.expires_at);
      if (now > expiresAt) {
        throw new functions.https.HttpsError('failed-precondition', 'Verification session has expired');
      }

      // Verify token ownership in Firebase
      const tokenRef = db.collection('tokens').doc(token_id);
      const tokenDoc = await transaction.get(tokenRef);

      if (!tokenDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Token not found');
      }

      const token = tokenDoc.data()!;
      if (token.current_owner_id !== session.seller_id) {
        throw new functions.https.HttpsError('failed-precondition', 'Seller is no longer the owner of this token');
      }

      // Validate NFC data
      if (nfc_data.token_uid !== token_id) {
        throw new functions.https.HttpsError('invalid-argument', 'NFC scan does not match the token being sold');
      }

      // Update session status
      const verifiedAt = now.toISOString();
      transaction.update(sessionRef, {
        status: 'nfc_verified',
        nfc_verified_at: verifiedAt,
        nfc_verification_data: nfc_data,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Log the verification event
      const eventRef = db.collection('events').doc();
      transaction.set(eventRef, {
        type: 'seller_ownership_verified',
        token_uid: token_id,
        seller_id: session.seller_id,
        buyer_id: session.buyer_id,
        session_id,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          verification_method: 'nfc_scan',
          verified_at: verifiedAt,
          nfc_data: nfc_data,
        },
      });

      return {
        ...session,
        status: 'nfc_verified',
        nfc_verified_at: verifiedAt,
        nfc_verification_data: nfc_data,
      };
    });
  } catch (error) {
    console.error('Error verifying seller ownership:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError('internal', 'Failed to verify seller ownership');
  }
});

export const completeSellerVerifiedTransaction = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { session_id } = data;

  if (!session_id) {
    throw new functions.https.HttpsError('invalid-argument', 'Session ID required');
  }

  try {
    return await db.runTransaction(async (transaction) => {
      // Get verification session
      const sessionRef = db.collection('seller_verification_sessions').doc(session_id);
      const sessionDoc = await transaction.get(sessionRef);

      if (!sessionDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Verification session not found');
      }

      const session = sessionDoc.data()!;

      // Verify user is the buyer (only buyer can trigger final ownership transfer)
      if (session.buyer_id !== context.auth!.uid) {
        throw new functions.https.HttpsError('permission-denied', 'Only the buyer can complete the transaction');
      }

      // Check session status
      if (session.status !== 'nfc_verified') {
        throw new functions.https.HttpsError('failed-precondition', `Cannot complete transaction. Session status is ${session.status}`);
      }

      // Check if session has expired
      const now = new Date();
      const expiresAt = new Date(session.expires_at);
      if (now > expiresAt) {
        throw new functions.https.HttpsError('failed-precondition', 'Verification session has expired');
      }

      // Get token and listing
      const tokenRef = db.collection('tokens').doc(session.token_id);
      const tokenDoc = await transaction.get(tokenRef);

      if (!tokenDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Token not found');
      }

      const token = tokenDoc.data()!;

      // Verify seller still owns the token
      if (token.current_owner_id !== session.seller_id) {
        throw new functions.https.HttpsError('failed-precondition', 'Token ownership has changed');
      }

      const listingRef = db.collection('marketplace_listings').doc(session.listing_id);
      const listingDoc = await transaction.get(listingRef);

      if (!listingDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Listing not found');
      }

      // Transfer token ownership
      const updatedPreviousOwners = [...token.previous_owners];
      if (updatedPreviousOwners.length === 0 ||
          updatedPreviousOwners[updatedPreviousOwners.length - 1] !== token.current_owner_id) {
        updatedPreviousOwners.push(token.current_owner_id);
      }

      // Update token ownership
      transaction.update(tokenRef, {
        current_owner_id: session.buyer_id,
        previous_owners: updatedPreviousOwners,
        last_transfer_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update listing status
      transaction.update(listingRef, {
        status: 'sold',
        sold_at: admin.firestore.FieldValue.serverTimestamp(),
        buyer_id: session.buyer_id,
      });

      // Complete verification session
      const completedAt = now.toISOString();
      transaction.update(sessionRef, {
        status: 'completed',
        completed_at: completedAt,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Create marketplace transaction record
      const marketplaceTransactionRef = db.collection('marketplace_transactions').doc();
      transaction.set(marketplaceTransactionRef, {
        id: marketplaceTransactionRef.id,
        listing_id: session.listing_id,
        token_id: session.token_id,
        seller_id: session.seller_id,
        buyer_id: session.buyer_id,
        amount: session.amount,
        platform_fee: session.metadata?.platform_fee || Math.round(session.amount * 0.05),
        currency: 'usd',
        payment_intent_id: session.payment_intent_id,
        verification_session_id: session_id,
        status: 'completed',
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        completed_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Log the completion event
      const eventRef = db.collection('events').doc();
      transaction.set(eventRef, {
        type: 'marketplace_transaction_completed',
        token_uid: session.token_id,
        from_user_id: session.seller_id,
        to_user_id: session.buyer_id,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          listing_id: session.listing_id,
          transaction_id: marketplaceTransactionRef.id,
          verification_session_id: session_id,
          amount: session.amount,
          platform_fee: session.metadata?.platform_fee || Math.round(session.amount * 0.05),
          completed_at: completedAt,
        },
      });

      return {
        transaction_id: marketplaceTransactionRef.id,
        status: 'completed',
        token_id: session.token_id,
        seller_id: session.seller_id,
        buyer_id: session.buyer_id,
        amount: session.amount,
        completed_at: completedAt,
      };
    });
  } catch (error) {
    console.error('Error completing seller verified transaction:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError('internal', 'Failed to complete transaction');
  }
});

export const cancelSellerVerificationSession = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { session_id, reason } = data;

  if (!session_id || !reason) {
    throw new functions.https.HttpsError('invalid-argument', 'Session ID and reason required');
  }

  try {
    return await db.runTransaction(async (transaction) => {
      // Get verification session
      const sessionRef = db.collection('seller_verification_sessions').doc(session_id);
      const sessionDoc = await transaction.get(sessionRef);

      if (!sessionDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Verification session not found');
      }

      const session = sessionDoc.data()!;

      // Verify user is authorized (seller or admin)
      const isAdmin = context.auth!.token.admin === true;
      if (session.seller_id !== context.auth!.uid && !isAdmin) {
        throw new functions.https.HttpsError('permission-denied', 'Only the seller or admin can cancel the session');
      }

      // Check if session can be cancelled
      if (session.status === 'completed' || session.status === 'cancelled') {
        throw new functions.https.HttpsError('failed-precondition', `Cannot cancel session with status ${session.status}`);
      }

      // Cancel verification session
      const cancelledAt = new Date().toISOString();
      transaction.update(sessionRef, {
        status: 'cancelled',
        cancelled_at: cancelledAt,
        cancellation_reason: reason,
        cancelled_by: context.auth!.uid,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update listing status
      const listingRef = db.collection('marketplace_listings').doc(session.listing_id);
      transaction.update(listingRef, {
        status: 'cancelled',
        cancelled_at: admin.firestore.FieldValue.serverTimestamp(),
        cancellation_reason: reason,
      });

      // Log the cancellation event
      const eventRef = db.collection('events').doc();
      transaction.set(eventRef, {
        type: 'seller_verification_cancelled',
        token_uid: session.token_id,
        seller_id: session.seller_id,
        buyer_id: session.buyer_id,
        session_id,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          reason,
          cancelled_by: context.auth!.uid,
          cancelled_at: cancelledAt,
          original_amount: session.amount,
        },
      });

      return {
        success: true,
        session_id,
        status: 'cancelled',
        reason,
        cancelled_at: cancelledAt,
      };
    });
  } catch (error) {
    console.error('Error cancelling seller verification session:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError('internal', 'Failed to cancel verification session');
  }
});

// Scheduled function to handle expired verification sessions
export const cleanupExpiredVerificationSessions = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async () => {
    const now = new Date();

    try {
      // Find expired sessions that are still pending
      const expiredSessions = await db
        .collection('seller_verification_sessions')
        .where('status', 'in', ['pending_nfc_scan', 'nfc_verified'])
        .where('expires_at', '<=', now.toISOString())
        .get();

      console.log(`Found ${expiredSessions.size} expired verification sessions`);

      // Process each expired session
      const batch = db.batch();
      const expiredSessionIds: string[] = [];

      for (const doc of expiredSessions.docs) {
        const session = doc.data();
        expiredSessionIds.push(session.session_id);

        // Update session status to expired
        batch.update(doc.ref, {
          status: 'expired',
          expired_at: now.toISOString(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Update associated listing
        const listingRef = db.collection('marketplace_listings').doc(session.listing_id);
        batch.update(listingRef, {
          status: 'expired',
          expired_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Log the expiration event
        const eventRef = db.collection('events').doc();
        batch.set(eventRef, {
          type: 'seller_verification_expired',
          token_uid: session.token_id,
          seller_id: session.seller_id,
          buyer_id: session.buyer_id,
          session_id: session.session_id,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          metadata: {
            original_amount: session.amount,
            expired_at: now.toISOString(),
            days_elapsed: 30,
          },
        });
      }

      await batch.commit();

      console.log(`Successfully processed ${expiredSessionIds.length} expired sessions:`, expiredSessionIds);

      return { processed: expiredSessionIds.length, session_ids: expiredSessionIds };
    } catch (error) {
      console.error('Error cleaning up expired verification sessions:', error);
      throw error;
    }
  });
