import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/seller_verification_session.dart';
import '../services/firebase_service.dart';
import '../services/nfc_service.dart';
import 'anti_spoofing_service.dart';

class SellerVerificationService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a seller verification session after payment is made
  static Future<SellerVerificationSession> createVerificationSession({
    required String tokenId,
    required String listingId,
    required String paymentIntentId,
    required double amount,
    required String buyerId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated');
      }

      final callable = _functions.httpsCallable('createSellerVerificationSession');
      final result = await callable.call({
        'token_id': tokenId,
        'listing_id': listingId,
        'payment_intent_id': paymentIntentId,
        'amount': amount,
        'buyer_id': buyerId,
      });

      return SellerVerificationSession.fromFirestore(result.data);
    } catch (e) {
      print('Error creating verification session: $e');
      throw e;
    }
  }

  /// Verify seller ownership by scanning the SwapDot with NFC
  static Future<SellerVerificationSession> verifyOwnershipWithNFC({
    required String sessionId,
    required String tokenId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated');
      }

      // Step 1: Initialize anti-spoofing protection
      await AntiSpoofingService.initialize();

      // Step 2: Perform secure NFC verification with anti-spoofing (no GPS needed for seller verification)
      print('🔍 Starting secure NFC verification for seller...');
      
      // FIXED: Use the correct method signature for secureNFCOperation
      await NFCService.secureNFCOperation(() async {
        return await NFCService.executeSecureOperation(
          operationType: 'seller_verification',
          parameters: {
            'session_id': sessionId,
            'expected_token_id': tokenId,
            'user_id': user.uid,
          },
          iosAlertMessage: 'Hold SwapDot near device to verify ownership',
        );
      });

      // Since secureNFCOperation doesn't return a SecureOperationResult,
      // we need to handle the verification differently
      
      // Step 3: Verify ownership in Firebase
      final token = await SwapDotzFirebaseService.getToken(tokenId);
      if (token == null) {
        throw Exception('Token not found in Firebase');
      }

      if (token.currentOwnerId != user.uid) {
        throw Exception('You are not the current owner of this SwapDot');
      }

      // Step 4: Update verification session via Cloud Function
      final callable = _functions.httpsCallable('verifySellerOwnership');
      final result = await callable.call({
        'session_id': sessionId,
        'token_id': tokenId,
        'nfc_data': {
          'token_uid': tokenId,
          'verified_at': DateTime.now().toIso8601String(),
          'verification_method': 'nfc_scan',
        },
      });

      return SellerVerificationSession.fromFirestore(result.data);
    } catch (e) {
      print('Error verifying seller ownership: $e');
      throw e;
    }
  }

  /// Complete the transaction and transfer ownership to buyer
  static Future<void> completeTransaction(String sessionId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated');
      }

      final callable = _functions.httpsCallable('completeSellerVerifiedTransaction');
      await callable.call({
        'session_id': sessionId,
      });
    } catch (e) {
      print('Error completing transaction: $e');
      throw e;
    }
  }

  /// Get seller verification session by ID
  static Future<SellerVerificationSession?> getVerificationSession(String sessionId) async {
    try {
      final doc = await _firestore
          .collection('seller_verification_sessions')
          .doc(sessionId)
          .get();

      if (!doc.exists) return null;

      return SellerVerificationSession.fromFirestore(doc.data()!);
    } catch (e) {
      print('Error getting verification session: $e');
      return null;
    }
  }

  /// Get all verification sessions for current user (as seller)
  static Stream<List<SellerVerificationSession>> getSellerVerificationSessions() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('seller_verification_sessions')
        .where('seller_id', isEqualTo: user.uid)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => SellerVerificationSession.fromFirestore(doc.data()))
          .toList();
    });
  }

  /// Get all verification sessions for current user (as buyer)
  static Stream<List<SellerVerificationSession>> getBuyerVerificationSessions() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('seller_verification_sessions')
        .where('buyer_id', isEqualTo: user.uid)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => SellerVerificationSession.fromFirestore(doc.data()))
          .toList();
    });
  }

  /// Get pending verification sessions (requiring NFC scan)
  static Stream<List<SellerVerificationSession>> getPendingVerificationSessions() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('seller_verification_sessions')
        .where('seller_id', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending_nfc_scan')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => SellerVerificationSession.fromFirestore(doc.data()))
          .where((session) => !session.isExpired) // Filter out expired sessions
          .toList();
    });
  }

  /// Cancel a verification session (refunds buyer)
  static Future<void> cancelVerificationSession(String sessionId, String reason) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated');
      }

      final callable = _functions.httpsCallable('cancelSellerVerificationSession');
      await callable.call({
        'session_id': sessionId,
        'reason': reason,
      });
    } catch (e) {
      print('Error cancelling verification session: $e');
      throw e;
    }
  }

  /// Check if seller has any pending verification sessions
  static Future<bool> hasPendingVerifications() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final snapshot = await _firestore
          .collection('seller_verification_sessions')
          .where('seller_id', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending_nfc_scan')
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking pending verifications: $e');
      return false;
    }
  }

  /// Get verification session for a specific listing (if exists)
  static Future<SellerVerificationSession?> getVerificationSessionForListing(String listingId) async {
    try {
      final snapshot = await _firestore
          .collection('seller_verification_sessions')
          .where('listing_id', isEqualTo: listingId)
          .orderBy('created_at', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      return SellerVerificationSession.fromFirestore(snapshot.docs.first.data());
    } catch (e) {
      print('Error getting verification session for listing: $e');
      return null;
    }
  }
}

class NFCVerificationResult {
  final bool success;
  final String? tokenUid;
  final String? error;
  final Map<String, dynamic>? metadata;

  NFCVerificationResult({
    required this.success,
    this.tokenUid,
    this.error,
    this.metadata,
  });

  factory NFCVerificationResult.success(String tokenUid, {Map<String, dynamic>? metadata}) {
    return NFCVerificationResult(
      success: true,
      tokenUid: tokenUid,
      metadata: metadata,
    );
  }

  factory NFCVerificationResult.failure(String error) {
    return NFCVerificationResult(
      success: false,
      error: error,
    );
  }
}