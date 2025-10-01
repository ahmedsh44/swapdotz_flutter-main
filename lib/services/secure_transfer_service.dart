import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for handling secure two-phase transfers
class SecureTransferService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Initiate a secure transfer (Phase 1)
  static Future<SecureTransferInitiateResponse> initiateTransfer({
    required String tokenId,
  }) async {
    try {
      final callable = _functions.httpsCallable('initiateTransfer');
      final result = await callable.call({
        'token_uid': tokenId,
      });

      return SecureTransferInitiateResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw SecureTransferException(
        code: e.code,
        message: e.message ?? 'Failed to initiate transfer',
        details: e.details,
      );
    }
  }

  /// Finalize a secure transfer (Phase 2)
  static Future<SecureTransferFinalizeResponse> finalizeTransfer({
    required String tokenId,
    String? tagUid,
  }) async {
    try {
      final callable = _functions.httpsCallable('completeTransfer');
      final result = await callable.call({
        'session_id': tokenId, // TODO: This should be sessionId not tokenId
        if (tagUid != null) 'tagUid': tagUid,
      });

      return SecureTransferFinalizeResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw SecureTransferException(
        code: e.code,
        message: e.message ?? 'Failed to finalize transfer',
        details: e.details,
      );
    }
  }

  /// Get current user ID
  static String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }

  /// Check if there's a pending transfer for a token
  /// ALWAYS fetches fresh data from server to avoid stale cache issues
  static Future<PendingTransfer?> getPendingTransfer(String tokenId) async {
    try {
      // CRITICAL: Force fresh read from server, not cache
      // This prevents seeing deleted transfers that are still cached
      final doc = await _firestore
          .collection('pendingTransfers')
          .doc(tokenId)
          .get(const GetOptions(source: Source.server));

      print('📊 PENDING TRANSFER CHECK: Token $tokenId');
      print('📊   - Document exists: ${doc.exists}');
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        print('📊   - State: ${data['state']}');
        print('📊   - From: ${data['fromUid']}');
        print('📊   - Expires: ${data['expiresAt']}');
      }

      if (!doc.exists) return null;
      return PendingTransfer.fromFirestore(doc);
    } catch (e) {
      print('❌ Error fetching pending transfer (likely offline): $e');
      // If we can't reach the server, try cache as fallback
      try {
        final doc = await _firestore
            .collection('pendingTransfers')
            .doc(tokenId)
            .get(const GetOptions(source: Source.cache));
        
        if (!doc.exists) return null;
        print('⚠️ Using CACHED pending transfer data - may be stale!');
        return PendingTransfer.fromFirestore(doc);
      } catch (cacheError) {
        print('❌ Cache also failed: $cacheError');
        return null;
      }
    }
  }
}

/// Response from initiating a secure transfer
class SecureTransferInitiateResponse {
  final bool ok;
  final String tokenId;
  final int nNext;
  final int expiresAt;

  SecureTransferInitiateResponse({
    required this.ok,
    required this.tokenId,
    required this.nNext,
    required this.expiresAt,
  });

  factory SecureTransferInitiateResponse.fromMap(Map<String, dynamic> data) {
    return SecureTransferInitiateResponse(
      ok: data['ok'] ?? false,
      tokenId: data['tokenId'] ?? '',
      nNext: data['nNext'] ?? 0,
      expiresAt: data['expiresAt'] ?? 0,
    );
  }

  DateTime get expiryDateTime => DateTime.fromMillisecondsSinceEpoch(expiresAt);
}

/// Response from finalizing a secure transfer
class SecureTransferFinalizeResponse {
  final bool ok;
  final String tokenId;
  final String newOwnerUid;
  final int counter;

  SecureTransferFinalizeResponse({
    required this.ok,
    required this.tokenId,
    required this.newOwnerUid,
    required this.counter,
  });

  factory SecureTransferFinalizeResponse.fromMap(Map<String, dynamic> data) {
    return SecureTransferFinalizeResponse(
      ok: data['ok'] ?? false,
      tokenId: data['tokenId'] ?? '',
      newOwnerUid: data['newOwnerUid'] ?? '',
      counter: data['counter'] ?? 0,
    );
  }
}

/// Pending transfer document
class PendingTransfer {
  final String fromUid;
  final String? toUid;
  final int nNext;
  final String? hNext;
  final DateTime expiresAt;
  final String state;
  final DateTime createdAt;

  PendingTransfer({
    required this.fromUid,
    this.toUid,
    required this.nNext,
    this.hNext,
    required this.expiresAt,
    required this.state,
    required this.createdAt,
  });

  factory PendingTransfer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PendingTransfer(
      fromUid: data['fromUid'] ?? '',
      toUid: data['toUid'],
      nNext: data['nNext'] ?? 0,
      hNext: data['hNext'],
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      state: data['state'] ?? 'UNKNOWN',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  bool get isOpen => state == 'OPEN';
  bool get isExpired => DateTime.now().isAfter(expiresAt) || state == 'EXPIRED';
  bool get isCommitted => state == 'COMMITTED';
}

/// Exception thrown by secure transfer operations
class SecureTransferException implements Exception {
  final String code;
  final String message;
  final dynamic details;

  SecureTransferException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() {
    return 'SecureTransferException: $code - $message';
  }

  /// User-friendly error messages
  String get userFriendlyMessage {
    switch (code) {
      case 'unauthenticated':
        return 'Please sign in to continue';
      case 'permission-denied':
        return 'Only the current owner can initiate transfers';
      case 'failed-precondition':
        if (message.contains('already pending')) {
          return 'A transfer is already in progress for this SwapDot';
        } else if (message.contains('No pending transfer')) {
          return 'No active transfer found for this SwapDot';
        } else if (message.contains('not OPEN')) {
          return 'This transfer has already been completed or expired';
        }
        return 'Transfer conditions not met';
      case 'not-found':
        return 'SwapDot not found';
      case 'deadline-exceeded':
        return 'Transfer expired. Please start a new transfer';
      case 'aborted':
        return 'Ownership changed during transfer. Please try again';
      default:
        return message;
    }
  }
}
